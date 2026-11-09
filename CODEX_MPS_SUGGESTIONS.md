# MPS Implementation Review: CoreAI, ANE, and GPU Opportunities

This is a read-only review of the following packages and their current Fabric node integrations:

- `MPS-EfficientTAM`
- `MPS-FlashDepth`
- `MPS-MediaPipe`
- `MPS-TAPNextPlusPlus`
- `MPS-ZipDepth`

The review used the Codex `model-authoring` and `working-with-coreai` skills, their GPU and Neural Engine guidance, and the local `coreai-models` checkout. No builds or tests were run and no implementation files were changed as part of the review.

## Executive summary

The MPS implementations are generally well designed for Fabric's GPU-first architecture. They should not be replaced wholesale with CoreAI.

The strongest path is:

1. Fix the MediaPipe and FlashDepth command-buffer ownership issues.
2. Give MediaPipe CPU-output nodes per-flight output/readback buffers.
3. Optimize the existing GPU paths, especially ZipDepth inference fusion.
4. Prototype CoreAI/ANE alongside MPS for ZipDepth and MediaPipe.
5. Keep EfficientTAM and TAPNext++ GPU-first until FP16 accuracy and whole-model ANE residency are proven.

CoreAI is also not presently a deployable replacement for Fabric's existing baseline. Apple's documentation labels the API preliminary, the current ahead-of-time compilation example uses a minimum deployment version of 27.0, and the active Xcode 26.1 installation on this machine contains neither `CoreAI.framework` nor `coreai-build`. CoreAI should therefore be treated as an experimental parallel backend while MPSGraph and Metal continue to support Fabric's macOS 15, iOS 18, and visionOS 2 targets.

## Highest-priority findings

### 1. MediaPipe violates Fabric's settled command-buffer contract

Fabric creates one persistent `MPSCommandBuffer` per frame in `Fabric/Graph/GraphRenderer.swift`. The canonical contract in `MLArchitecture.md` says packages must accept that exact wrapper, never wrap it again, and never commit it.

`MPS-MediaPipe/Sources/MPSMediaPipe/Utils/MediaPipeMPSGraph.swift` currently:

- accepts `MTLCommandBuffer` rather than `MPSCommandBuffer`;
- constructs another `MPSCommandBuffer` in both `submit` and `encode`;
- adds its slot-release handler to the original command buffer before MPSGraph encoding; and
- retains a `commit:` parameter and may commit internally.

If `MPSGraphExecutable.encode` calls `commitAndContinue`, the original completion handler can fire before continuation work completes. The synchronous Fabric branches also wait on the original raw command buffer, which may no longer represent the graph's final segment.

ZipDepth now implements the correct behavior: it reuses an existing wrapper and rejects non-committing use of a plain buffer. EfficientTAM and TAPNext++ have similarly sound wrapper helpers. MediaPipe should converge on the API documented in `MLArchitecture.md`:

- `submit(..., commandBuffer: MPSCommandBuffer, completion:)`
- `encode(..., commandBuffer: MPSCommandBuffer)`
- no `commit:` parameter;
- no internal wrapping or committing; and
- completion handlers attached to the live wrapper after graph encoding.

### 2. FlashDepth has the same nested-wrapper issue

`MPS-FlashDepth/Sources/MPSFlashDepth/FlashDepthMPSGraph.swift` wraps the caller's command buffer inside `encodePipeline`. Its continuation logic then examines the outer/original command buffer rather than the persistent wrapper's current live root.

This should be corrected before a FlashDepth Fabric node is added. There is no FlashDepth source node or package dependency in the current Fabric checkout; only a serialized sample reference exists.

### 3. MediaPipe CPU-output nodes need in-flight output rings

Detection and landmark nodes allocate one persistent array of shared output buffers, then read those buffers in a command-buffer completion handler. The model permits multiple in-flight submissions, but the node output storage does not.

Later frames can begin writing the same buffers while the CPU completion handler is copying the previous result. This is a potential CPU/GPU race. Each accepted inference should acquire its own output/readback slot, analogous to the existing TAPIR readback ring in `Fabric/Nodes/Image/Analysis/TAPIRPointTrackingNode.swift`.

Selfie Segmentation is less exposed because its output remains GPU-resident and is consumed in order on the same command queue.

## CoreAI and ANE suitability

| Implementation | Recommendation | Main reason |
|---|---|---|
| ZipDepth | Best first CoreAI/ANE prototype | Small, static, convolution-heavy, NPU-oriented architecture |
| MediaPipe | Strong candidate per checkpoint | Mobile convolutional models with naturally static inputs |
| FlashDepth | Experimental CoreAI path; retain Metal | Strong custom GPU attention already; Mamba state complicates ANE |
| TAPIR | Possible second-stage experiment | More convolutional than TAPNext++, but carries large explicit state |
| TAPNext++ | GPU-first | 741 MiB FP32 model, attention/recurrent math, full FP16 already has larger error |
| EfficientTAM | GPU-first | Known severe blanket-FP16 degradation and rank-six transformer intermediates |

