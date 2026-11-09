RenderEncoder# MPS Packages: Combined Improvement Plan

Combines `CLAUDE_MPS_SUGGESTIONS.md` and `CODEX_MPS_SUGGESTIONS.md`, re-checked against the code and the macOS SDK headers. Plan only; no code changes.

Goals, in order: **bug free → correct → faster → ANE-capable**. Each phase is gated on the one before it. A speed-up we can't measure or verify for accuracy doesn't count.

---

## What changed after re-checking

1. **MPSGraph can place work on the ANE. Both earlier documents were wrong about this.** `MPSGraph.h` says `MPSGraphOptimizationLevel1` "performs additional Optimizations, like using the placement pass to dispatch across different HW blocks like the NeuralEngine and CPU along with the GPU." Every package already compiles at `.level1`, so the placement pass already runs. There is no public API to force the ANE. What decides placement is whether the graph is *eligible*: float16/int8 tensors, rank ≤ 5, static shapes, and ops the ANE supports. Every graph today is float32, and the ANE cannot run float32, so placement almost certainly keeps everything on the GPU. **Float16 is the gate for both speed and the ANE.** CoreAI drops to an optional side experiment (preliminary API, requires OS 27, not installed here).
2. **`reducedPrecisionFastMath` is macOS 26 / iOS 26 only.** The SDK header confirms it. On the macOS 15 dev machine, the `#available` branches in ZipDepth, MediaPipe, FlashDepth and TAPNext do nothing. It also wouldn't make tensors float16 for ANE placement even where it's available; it only allows float16 intermediates in some GPU kernels.
3. **`optimizationProfile = .powerEfficiency` is deprecated since macOS 14.** The header says `.level1` handles power automatically. Don't use it.
4. **Command-buffer contract (Codex finding, confirmed).** `MLArchitecture.md` says packages take the caller's `MPSCommandBuffer`, never wrap it, never commit it, and have no `commit:` parameter. MediaPipe violates all of these. FlashDepth wraps a temporary inside `encodePipeline` (`FlashDepthMPSGraph.swift:417`). ZipDepth reuses the caller's wrapper correctly but still has a `commit:` parameter. This becomes more urgent once ANE placement is possible: moving between accelerators is exactly what forces MPSGraph to split work across command buffers internally (`commitAndContinue`).
5. **float32 constants silently block ANE eligibility.** ZipDepth's `scalar`/`channelConstant`, MediaPipe's `graph.constant(3.0, dataType: .float32)`, and every `*Weights.constant` produce float32 tensors. Per the skill's "no fp32 literals" rule, any one of these forces a cast or a float32 region.
6. **Rank-6 intermediates (Codex finding, confirmed).** MediaPipe `DEPTH_TO_SPACE` reshapes to rank 6 (`MediaPipeMPSGraph.swift:746`). EfficientTAM window partitioning reshapes to `[1,3,14,3,14,192]` (`EfficientTAMImageEncoder.swift:433`). The ANE's limit is rank 5.
7. **Items to re-verify.** Codex's "16 crop buffers per node (~12 MiB)" doesn't hold for `MediaPipeHandLandmarkNode`, which uses the preprocessor default of 3. Check each node's actual count before changing anything.

---

## Phase 0: Measurement harness (before any change)

Without this we can't tell whether a later change helped, or whether the ANE is actually being used.

- **0.1 Per-package baselines.** Record these for each model at its shipped resolution:
  - GPU time (Metal System Trace)
  - CPU encode time
  - cold compile and specialize time
  - peak and steady-state memory
  - end-to-end node latency
  - number of `commitAndContinue` calls / command buffers per frame (visible in the trace)
  - package benchmarks already exist for TAPNext, TAPIR, EfficientTAM (temporary) and ZipDepth tests
- **0.2 Placement observability.** Build a standard recipe to answer "did anything run on the ANE?":
  - Instruments with the Neural Engine / Core ML activity tracks alongside the Metal System Trace
  - `powermetrics` ANE power while the benchmark runs
  - `graph.options = .verbose` to see what placement MPSGraph logs

  Validate the recipe once on a known ANE-eligible toy graph (a float16 conv stack) so that a negative result on a real model means something.
- **0.3 CoreML as a placement oracle, not a runtime.** Apply the `inspect_coreml_compute_plan` tool (in MPS-TAPNextPlusPlus) to throwaway CoreML exports of ZipDepth and one MediaPipe model. `MLComputePlan` reports per-op ANE eligibility, which tells us which ops to re-author before trying MPSGraph placement. This respects the MPS-first policy: CoreML is only used as a diagnostic.
- **0.4 Accuracy gates** (from the skills plus the existing tests):

  | Change | Gate |
  |---|---|
  | Exact graph surgery (BN folding, reparameterization) | Existing differential tests unchanged; > 70 dB PSNR against the current float32 build |
  | Float16 / mixed precision | > 50 dB against the float32 reference (investigate below 40 dB); existing max-error thresholds must still pass |
  | 8-bit weights | ≥ 50 dB |
  | 4-bit weights | ≥ 35 dB |
  | Temporal models (FlashDepth, TAPNext, TAPIR, EfficientTAM) | Must pass over a *multi-frame* sequence, not a single frame; float16 drift accumulates |

