# Fabric / Satin frame contract (draft 4, async-delivery clarification 2026-10-23)

Single-threaded. Principle 1 (host and rendering never block each other) is deferred, not dropped: every piece of state still has one owner, so threading can be added later.

## The invariant everything rests on

**Memory that pending GPU work reads is never rewritten, including across in-flight frames and command-buffer segments.** GPU command order follows graph order; correctness across iterations comes from not overwriting, not from waiting. Nothing waits on the GPU unless a node asks for a result in the same frame (§5).

The rule that delivers it, for every node output (images, geometry, buffers):

**A published output is immutable.** New content goes into new memory; unchanged content is the same output, retained, not copied. As in Quartz Composer, where image providers are immutable.

- A static image, or a movie frame for one graph time, reused across N iterations: one texture, retained N times.
- An effect run each iteration: N images, one per iteration, each with its own memory (`newImage`).
- Static geometry: one geometry, reused. Dynamic geometry whose inputs change per iteration (iteration progress driving an animated mesh's frame): a new geometry or vertex buffer per change, so frames already submitted keep theirs.
- Image storage comes from the context's GPU allocator (Satin `GPUAllocator`): automatic heaps shared by every renderer handed that context. Each image version gets a distinct texture object; ports, materials, recordings and Metal command buffers keep that texture's allocation alive through their own ownership. Heap memory becomes reusable only after the last texture owner releases it, across every in-flight frame and command-buffer segment. There is no global texture-recycling hold. Retained ownership does not make published contents writable.
- A logical frame may span multiple underlying command buffers. Completion of an earlier segment must not release memory needed by a later segment. Abandoning a frame releases unused resources, but resources used by already-submitted work stay alive until that work completes.

## 1. Iterator: values and draws

- Each iteration records its Satin draws as it is then: transforms, material uniforms, geometry and instances are snapshotted per record. A red sphere at A and a blue sphere at B are both drawn, each with its own uniforms and lighting.
- Iterated draws join the frame's one scene pass, alongside root objects (§3).
- Iterated objects are lit by every light in the frame and cast shadows onto everything. Shadows are rendered once all of the frame's casters are known, before the scene pass.
- A light inside an Iterator is one light per iteration: N lights, N shadow casts. Allowed, if costly.
- **Known limitation:** Satin's light and shadow-caster limits still apply. An Iterator that multiplies lights past them isn't supported; documented, pointing at deferred rendering.

## 2. Iterator: raw GPU work

- Raw Metal, MPS and Satin compute work is encoded into the frame's command buffer in graph and iteration order.
- Raw work never blocks between iterations; the immutability rule keeps each iteration's results intact.
- Satin-owned read-only GPU inputs (uniforms, registered buffers, compute inputs) are copied or ring-snapshotted per record or dispatch, never rebound live. Compute buffers that reset or update kernels can write bind their original storage; copying them would hide the kernel's outputs. Shader reflection determines access, with unknown access treated as potentially writable. Producers must version writable outputs before publishing new contents, and must not overwrite storage pending GPU work still reads.

## 3. Layering

- Satin does no depth sorting across the graph; depth testing applies, and `renderOrder` orders draws.
- Iterated objects draw in graph order, in one pass with root objects, respecting `renderOrder`. Ties within a `renderOrder` resolve as today.

## 4. Render to Image

- An Iterator inside Render to Image: one texture, drawn by the same rules as a root Iterator, into that target.
- Render to Image inside an Iterator: one image per iteration.
- Every time Render to Image draws, at any nesting level, it produces a unique Fabric Image with its own memory, through `newImage`. It encodes its pass when it executes, so its output is in the command buffer before anything downstream reads it.

## 5. GPU results now or later

Use case: a node computes on the GPU and outputs a CPU value (MPS face detection outputting keypoints).

- **Deferred (non-blocking, also called next-frame delivery):** the node encodes without waiting for its result. GPU completion marks a request ready. The execution owner subsequently processes its completion closure and stages its output values; those values become visible at the next CPU execution of the matching node and iteration context after processing. Frame N's analysis is not guaranteed to appear in frame N+1: completion and matching execution may occur later. Delivery never injects values into an execution already in progress.
- **Same frame (synchronous):** the node commits the GPU work encoded so far (including its inputs' work) and waits for it, then outputs the result in frame N. Nodes downstream see it in the same frame. The wait is coordinated by the rendering owner. With Principle 1 implemented that owner is separate from the host; this document currently defers that separation rather than claiming an execution owned by the host cannot block the host.
- The frame's command buffer is an `MPSCommandBuffer` (required: Sight's MPS and MPSGraph work needs it). `commitAndContinue()` commits the work so far and keeps the same object, which can carry the synchronous mode without changing node signatures. PR #414 introduces the `MPSCommandBuffer`; its other details are not the spec.
- **Synchronous readback boundary:** finish active command encoders, capture the current `rootCommandBuffer`, call `commitAndContinue()`, then wait for the captured buffer and check its completion status/error before reading the result. Perform any synchronization required by the resource's storage mode before reading. Waiting on the `MPSCommandBuffer` wrapper after `commitAndContinue()` would target its new, uncommitted buffer instead. Continue encoding through the same wrapper after a successful readback.
- The rendering owner coordinates this boundary, resource lifetimes and errors. Completion handlers attached before `commitAndContinue()` belong to the submitted segment; resources used by subsequent segments must remain retained through those uses. Only the final segment presents the frame.
- Consistent with §4: Render to Image encodes when it executes, so a same-frame analyzer reading a Render to Image's output sees it. The root scene pass is encoded last, so analysing the frame's own final image is necessarily next-frame.
- The choice can be the user's and can change while running (principle 6). Deferred request storage and published results obey the same immutability rule; a fixed two-buffer ring alone does not establish safe reuse.

### 5.1 Deferred completion API and ownership

- The public operation is `try commandBuffer.addCompletion { ... }`, exposed on the existing `MTLCommandBuffer`-typed node argument and backed by Fabric's graph command buffer. It is distinct from Metal's `addCompletedHandler`. Plugins receive the same operation as built-in nodes. Registration outside active node execution or on a non-Fabric buffer throws before submission.
- A node encodes raw Metal/MPS/Satin work normally, then registers a closure that decodes request-owned readback storage and uses existing typed `output.send(...)` operations. No pending-value port types, special node superclass, or node-specific Iterator bookkeeping is required.
- Registration captures an immutable binding to the active node and result scope, its generation, and request order. It must not retain the mutable `GraphExecutionInfo` as the identity snapshot. GPU completion handlers only mark readiness/failure and notify admission; all decoding, graph mutation, and port publication occur on the execution owner.
- Each Iterator owns reusable per-iteration result scopes. Nested Iterator storage is partitioned by its enclosing scope, so inner iteration 0 under different outer iterations is independent. Outside Iterators, the graph renderer owns the default result scope. Contexts identify execution slots, not semantic identities such as tracked people.
- A scope retains pending requests and the last prepared/published values for participating node outputs. Actual registrations and sends identify participating outputs: no graph-wide port scans, and no per-frame reconstruction of UUID-keyed context dictionaries. Stable repeated paths use reusable scope/node handles.

### 5.2 Completion processing versus publication

- At owner-controlled boundaries between executions, ready completion closures are processed under their captured scope. Their `output.send` calls stage typed output values; they do not immediately mutate live port values, notify consumers, or execute downstream nodes. Ordinary sends outside deferred completion processing keep their current immediate behavior.
- At entry to the next matching node execution, the renderer restores that scope's output state and publishes its staged changes as one delivery before the node body and downstream consumers execute. Completion processing that occurs after an execution starts cannot affect that execution. Delivery itself makes the source eligible even if its ordinary inputs are clean.
- The initial deferred value is absent. Thereafter each iteration retains its last completed output state until replaced. Switching iterations restores the correct state, including clearing outputs absent in that scope, rather than inheriting another iteration's live port values. Restoration concerns registered deferred outputs only.
- All sends from one successful completion form a delivery group. If decoding fails, its staged sends are discarded and the graph's error handling receives the failure; consumers do not observe a partial group. Requests are processed in submission order per node/context. If several complete before the next matching execution, the prepared output state reflects their ordered sends, as ordinary state-valued ports do; this is not a promise to execute consumers once for every intermediate result.
- Stopping/removing a node, removing a destination port/iteration, or changing delivery mode/relevant settings invalidates affected pending delivery generations. Invalidated requests cannot publish into replacement contexts. Their submitted resources remain alive until their GPU segments finish. A context that is not executed does not independently run consumers just because a result completes.

### 5.3 Bounded frame batches and resources

- One logical frame batch owns all its accepted completion registrations, including every Iterator invocation and every command-buffer segment. The current admission target is three outstanding logical frame batches, not three individual inference requests. No per-node semaphore, silent result dropping, or automatic synchronous fallback is introduced.
- Batch storage is reusable after CPU recording has ended, every submitted segment is complete (or an unsubmitted segment is abandoned), and its completion closures have been processed or cancelled. Decoded values transfer ownership into their result scopes; a batch need not stay occupied until those values are published by a future matching execution. Storage still referenced by a decoded/published value remains owned and cannot be overwritten on batch reuse.
- Ready completion processing must be serviced before waiting for admission and after GPU progress wakes admission. Never wait for a free slot whose release requires callbacks on the blocked execution owner. Frame-admission backpressure is distinct from waiting for a particular node's readback. The existing frame admission must be integrated with this rule rather than assuming GPU completion alone bounds undelivered results.
- Display-driven and offscreen execution must participate in the logical-frame admission/lifetime contract; the graph command-buffer factory and display entry both participate in batch accounting. Nested renderers/Iterators share their enclosing logical frame batch; `commitAndContinue()` does not consume a new frame slot.
- Request-owned readback and model scratch memory remain independent for every pending invocation. Three admitted frames with N invocations may require 3N request allocations. Fixed-capacity model packages must be adapted to this ownership rule; the completion API does not itself increase their scratch capacity. Allocation failures are reported, not hidden by reusing live memory or forcing synchronous mode.

### 5.4 Swift performance constraints

- **Dormant path:** graphs that do not register deferred work allocate no async-result storage and perform no async scans, readiness polling, or bookkeeping loops. Synchronous Iterator execution does not create async scopes. Any required execution-context binding or send-mode branch must remain minimal and must not trigger lookup, allocation, or ownership churn.
- **Direct ownership and addressing:** result storage belongs directly to its Iterator/default graph scope and frame batch. No global node/port/context side tables, hot-path dictionaries, UUID hashing, string construction, or named-port searches. Repeated contexts use cached integer handles and array slots. Dynamic setup and growth happen only when participating contexts/output schemas or required capacity change.
- **Ownership cost:** no newly introduced weak/delegate/Combine chains for request registration, readiness or publication. Use explicit owner lifetimes, immutable captures and generation-based cancellation; do not replace weak references with unsafe lifetime assumptions. Avoid temporary reference arrays, copy-on-write buffer copies, existential boxing and redundant retain/release chains. Profile Swift slow reference-count paths rather than assuming strong references or structs eliminate them.
- **Reuse and synchronization:** reuse batch/request metadata, typed output storage capacity and safely retired readback buffers. Do not allocate an extra heap wrapper/closure for each output send or reconstruct typed setter closures every frame. GPU-to-owner readiness is the only required cross-thread handoff; synchronize that handoff correctly, without per-port locks, per-node semaphores, queue dispatch per send, or locks on ordinary scope lookup/publication. New output content and escaping callback captures may require allocation: measure and distinguish those costs rather than promising impossible blanket allocation freedom or overwriting pending memory to achieve it.
- **Verification:** compare Release allocation/CPU profiles for an ordinary graph, a synchronous Iterator, async outside Iterator, and a warmed-up nested async Iterator at a fixed workload. Show dormant-path costs and request/capture allocation counts separately. Repeated publication must introduce no dictionary hashing or named-port work. Reject a design whose warmed-up bookkeeping repeatedly allocates/rebuilds containers or merely relocates expensive Swift ownership operations to another call stack. Correctness and safe lifetime remain mandatory.

## Open

1. **Settings surface and adoption.** A consistent user-facing same-frame/deferred setting and migration of existing analyzers remain. The completion API does not automatically migrate nodes using the earlier readback helper.
2. **Enforcing immutability.** Writing into an already-published output can't be detected for raw Metal in general. Decide whether debug builds check what they can (for example, `newImage` outputs marked published), or whether the rule lives in docs and the node templates only.