Important ANE constraints from the new skills are:

- static shapes;
- FP16, int8, or int16 tensors rather than FP32;
- tensor rank no greater than five;
- aligned innermost dimensions;
- minimal casts, reshapes, and transposes; and
- whole-model residency wherever possible.

Moving between ANE, GPU, and CPU can erase the benefit of using ANE. A conversion should not be considered successful based only on numerical correctness: its compiled compute plan and end-to-end residency need to be inspected.

CoreAI also does not expose Fabric's caller-owned `MPSCommandBuffer` scheduling contract in the reviewed API. Any CoreAI backend needs an explicit asynchronous scheduling and resource-interop design. Its latency measurements must include preprocessing, tensor or texture interchange, synchronization, postprocessing, and the effect on the render queue.

## Package-specific opportunities

### MPS-ZipDepth

The largest immediate GPU improvement is offline inference fusion.

The graph currently evaluates each QARep block as:

- a 3x3 convolution plus batch normalization;
- a 1x1 convolution plus batch normalization;
- an optional identity branch;
- additions; and
- ReLU.

For inference, batch normalization can be folded into the convolution weights and biases. The 1x1 and identity branches can then be padded and added into one 3x3 kernel. This is mathematically exact, requires no retraining, substantially reduces graph size, and improves both MPSGraph execution and prospective ANE residency.

Other opportunities:

- Fold remaining convolution-plus-BN sequences into inference weights.
- Consider folding input mean/standard-deviation normalization into preprocessing or the first convolution.
- Have preprocessing produce the model's native layout rather than writing NHWC and immediately transposing to NCHW.
- Start CoreAI experimentation with static 384x384, 672x384, and 384x672 functions rather than arbitrary shapes.
- Use FP16 weights, inputs, and outputs, then verify that the global-context softmax/matmul remains on ANE.
- Explore palettization only after the FP16 model passes quality validation; the model is small enough that compression may help startup and memory more than steady-state compute.

### MPS-MediaPipe

These models are structurally good ANE candidates, but the generic JSON interpreter is better suited to a flexible/reference GPU backend than the final CoreAI representation. A production CoreAI path should export one static `.aimodel` per checkpoint, eliminating runtime JSON interpretation, graph construction, and specialization.

Current GPU opportunities:

- Produce NCHW directly in the crop shader instead of writing NHWC and immediately transposing.
- Consider FP16 preprocessing and public tensors where accuracy permits.
- Use private buffers for GPU-only preprocessing paths where CPU access is unnecessary.
- Separate shared-model inference capacity from per-node preprocessing capacity.
- Give CPU-output nodes real per-flight output/readback rings.
- Re-author depth-to-space with an ANE-compatible high-level operation. The current MPSGraph implementation creates a rank-six intermediate, above ANE's rank-five limit.

The capacity distinction matters: the shared model may need enough inference slots for several nodes across several overlapping frames, but every node creates its own crop preprocessor. Giving each node 16 crop buffers is unnecessary. At 256x256 FP32 RGB, that is approximately 12 MiB of eagerly allocated crop storage per node. Node-local preprocessors normally need only the renderer's actual frames-in-flight count.

### MPS-FlashDepth

The custom GPU work is already thoughtful and consistent with the GPU skill guidance:

- fused QKV;
- online-softmax attention without materializing a full attention-score matrix;
- one compute encoder across all twelve ViT blocks;
- private reusable scratch buffers; and
- direct GPU-resident DPT/Mamba processing.

Remaining opportunities:

- Test FP16 weight and activation storage while retaining FP32 normalization, softmax, Mamba accumulation, and other sensitive reductions.
- Benchmark a `simdgroup_matrix` implementation of the dense projections with half inputs and FP32 accumulation.
- Reduce dispatches and memory traffic by fusing LayerScale/residual work into projection and `fc2` kernels where practical.
- Precompile bundled Metal libraries instead of invoking `makeLibrary(source:)` during model initialization. Runtime compilation currently requires explicit serialization because concurrent compilation produced numerical corruption.
- Profile read-only weights in private storage or heaps versus their current shared storage rather than assuming either is faster on unified memory.
- Continue profiling the correctness-first post-ViT convolutions and the single-threadgroup Mamba SSD step.

An ANE version would be a separate authoring effort rather than a backend toggle. It would require Conv2d projections, per-head attention, BC1S-style layouts, FP16 throughout, rank-safe intermediates, and explicit Mamba state inputs and outputs. Splitting DPT onto ANE while leaving ViT/Mamba on GPU is unlikely to win unless a compute plan proves transfer costs are small.

### MPS-TAPNextPlusPlus and TAPIR

