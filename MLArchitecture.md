# MPS Execution Architecture

What every MPS SPM package (MPS-MediaPipe, MPS-ZipDepth, and any future one) and every Fabric node that wraps one is required to do — settled, not up for silent re-litigation.

## Contents

1. [Who owns a command buffer, who commits it](#who-owns-a-command-buffer-who-commits-it)
2. [The crash this caused, and the actual fix](#the-crash-this-caused-and-the-actual-fix)
3. [What every MPS SPM package must expose](#what-every-mps-spm-package-must-expose)
4. [What every Fabric node built on one must do](#what-every-fabric-node-built-on-one-must-do)
5. [Sync vs. async — the real tradeoff](#sync-vs-async--the-real-tradeoff)
6. [API symmetry between packages](#api-symmetry-between-packages)

## Who owns a command buffer, who commits it

**RULE: A command buffer is committed exactly once, by whoever created it — never by code it merely passes through.**

Fabric's shared per-frame buffer is created once, as a genuine `MPSCommandBuffer`, by `GraphRenderer.preDraw()` (overriding Satin's `Renderer.preDraw()`), and committed once by Satin's own `postDraw()` after every node has finished encoding onto it. A node that needs a dedicated buffer for synchronous work creates its own `MPSCommandBuffer` and owns that buffer's commit — nothing else does.

**RULE: An MPS SPM package never wraps, and never commits, the command buffer it's given. Full stop.**

`encode()`/`submit()` take an `MPSCommandBuffer` directly (not `MTLCommandBuffer`) and use exactly the instance the caller passed in — no internal `MPSCommandBuffer(commandBuffer:)` construction, no `commit:` parameter, no call to `.commit()` or `.commitAndContinue()` anywhere in package code. Committing is entirely the caller's decision and the caller's action, on an object only the caller holds.

## The crash this caused, and the actual fix

Real crash, from the synchronous branch of `MediaPipeFaceDetectionNode.detect()`, before this design was settled:

```
#6  -[_MTLCommandBuffer addCompletedHandler:] (assertion)
#7  -[CaptureMTLCommandBuffer _preCommitWithIndex:]
#8  -[CaptureMTLCommandBuffer commit]
#11 MediaPipeFaceDetectionNode.detect(...) — targetBuffer.commit()
```

That signature — an assertion *inside Metal's own commit bookkeeping* — meant `targetBuffer` was already committed by the time the node's explicit `.commit()` ran. At the time, the node passed a plain `MTLCommandBuffer` into the package, and the package internally did `MPSCommandBuffer(commandBuffer: commandBuffer)` to satisfy `MPSGraphExecutable.encode(to:)`'s type requirement. `MPSGraphExecutable.encode(to:)` can call `commitAndContinue()` on that buffer internally, depending on the compiled graph (deterministic per graph, not random). When it did, it committed the underlying buffer and continued on a new one — but only the package's temporary, internal wrapper knew about the continuation. The node was still holding its own separate reference to the original (now-committed) buffer, and its later `.commit()` call crashed on it.

**The actual fix is not "let the package commit for you" — an earlier `commit: Bool` design was tried and rejected for exactly that reason.** The real fix is that the package must never create that second, temporary wrapper in the first place. If the caller passes in the *one* `MPSCommandBuffer` instance it already owns, and the package uses that exact instance with no wrapping, then whatever `commitAndContinue()` does internally happens to the object the caller is holding. An `MPSCommandBuffer`'s contract is specifically to remain valid and commit-able across such continuations — so the caller's own later `.commit()` call, on that same instance, is always correct, regardless of how many internal continuations happened underneath it.

This is also why Fabric's shared per-frame buffer is created as a genuine `MPSCommandBuffer` at its single point of creation (`GraphRenderer.preDraw()`) rather than wrapped locally by whichever node happens to call an MPS package first: only one wrapper may ever exist for a given buffer's lifetime, held by whoever also performs its final commit. Wrapping it anywhere else — inside a node, inside a package — creates a second instance nothing downstream knows about, and reintroduces the same crash somewhere else in the frame.

## What every MPS SPM package must expose

**`run(inputBuffer:)`**
- Fully synchronous, CPU readback.
- `throws` — validates buffer size before touching the GPU.
- Not buffer-based: manages its own command queue submission internally, so it has no caller-buffer ownership question at all.

**`submit(..., commandBuffer: MPSCommandBuffer, completion:)`**
- Async, CPU-readback via completion.
- `throws` for invalid input (bad size, wrong device) — never silently folded into backpressure.
- Returns `false` (not an error) only when every in-flight slot is busy.
- Uses the caller's `MPSCommandBuffer` as-is; never commits it.

**`encode(..., commandBuffer: MPSCommandBuffer)`**
- GPU-resident, no CPU readback at all.
- Same validation and backpressure contract as `submit()`.
- Slot releases on the buffer's actual GPU completion, not a CPU wait.
- Uses the caller's `MPSCommandBuffer` as-is; never commits it.

**Validation, every entry point**
- Input buffer length checked against the tensor's required bytes.
- Each output buffer length checked individually.
- Command buffer's device checked against the model's device.
- All of it `throws` — a wrong-sized buffer is a programmer error, not transient state.

| Method | Real error | All slots busy |
|---|---|---|
| `run()` | `throws` | blocks briefly (sync anyway) |
| `submit()` | `throws` | returns `false`, doesn't throw |
| `encode()` | `throws` | returns `false`, doesn't throw |

The split matters: an invalid call is a bug, surfaced immediately. Backpressure is expected, recoverable state — a dropped frame, not an exception.

## What every Fabric node built on one must do

**DO** encode async work directly onto Fabric's shared per-frame command buffer. Recover the real `MPSCommandBuffer` instance with `commandBuffer as? MPSCommandBuffer` (a cast, not a new wrapper — `GraphRenderer.preDraw()` guarantees it already is one) and pass that into `encode()`/`submit()`. Never commit it — it isn't this node's buffer.

**DO**, for a synchronous result, construct a dedicated buffer this call owns exclusively — `MPSCommandBuffer(from: self.context.commandQueue)` — and pass that same instance into `encode()`/`submit()`. Once encoding is done, the node calls `.commit()` and `.waitUntilCompleted()` itself, directly on that same instance. This is safe specifically because no wrapper was ever created inside the package around it — see §2.

**NEVER** call `.commit()` on a plain `MTLCommandBuffer` the node itself wrapped locally, or on the shared buffer. If a buffer needs committing, it must be an `MPSCommandBuffer` the node constructed once and holds the only reference to.

**DO** keep lifetime capture on completion handlers for anything the texture cache might recycle: `commandBuffer.addCompletedHandler { [weak self, image] _ in withExtendedLifetime(image) {} }` — `GraphRendererTextureCache` recycles a managed image the instant its last Swift reference drops, with no regard for whether the GPU is still using it.

## Sync vs. async — the real tradeoff

Not a preference — a real, named cost either way. Pick deliberately.

**Async (default)**
- Zero CPU wait, no pipeline bubble.
- Steady-state one frame of latency on the numeric result.
- Inference slot only releases once the *whole frame's* shared buffer completes — under heavy per-frame GPU load, slots can starve, causing irregular, not just delayed, updates.

**Synchronous (dedicated buffer)**
- Same-frame numeric result, no latency.
- Real, bounded CPU stall (this model's own GPU time — sub-millisecond for these models).
- Slot releases fast, tied only to this node's own small buffer — no frame-load interference.

Sync/async is only a meaningful choice for nodes with **numeric CPU-readback outputs** (landmarks, regions, rotations) — image-resident GPU data flows through the graph at full current-frame speed regardless, so it's only the CPU-readback numerics that can visibly lag a frame behind on fast-moving input. Nodes with only image outputs (MPS image/compute processing, ZipDepth, Selfie Segmentation's mask) have **no sync/async switch at all**: they always encode directly onto whatever buffer they're given, with no CPU readback to desync in the first place.

Currently a compile-time flag per node (`private static let synchronousInference = false`) — not a port — until Fabric has a systemized protocol for per-node sync/async execution. Iterator usage forces `synchronous = true` unconditionally: each iteration needs its result before the next one runs, which the async path structurally cannot deliver in time.

## API symmetry between packages

MPS-ZipDepth and MPS-MediaPipe match on every point above: same method shapes, same `MPSCommandBuffer` parameter, same validation/throws/backpressure split. The one deliberate difference is `outputBuffer:` (singular) in ZipDepth vs. `outputBuffers: [MTLBuffer]` in MediaPipe — not an inconsistency, just each model's real tensor count (one output vs. several). Forcing ZipDepth into an array-of-one would be ceremony with no benefit.