---

## Phase 1: Bugs and correctness

### 1.1 One command-buffer contract across all packages
Target the API in `MLArchitecture.md`: `encode(..., commandBuffer: MPSCommandBuffer)` and `submit(..., commandBuffer: MPSCommandBuffer, completion:)`, with no `commit:` parameter, no internal wrapping, and completion handlers attached to the caller's wrapper **after** graph encoding.
- **MediaPipe** (`MediaPipeMPSGraph.swift`): all three entry points need the change. `encode()` currently adds its slot-release handler to the raw buffer *before* encoding. If MPSGraph commits partway through, the slot is released early, while the graph's last segment is still in flight.
- **FlashDepth**: remove the temporary wrapper in `encodePipeline`. `continuingBuffer(after:)` becomes unnecessary once the caller's wrapper is used directly.
- **ZipDepth, TAPNext, TAPIR, EfficientTAM**: remove the `commit:` parameter and the "wrap if not already an MPS buffer" helpers.
- **Nodes**: async paths cast Fabric's buffer with `commandBuffer as? MPSCommandBuffer`. Sync and iterator paths create `MPSCommandBuffer(from: queue)`, then commit and wait on *that* instance. This also fixes the sync branches in the MediaPipe nodes, which currently wait on a raw buffer that may not be the graph's final segment.
- `run()` stays as-is for tests.
- Symmetric API across packages is a standing goal, so all packages change together.

### 1.2 Per-flight output buffers in MediaPipe nodes
Detection and landmark nodes each hold one set of `storageModeShared` output buffers. The completion handler reads them while a later frame, admitted because the model has 16 slots, can already be writing them. The fix is a small per-node ring sized to the renderer's frames in flight, following the TAPIR readback ring in `TAPIRPointTrackingNode.swift`. A slot is acquired with the inference slot and released after the handler has copied the data out. If no slot is free, drop the frame, consistent with the existing drop-on-backpressure behaviour.

### 1.3 FlashDepth's "concurrent shader compile causes numerical divergence"
`FlashDepthShaderCompilation.synchronized` works around a symptom. Metal shader compilation is expected to be thread-safe, so a numerical difference more likely points at a real race or at uninitialized memory in a kernel or scratch buffer that shows up under different timing. The plan:
- (a) Precompile `.metal` into the package's bundled metallib so runtime `makeLibrary(source:)` disappears. This also cuts cold start.
- (b) Separately, run the FlashDepth differential tests with Metal API Validation and the shader validation layer turned on, to look for the underlying race or out-of-bounds access.

Don't treat (a) as fixing (b).

### 1.4 Remove per-frame allocations and render-thread compiles
- **EfficientTAM node**: allocates its ~3 MiB model input buffer every frame (`EfficientTAMTrackerNode.swift:344`). Pool it with a ring (CLAUDE.md: "avoid allocations").
- **`SharedModelCache`**: holds its lock while compiling (~1 s), and `prepareModel` can run from `execute`. This blocks the render thread and every other lookup in that model family. Move to once-per-key asynchronous construction: the node shows no output until its model is ready, instead of stalling the frame. Settings changes should trigger the compile, not the first `execute`.

### 1.5 Timing labels
`MediaPipeInferenceTimingLogger` measures from submission to completion of the *whole frame*. Rename it or document it as frame latency, and add GPU timestamp counters where the true per-model time is needed.

---

## Phase 2: Precision (a prerequisite for both speed and the ANE)