The current mixed-precision design is sensible: large convolution and dense work runs in FP16 while normalization, attention, recurrent state, prediction heads, and public buffers remain FP32. Fused scaled-dot-product attention and the batched RG-LRU matrix multiplication are appropriate for GPU execution.

The biggest opportunity is model size:

- TAPNext++ uses approximately 741 MiB of FP32 weights.
- FP16 storage should roughly halve that footprint.
- Palettization or quantization could reduce it much further if output quality survives.

Additional opportunities:

- Fuse `linear_x` and `linear_y` projections that read the same input where the resulting layout remains efficient.
- Fuse sliced feed-forward projections into one larger matrix multiplication where possible.
- Precompute graph-build-time weight transposes and constant offsets in the exporter.
- Continue using explicit recurrent state buffers. For a CoreAI/ANE experiment, export static functions per point-count/refinement configuration and keep state as explicit inputs and outputs rather than using stateful transforms that reset between calls.

TAPIR is probably the better first CoreAI experiment because it is more convolutional, but its state sizes and placement still need careful profiling.

### MPS-EfficientTAM

EfficientTAM should remain GPU-first. The implementation deliberately preserves FP32 transformer intermediates because indiscriminate FP16 conversion causes severe accuracy degradation. Window partitioning also creates rank-six intermediates, which prevents a direct ANE lowering.

Possible improvements:

- Test selective FP16 only stage by stage, never as a blanket conversion.
- Keep normalization, attention-score, and other sensitive accumulation in FP32.
- Pretranspose linear weights during checkpoint export where graph-time transposes remain.
- Pool the Fabric node's approximately 3 MiB per-frame model input buffer instead of allocating it every frame.
- If multiple tracker nodes are expected, investigate sharing immutable compiled stages and weights while retaining completely independent video state.

The existing full-tensor differential tests are valuable and should remain the acceptance gate for any precision or layout change.

## Cross-cutting Fabric/node opportunities

### Buffer pooling and capacity

- Keep shared compiled models keyed by device and static shape; the current shared caches for MediaPipe, ZipDepth, and TAPIR are directionally correct.
- Do not reuse one CPU-readable output buffer across overlapping submissions.
- Size per-node preprocess/readback pools to actual renderer concurrency, not aggregate shared-model concurrency.
- Pool large transient allocations such as EfficientTAM's model input and readback buffers.

### Model initialization

MPSGraph construction and specialization currently occur synchronously, often with `waitForCompilationCompletion = true`. CoreAI ahead-of-time compilation would reduce cold-load cost on supported systems. For MPS, prewarming outside the first live frame and preserving compiled model caches remain important.

The current shared-model cache intentionally holds its lock while construction occurs. That prevents duplicate compilation but also blocks every lookup in that model family during a long compile. An asynchronous once-per-key construction mechanism could preserve deduplication without tying model enablement to the render path.

### Timing and profiling

The MediaPipe timing logger measures from CPU submission until Fabric's entire shared frame command buffer completes. That includes queueing and unrelated downstream GPU work, so it is end-to-end frame latency, not isolated model latency. It is useful, but its label should not be interpreted as pure inference time.

Optimization decisions should use:

- Metal System Trace for MPS/Metal paths;
- GPU counters or counter sample buffers when stage isolation is needed;
- CoreAI compute-plan/residency inspection;
- cold-load and specialization time;
- peak and steady-state memory;
- energy, especially on iOS and visionOS; and
- end-to-end node latency including format conversion and synchronization.

## Recommended evaluation order

1. Correct MediaPipe and FlashDepth command-buffer ownership.
2. Add per-flight MediaPipe result buffers.
3. Fuse ZipDepth BN and QARep branches and measure the improved MPS baseline.
4. Produce a static FP16 CoreAI ZipDepth export.
5. Inspect actual compute placement; reject versions with significant GPU/CPU partitioning unless they still win end to end.
6. Measure the complete Fabric node cost, not just model execution.
7. Require reference parity of approximately greater than 70 dB PSNR for FP32 and greater than 50 dB for FP16 before performance comparisons.
8. Repeat with one representative MediaPipe model before converting the entire family.
9. Explore TAPNext++/TAPIR compression only after their existing mixed-precision correctness baseline is locked down.
10. Attempt selective FP16 EfficientTAM stages last, because its known accuracy sensitivity makes it the highest-risk precision conversion.

## Relevant CoreAI references

The local `coreai-models` checkout contains useful export patterns, but not drop-in equivalents for these packages:

- `coreai-models/models/depth-anything/export.py` demonstrates a vision/depth export, but is currently Float32-only and is not evidence of ANE residency.
- `coreai-models/models/efficient-sam/export.py` demonstrates the more relevant static-FP16 export pattern, although EfficientSAM is not EfficientTAM.

Apple references:

- [Core AI documentation](https://developer.apple.com/documentation/coreai)
- [Compiling Core AI models ahead of time](https://developer.apple.com/documentation/coreai/compiling-core-ai-models-ahead-of-time)

