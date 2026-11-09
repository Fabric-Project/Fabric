# Fabric MPS Model Optimization Plan

## Purpose

This document is a proposed implementation plan for improving the following Swift packages and their Fabric integrations:

- `MPS-ZipDepth`
- `MPS-MediaPipe`
- `MPS-FlashDepth`
- `MPS-TAPNextPlusPlus`, including TAPIR
- `MPS-EfficientTAM`

The plan has four ordered goals:

1. Make command submission, resource lifetimes, recurrent state, and overlapping frames correct.
2. Preserve model behavior through full-tensor and task-level validation.
3. Reduce end-to-end latency, memory traffic, initialization cost, and energy use.
4. Make suitable MPSGraph regions eligible for automatic placement on the Apple Neural Engine without compromising the caller-owned Metal command-buffer architecture.

This is a plan, not an instruction to implement every possible optimization. Every change must earn its place through correctness and performance evidence.

## Architectural position

MPSGraph remains the primary model runtime. Custom Metal remains appropriate where it demonstrably performs better or implements operations that MPSGraph cannot express efficiently.

MPSGraph can execute work across the GPU, CPU, and Apple Neural Engine. With optimization level 1, its compiler placement pass may dispatch compatible regions to different hardware blocks. ANE support therefore does not require replacing MPSGraph with Core ML or CoreAI.

There is no supported public switch that guarantees an entire MPSGraph executable will run on ANE. ANE placement is a compiler decision. A graph is not considered “ANE optimized” merely because it uses optimization level 1 or FP16. Actual hardware activity, transfers, latency, and energy must be measured.

All reviewed packages already request optimization level 1. They may already receive partial ANE placement. The first ANE task is to measure the current placement, not to assume none exists.

The macOS 26 `allowFP16Intermediates` reduced-precision fast-math option is also not the ANE enablement switch. It is a curated GPU/intermediate precision optimization. Explicit FP16 inputs, weights, tensors, casts, and mixed-precision graph authoring are available on Fabric’s current deployment targets and should be evaluated independently.

Relevant Apple material:

- [Metal Performance Shaders Graph](https://developer.apple.com/documentation/metalperformanceshadersgraph)
- [MPSGraph optimization options](https://developer.apple.com/documentation/metalperformanceshadersgraph/mpsgraphoptimization)
- [WWDC23: Optimize machine learning for Metal apps](https://developer.apple.com/videos/play/wwdc2023/10050/)

## Non-negotiable guardrails

### Correctness before performance

- Do not combine a behavior-preserving rewrite with a precision change in the same validation step.
- Establish a frozen reference fixture before modifying each graph region.
- Compare complete tensors, not selected elements, averages, screenshots, or only final argmax values.
- Validate recurrent models over sequences, including state reset, dropped-frame, interrupted-frame, and recovery behavior.
- Retain a known-correct FP32 path until the replacement has passed numerical, integration, and performance gates.
- Never accept visual plausibility as a depth, segmentation, detection, or tracking correctness test.

### Honest accelerator claims

- Do not label a path “ANE” unless profiling demonstrates Neural Engine execution for the tested model, shape, precision, OS, and hardware.
- Do not equate FP16 with ANE placement.
- Do not optimize for ANE utilization percentage. Optimize for end-to-end latency, energy, and predictable scheduling.
- Reject placement that introduces transfers or synchronization expensive enough to erase the compute benefit.
- Prefer a large compiler-visible graph over manually fragmented micrographs unless traces prove fragmentation wins.

### Command-buffer ownership

- Fabric owns the frame command buffer and its commit lifecycle.
- Package `encode` APIs must consume the exact supplied `MPSCommandBuffer` and must not wrap, commit, wait, or create a parallel queue.
- Package `submit` APIs must attach completion to the command buffer that contains the final encoded work.
- Package synchronous `run` APIs may create, commit, and wait on a dedicated MPS command buffer.
- Completion handlers, slot release, CPU readback, and recurrent state publication must observe the live MPS wrapper after encoding, including any `commitAndContinue` segmentation.
- No optimization may reintroduce a hidden synchronization point into normal Fabric rendering.

### Resource safety

- Every overlapping inference owns a distinct writable input, output, readback, scratch, and state slot unless ordering proves that reuse is safe.
- Shared immutable weights and compiled executables are encouraged; mutable recurrent state is never shared between node instances.
- Dropped or failed submissions must release capacity without publishing incomplete output or advancing model state.
- Pool sizes must reflect the concurrency domain: shared-model capacity and per-node renderer frames-in-flight are different quantities.
- Avoid per-frame heap allocation after warm-up.

### Evidence-driven performance work

- Profile before and after every material optimization on representative Apple silicon.
- Measure the complete node pipeline: preprocessing, graph/custom kernels, accelerator transitions, postprocessing, output conversion, queueing, and readback.
- Preserve cold-start, steady-state, peak-memory, and energy measurements separately.
- Do not retain an optimization that merely moves time between stages without improving an agreed product metric.
- Do not assume fewer dispatches, lower precision, a larger fused kernel, private storage, zero-copy, or quantization is faster. Measure each candidate.

### Scope discipline

- No third-party runtime should be introduced.
- Core ML or CoreAI may be used later as comparison backends, but they are not prerequisites for MPSGraph ANE placement and are outside the first implementation pass.
- Precision, model shape, and backend-affecting choices belong in node settings, not dynamic graph ports.
- Package APIs should converge on consistent `run`, `submit`, and `encode` semantics.

## Acceptance framework

Before implementation, create an agreed benchmark manifest for every package. It should identify exact checkpoints, input fixtures, image sizes, frame sequences, devices, OS versions, thermal state, and build configuration.

### Correctness gates

- FP32 algebraic re-authoring versus the existing FP32 implementation: target greater than 70 dB PSNR for complete floating-point outputs, plus model-specific metrics.
- Compiled mixed/FP16 implementation versus the frozen FP32 reference: establish a model-specific threshold before performance evaluation; 40 dB is a useful minimum compilation check, not a universal product-quality guarantee.
- Verify maximum absolute error, mean absolute error, relative error, NaN/Inf counts, output range, and shape in addition to PSNR.
- Use task metrics where appropriate: depth ordering and edge behavior, mask IoU, detection boxes/scores/classes, landmark distances, and tracking error/occlusion confidence.
- For stateful models, test long sequences and compare accumulated drift, not just the first frame.

### Systems-correctness gates

- Run with several in-flight frames and multiple nodes sharing one compiled model.
- Verify execution when MPSGraph segments a command buffer.
- Verify that subsequent Metal encoders consume completed inference output correctly.
- Exercise capacity exhaustion, cancellation, graph teardown, node deletion, device errors, and model initialization failure.
- Use Metal validation and concurrency diagnostics where applicable.

### Performance gates

- CPU encode/submission duration.
- End-to-end node latency at p50 and p95.
- GPU duration and observed Neural Engine activity.
- Accelerator transition and idle gaps.
- Sustained throughput under normal Fabric frame overlap.
- Cold graph construction/specialization and first-inference latency.
- Peak and steady-state memory.
- Energy on relevant mobile and spatial hardware.

Performance thresholds should be agreed before implementation. A change should normally be rejected if it regresses end-to-end latency, energy, or memory materially without providing an explicitly chosen benefit.

## Phase 0: Baseline and instrumentation

No graph transformation should begin until this phase is complete.

1. Freeze reference weights, inputs, outputs, and representative frame sequences for every supported checkpoint.
2. Record current output tensors from the existing FP32/reference paths.
3. Add stage-level signposts around preprocessing, MPSGraph execution, custom Metal execution, postprocessing, texture conversion, readback, and state publication.
4. Profile current optimization-level-1 executables with Metal System Trace and Neural Engine instrumentation.
5. Record current accelerator placement by model, shape, precision, device, and OS.
6. Separate isolated model time from shared Fabric frame-command-buffer completion time.
7. Record allocation counts and peak resident memory during model load, first inference, and steady-state operation.

Deliverable: a baseline report and machine-readable benchmark manifest. This baseline becomes the acceptance reference for every later phase.

## Phase 1: Repair command and lifetime correctness

This phase is required before precision, fusion, compression, or ANE-specific graph work.

### MPS-MediaPipe

- Replace APIs that accept a raw `MTLCommandBuffer` and create an internal MPS wrapper with APIs that accept and reuse the caller’s `MPSCommandBuffer`.
- Remove package-level `commit` choices from non-synchronous paths.
- Attach slot-release and result-completion behavior to the final live command buffer after graph encoding.
- Give detection and landmark execution per-flight GPU output and CPU readback slots.
- Ensure a later frame cannot overwrite buffers while an earlier completion handler is reading them.
- Separate shared model inference capacity from node-local crop-preprocessor capacity.

### MPS-FlashDepth

- Remove nested MPS command-buffer wrapping in the pipeline encoding path.
- Make continuation and completion logic follow the live MPS wrapper rather than the original raw Metal command buffer.
- Verify that temporal state changes become visible only after successful completion.

### MPS-EfficientTAM and MPS-TAPNextPlusPlus

- Preserve their correct wrapper-reuse behavior.
- Audit `submit` convenience APIs so their ownership rules match the common package contract.
- Confirm that model state, tracker state, and readback pools are isolated by node instance and inference flight.

### Fabric nodes

- Cast or pass the renderer-owned MPS command buffer explicitly.
- Use package synchronous APIs only outside the shared frame-render path.
- Pool EfficientTAM’s model input buffer rather than allocating it each frame.
- Ensure teardown does not release resources still referenced by in-flight command buffers.

Deliverable: one documented command-buffer contract and stress tests covering every package API shape.

## Phase 2: Exact inference simplification

Only algebraically exact or equivalence-proven transformations belong in this phase. All work remains FP32 during initial verification.

### ZipDepth

- Fold batch-normalization parameters into their preceding inference convolutions.
- Reparameterize each QARep block into one 3×3 convolution by combining the folded 3×3 branch, padded 1×1 branch, and identity kernel where present.
- Remove runtime branch additions made redundant by that reparameterization.
- Generate and retain a conversion-time verification artifact proving fused versus unfused tensor parity at each converted block.
- Evaluate folding input normalization into preprocessing first. Fold it into the first convolution only if padding and boundary behavior are proven identical.
- Benchmark, but do not assume, replacement of the parallel depthwise dilation paths with a single larger kernel.

### TAPNext++ and TAPIR

- Concatenate `linear_x` and `linear_y` weights and biases into one projection followed by a split where exact.
- Convert sliced feed-forward up-projections into one projection followed by a split where exact.
- Precompute immutable weight transposes, offsets, and constant scale adjustments in checkpoint conversion rather than at graph construction or execution time.

### All packages

- Make preprocessing emit the model’s actual entry layout directly when that removes a full-frame transpose.
- Preserve a layout variant if profiling shows the MPSGraph compiler prefers a different physical layout for ANE placement.
- Remove constant casts, reshapes, and transposes from runtime graphs when they can be expressed once in exported weights.
- Prefer standard high-level graph operators so compiler fusion and placement opportunities remain visible.
- Investigate `.mpsgraphpackage` serialization for stable fixed-shape executables to reduce graph construction and cold specialization time.
- Precompile custom Metal sources into metallibs rather than compiling source at runtime, once numerical parity is established.

Deliverable: smaller FP32 graphs with unchanged public behavior and an updated performance baseline.

## Phase 3: Explicit precision policies

Precision changes must be introduced region by region against the simplified FP32 graph. Do not rely on `allowFP16Intermediates` availability.

Each package should expose internal build configurations equivalent to:

- Reference FP32.
- Balanced mixed precision.
- Energy-efficient FP16 candidate.

These are package/compiler configurations, not promises that a particular accelerator will be selected.

### ZipDepth

- Evaluate FP16 inputs, weights, convolutions, and feature tensors first.
- Keep softmax, normalization, global-context reductions, and public output FP32 during the first mixed-precision pass.
- Expand FP16 coverage only after complete-tensor depth validation.

### MediaPipe

- Build a precision policy per checkpoint rather than assuming every generated graph has the same tolerance.
- Evaluate FP16 preprocessing and model tensors while retaining FP32 CPU-facing outputs when required by the public API.
- Re-author depth-to-space without a rank-six intermediate if exact parity is possible.

### TAPNext++ and TAPIR

- Preserve the existing mixed-precision intent: large convolution/projection work may use FP16 while normalization, attention reductions, recurrent state, prediction heads, and public results remain FP32 initially.
- Evaluate additional FP16 storage separately from additional FP16 arithmetic.
- Test temporal drift and occlusion transitions across long sequences.

### FlashDepth

- Begin with FP16 weight and activation storage in large projections.
- Retain FP32 normalization, softmax, recurrent/Mamba accumulation, and sensitive reductions until isolated tests justify otherwise.
- Test both single-frame depth quality and temporal behavior.

### EfficientTAM

- Keep the FP32 implementation as the default reference.
- Test selective FP16 one stage at a time because blanket FP16 has already shown severe degradation.
- Preserve FP32 attention scores, normalization, and other sensitive accumulation unless full-tensor tests prove safety.

Deliverable: validated precision maps identifying the dtype of every graph boundary, sensitive reduction, state tensor, and public output.

## Phase 4: Improve automatic ANE placement

This phase starts with observation of the simplified mixed-precision graphs. Do not create an alternate architecture until current placement is known.

For candidate graph regions:

- Keep shapes fully static for a compiled executable.
- Prefer FP16-compatible operations and constants.
- Keep tensor rank at five or below where possible.
- Align important feature dimensions where padding cost is acceptable and reversible.
- Remove avoidable casts, transposes, reshapes, and host-visible boundaries.
- Prefer compiler-recognizable convolution, matrix multiplication, normalization, activation, pooling, and resize operations.
- Keep related operations within one compiler-visible graph so placement can occur at coarse boundaries.
- Inspect whether unsupported operations create small alternating ANE/GPU islands.

### Priority order

1. ZipDepth: first full-model ANE-placement candidate because it is static, compact, and convolution-heavy after QARep fusion.
2. MediaPipe: evaluate checkpoint by checkpoint; many mobile convolutional models should provide large eligible regions.
3. TAPIR: experimental mixed placement after state and rank behavior are understood.
4. TAPNext++: retain GPU-first execution unless a large contiguous region moves profitably.
5. EfficientTAM: evaluate compatible convolutional regions, but avoid transitions around rank-six window/attention processing unless traces show a net win.
6. FlashDepth: keep the existing custom GPU implementation as the baseline. Greater ANE use requires an alternate MPSGraph expression of major custom Metal stages, not a flag change.

For every candidate, compare:

- Existing GPU-oriented graph.
- ANE-eligible mixed-precision graph under automatic placement.
- Any hybrid graph only if it has coarse, low-transfer boundaries.

Accept the ANE-friendly version only when profiling proves Neural Engine execution and a net latency or energy improvement without quality regression.

Deliverable: a placement matrix identifying which operations execute on which hardware for every retained model variant.

## Phase 5: GPU and memory-bandwidth optimization

GPU-specific work follows correctness, exact fusion, and precision mapping so it is not spent optimizing operations that later disappear.

### FlashDepth

- Use Metal System Trace and counter data to identify the dominant projection, attention, DPT, and Mamba kernels.
- Prototype `simdgroup_matrix` only for confirmed matrix-heavy bottlenecks and supported device families.
- Evaluate FP16 inputs/weights with FP32 accumulation.
- Fuse LayerScale, residual, bias, and activation work into adjacent kernels when it reduces memory traffic without increasing harmful register pressure.
- Preserve the current online-softmax strategy unless another implementation wins complete attention benchmarks.
- Benchmark shared, private, and heap-backed immutable weights on unified memory instead of assuming one storage mode is universally superior.

### TAPNext++ and TAPIR

- Measure whether exact projection fusion reduces bandwidth and dispatch overhead.
- Keep fused GPU scaled-dot-product attention when it outperforms compiler-partitioned alternatives.
- Reduce weight storage bandwidth before attempting complicated kernel rewrites.

### ZipDepth

- Compare the fused QARep graph across GPU and automatic placement.
- Investigate texture-backed output using supported tensor/image APIs, padded row bytes, or compatible `MPSImageBatch` storage.
- Keep the explicit output copy when zero-copy would impose alignment restrictions, additional padding, or fragile aliasing.

### MediaPipe

- Prioritize removal of allocations, redundant preprocessing, and excess buffer capacity.
- Optimize already-fast checkpoints for energy and sustained multi-node throughput rather than isolated latency alone.

### EfficientTAM

- Focus on input pooling, immutable executable/weight sharing, transpose elimination, and measured selective precision.
- Avoid speculative attention rewrites without a trace-proven bottleneck.

Deliverable: retained optimizations with before/after traces and rejected experiments recorded to prevent repetition.

## Phase 6: Weight loading and compression

First measure the current peak lifetime of mapped checkpoint data, decoded arrays, repacked `Data`, graph constants, and executable-owned weights. Then reduce duplication without obscuring ownership.

Compression order:

1. FP16 weight storage with model-specific precision validation.
2. Int8 weight representation where MPSGraph can fuse dequantization into the consuming operation efficiently.
3. LUT/palettized weights only after runtime support, placement, memory, latency, and quality are verified.

Initial exclusions:

- First and last layers.
- Normalization parameters.
- Bias where savings are negligible.
- Recurrent state.
- Sensitive attention and prediction projections.

Compression is accepted only if the compiled runtime representation is smaller and the full node is faster or materially more memory-efficient. File-size reduction alone is insufficient. Avoid describing sub-byte weights as native sub-byte compute unless traces and APIs prove that behavior.

TAPNext++ should be the highest-priority compression experiment because its FP32 checkpoint is approximately 741 MiB. ZipDepth may gain more from fusion and placement than from aggressive compression because the model is comparatively small.

Deliverable: an accuracy-versus-size-versus-latency table for each explored compression configuration.

## Phase 7: Fabric API and node integration

After package-level behavior is settled:

- Make `run`, `submit`, and `encode` naming and ownership consistent across packages.
- Cache compiled models by device, checkpoint, static shape, precision policy, and graph/export revision.
- Ensure cache creation deduplicates expensive compilation without holding a global lock across unrelated keys.
- Prewarm outside the first live frame where Fabric lifecycle rules permit it.
- Keep normal node execution asynchronous and GPU/accelerator resident.
- Publish CPU results only where the node contract requires them.
- Avoid per-frame allocation after warm-up.
- Keep recurrent state and readback resources node-local even when immutable executables and weights are shared.

If Fabric exposes user-selectable model modes, use honest capability names such as:

- Reference FP32
- Balanced
- Energy Efficient

Do not expose an “ANE” switch when MPSGraph controls placement automatically. Settings that alter graph precision, static shape, or compiled executable identity must be node settings with stable initialization and serialization, not runtime ports.

Iterator batching is a later, independent experiment. It may be considered only after single-inference correctness and scheduling are stable, and only with explicit analysis of iterator semantics, static batch sizes, model-cache cardinality, memory, and latency.

## Package execution order

### Workstream A: Cross-cutting correctness

1. Freeze test fixtures and benchmark manifests.
2. Repair MediaPipe command-buffer handling.
3. Add MediaPipe per-flight output/readback storage.
4. Repair FlashDepth command-buffer handling.
5. Audit remaining package convenience APIs and Fabric node lifetimes.

### Workstream B: ZipDepth pilot

1. Fuse QARep and batch normalization in FP32.
2. Remove avoidable entry-layout work.
3. Establish explicit mixed-precision variants.
4. Trace automatic ANE placement.
5. Tune graph shape/layout only where placement or performance evidence justifies it.
6. Use ZipDepth as the reference implementation for the final package API and validation workflow.

### Workstream C: MediaPipe family

1. Apply the corrected scheduling and resource model.
2. Classify checkpoints by architecture and numerical tolerance.
3. Remove rank-six depth-to-space intermediates where possible.
4. Evaluate FP16 and ANE placement per checkpoint.
5. Roll improvements across the family only when equivalent checkpoint classes share evidence.

### Workstream D: Large and stateful models

1. Consolidate TAP projection and checkpoint transformations.
2. Measure TAPNext++ FP16 storage and compression.
3. Validate TAPIR/TAPNext++ temporal behavior.
4. Profile FlashDepth and implement only trace-supported GPU experiments.
5. Test selective EfficientTAM precision last, retaining its high-quality FP32 baseline.

## Review checkpoints

Stop for review after each of these milestones:

1. Baseline fixtures, metrics, and hardware placement are agreed.
2. Command-buffer and overlapping-frame tests pass.
3. Exact FP32 graph simplifications pass full-tensor validation.
4. Precision policies and quality thresholds are approved.
5. ANE placement evidence and transfer costs are reviewed.
6. GPU optimization traces demonstrate real bottlenecks.
7. Compression results show acceptable quality and runtime value.
8. Fabric settings, caching, and rollout behavior are approved.

No later milestone should be used to excuse a failure in an earlier one.

## Definition of done

The effort is complete when:

- Every package follows the same caller-owned command-buffer contract.
- Overlapping frames cannot race writable model resources or publish incomplete state.
- Every retained rewrite has full-tensor and model-specific quality evidence.
- Every retained optimization has end-to-end performance or energy evidence.
- ANE claims are backed by observed hardware activity and a net product benefit.
- FP32 reference paths remain available where reduced precision is not safe.
- Nodes allocate no large transient resources during steady-state execution.
- Static model variants are cached deterministically and do not stall unrelated model initialization.
- The implementation remains compatible with Fabric’s macOS 15, iOS 18, and visionOS 2 deployment targets.

## Explicitly deferred work

- A wholesale migration to Core ML or CoreAI.
- Dynamic-shape ANE promises.
- A user-facing force-ANE control.
- Iterator-wide batching before scheduling correctness is complete.
- Aggressive 4-bit or 2-bit compression before FP16 and int8 results are established.
- Replacing correct GPU custom kernels solely to increase ANE utilization.
- Zero-copy output paths that weaken format, alignment, or lifetime guarantees.