### 2.1 Weight storage and loading (all packages)
- The exporters write float16 (keeping float32 only for tensors the precision policy marks as sensitive), with the dtype recorded per tensor in the manifest.
- The loaders pass `Data` slices of the memory-mapped file straight to `graph.constant`. This removes the current `Data → [Float] → Data` double copy (about 3× peak memory at load for TAPNext's 741 MiB).
- Remove the per-constant `Float16Storage.bitPattern` conversion at load; the exporter writes float16 directly.

### 2.2 Explicit float16 compute, per model
Use TAPNext's `mixedFloat16` casting style, since it works on macOS 15, and make it a shared precision policy:
- **float16:** convolutions, linear/matmul, activations, pooling, resize, elementwise
- **float32:** normalization statistics, softmax and attention scores, recurrent/SSM state and its update math, prediction heads, public I/O buffers where consumers need float32

Per model:
- **ZipDepth:** float16 across the whole graph, including input and output, is plausible. Conv, BN and ReLU tolerate float16 well. This is also the ANE candidate (Phase 4).
- **MediaPipe:** float16 across the whole graph (these are TFLite float16-trained mobile models).
- **FlashDepth:** float16 storage for weights and activations with float32 accumulation (Phase 3).
- **EfficientTAM:** one stage at a time, never as a blanket conversion. Start with the conv-heavy memory encoder and mask downsampler; keep the transformer in float32.
- **TAPNext / TAPIR:** already mixed; only 2.1 applies.

All MPSGraph constants and scalars (`scalar`, `channelConstant`, activation constants) must use the tensor's own compute dtype. This is required for ANE eligibility (finding 5) and removes the casts MPSGraph currently inserts.

---

## Phase 3: Faster (exact graph surgery, then kernels)

### 3.1 ZipDepth: exact offline reparameterization (exporter side)
- Fold BN into every preceding conv.
- Merge the QARep 3×3 conv, 1×1 conv and identity branch into one 3×3 conv plus bias (16 blocks).
- Merge `minimalMultiScale`'s depthwise 3×3 plus dilation-2 depthwise 3×3 into one depthwise 5×5, then fold its BN.
- Move mean/std normalization into the preprocessing kernel.
- Resulting graph: roughly conv → ReLU chains, which is ideal for both the GPU and the ANE.

### 3.2 TAPNext: fuse matrix multiplies (exporter plus graph)
- `linear_x` and `linear_y` → one matmul, then split.
- `ffw_up`'s two slices → one `[768, 6144]` matmul.
- Precompute the RMSNorm `scale + 1` and all weight transposes offline. The graph-build-time transposes of constants go away.

### 3.3 Preprocessing writes the model's native layout
The crop, ZipDepth, FlashDepth and EfficientTAM preprocessors write NCHW in the model's compute dtype, already normalized. This removes the transpose at the head of every graph (the ANE skill penalizes transposes of the innermost dimension in particular).

### 3.4 FlashDepth hand-written kernels
In order:
1. **Matrix multiply** (`flashDepthLinear`, `flashDepthPostViTLinear`): `simdgroup_matrix` (Apple7+/M1+), half inputs and float32 accumulation, several outputs per thread. Also fuse the bias, GELU, LayerScale and residual into the kernel's final step, which removes 24 dispatches and their memory round trips per frame.
2. **Attention**: the current kernel keeps `q[64]` and `acc[64]` in float32 registers per thread and rescales with `exp` after every key. Rewrite it to compute QKᵀ and PV with simdgroup matrices over a K/V tile, rescaling once per tile, with half K/V tiles.
3. **LayerNorm**: move the statistics into the prologue of the following matrix multiply, or at least read each row only once.
4. **Post-ViT convolutions**: replace the direct convolutions with an implicit-GEMM conv using the same simdgroup matrix multiply core.
5. **Mamba SSD**: move from one threadgroup to a head-parallel dispatch.

Re-trace after each step; the goal is GPU time, measured.

### 3.5 Node-level copies
ZipDepth's output blit becomes a texture created directly over the output buffer (`makeTexture(descriptor:offset:bytesPerRow:)`, respecting `minimumLinearTextureAlignment`). Do the same wherever a model writes a single-plane image.

### 3.6 Iterator batching (MediaPipe landmarks)
Instead of N synchronous command buffers per frame, compile a landmark executable for a fixed batch size (`maxHands` / `maxFaces`), with unused entries padded and masked. The result is one submission and one wait. (The ANE skill's "one function per static shape" rule applies equally to batch size.)

---

## Phase 4: ANE through MPSGraph placement

Starts only after Phases 1 to 2 (float16 is required) and 3.1 (fewer, higher-level ops).

### 4.1 Eligibility checklist (from `neural_engine_rules.md`, adapted to MPSGraph)
- float16 or int8 tensors throughout the region, with no float32 constants (Phase 2)
- rank ≤ 5 everywhere
  - MediaPipe `DEPTH_TO_SPACE` → `graph.depthToSpace2D(... usePixelShuffleOrder: false)` (TF channel order); confirm the order with the existing differential test
  - EfficientTAM window partition → drop the leading batch-1 dimension so the reshape and transpose stay rank 5
- static shapes (already true everywhere)
- stride factors of 2 and 3, and pooling stride 2 or 4. ZipDepth complies. FlashDepth's patch embed uses stride 14 and TAPNext's uses stride 8, which is fine; 14 = 2×7 is not.
- innermost dimension ≥ 32 float16 elements and 64-byte aligned. NCHW widths at deep stages are small (ZipDepth at 384 input gives W = 12 at the 1/32 stage). Measure whether those stages stay on the ANE; if not, consider an NHWC variant or accept a GPU tail.
- prefer high-level ops. `normalize` and `softMax` over the channel axis are better than hand-decomposed reductions. ZipDepth's `globalContext` softmax runs over the spatial axis, which the skill flags; it runs at 1/16 resolution, so check placement before re-authoring it.
- minimize casts, reshapes and transposes (Phase 3.3)

### 4.2 Order of experiments
1. **ZipDepth, the whole graph.** Designed as an NPU graph, conv-only after 3.1. Success means the whole graph is ANE-resident, GPU time for the node drops to near zero, and end-to-end latency is acceptable.
2. **MediaPipe detectors and landmarks** (one checkpoint first). Small models: the ANE's fixed dispatch overhead may cost more than the ~0.5 ms GPU time. The main win is freeing the GPU for rendering and saving energy on iOS and visionOS.
3. **TAPIR feature extractor** (a conv backbone), keeping the refinement and state parts on the GPU. Only worth it if the trace shows the transfer between accelerators is cheap.
4. **Not candidates for now:**
   - FlashDepth: its hand-written Metal cannot be placed on the ANE, so an ANE version would mean rebuilding the ViT as an ANE-shaped MPSGraph (per-head attention, 1×1 convs)
   - EfficientTAM: float16-sensitive transformer
   - TAPNext: 741 MiB, recurrent, float16-sensitive

### 4.3 Hypothesis to test early
FlashDepth's post-ViT MPSGraph version spent most of its CPU time in `GPURegionRuntime::encodeOpWithCommitAndContinue`. "Region" suggests the level-1 placement pass split the graph into segments, each committed separately. Test this: compile the same graph at `.level0` (no placement pass) and compare command-buffer counts. If it holds, two things follow:
- (a) partial ANE/CPU placement has a real CPU cost, so a graph should be either entirely eligible or deliberately kept on the GPU
- (b) `.level0` is the right setting for graphs we deliberately keep on the GPU, which could remove the internal commits the command-buffer contract has to cope with

### 4.4 Scheduling implications
- Once ANE regions exist, `encode()` will use `commitAndContinue` more often; this is why 1.1 must come first.
- Completion times move later, so model slots are held longer. Size the in-flight capacity to measured latency, not to a guess.
- Success metric: GPU time freed per frame plus end-to-end latency. Raw inference time on its own is not the measure.

### 4.5 CoreAI (optional)
Only if MPSGraph placement refuses a graph the Phase 0.3 oracle says is eligible. It needs OS 27, has no command-buffer integration, and its API is preliminary. Treat it as a comparison point only.

---

## Phase 5: Weight compression (memory first, then speed)

MPSGraph on macOS 15 / iOS 18 supports `dequantize(_:LUTTensor:axis:)` (4-bit and 8-bit lookup tables) plus scale and zero-point dequantization (confirmed in `MPSGraphQuantizationOps.h`).
- **TAPNext and TAPIR first** (largest). Compress per channel, leave the first and last layers and each sub-module's input/output projections uncompressed, and sweep 8-bit then 4-bit against the Phase 0.4 gates over multi-frame sequences.
- **ZipDepth** only if startup time or memory becomes a problem (it's small).
- The ANE supports lookup-table weights natively. If ZipDepth ends up on the ANE, re-check placement after compressing; the skill warns that stride support narrows with compressed kernels.

---

## Execution order and dependencies

| # | Item | Depends on | Outcome |
|---|---|---|---|
| 1 | Phase 0 harness and baselines | — | measurable |
| 2 | 1.1 command-buffer contract (all packages and nodes) | 1 | bug free |
| 3 | 1.2 MediaPipe output rings | 2 | bug free |
| 4 | 1.3 FlashDepth metallib and validation run | 1 | correct |
| 5 | 1.4 allocation pooling and async model build | 1 | correct, smooth |
| 6 | 2.1 float16 weight export and zero-copy loaders | 1 | faster load, less memory |
| 7 | 3.1 ZipDepth reparameterization | 6 | faster |
| 8 | 2.2 float16 compute plus dtype-matched constants | 6, 7 | faster, ANE-eligible |
| 9 | 4.3 level0 vs level1 region test | 2 | informs 10 and 12 |
| 10 | 4.1 / 4.2 ZipDepth on the ANE | 8, 9 | ANE |
| 11 | 3.3 native-layout preprocessing, 3.2 TAPNext fusion, 3.5 zero-copy output | 6 | faster |
| 12 | MediaPipe float16, rank-5 fix, ANE trial | 2, 3, 8 | faster, ANE |
| 13 | 3.4 FlashDepth kernels | 4 | faster |
| 14 | 5 compression (TAPNext, TAPIR) | 6 | memory |
| 15 | 3.6 iterator batching; EfficientTAM stage-by-stage float16 | 12 | faster |

Each item lands with its accuracy gate (0.4) and a before/after trace.
