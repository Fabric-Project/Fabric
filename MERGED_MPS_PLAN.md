# Merged MPS Package Plan

## Objective

Improve the following Swift packages in controlled, recoverable phases. Active scope is limited to the SPMs Fabric currently depends on (`Package.swift`):

- `MPS-ZipDepth`
- `MPS-MediaPipe`
- `MPS-TAPNextPlusPlus`, including TAPIR
- `MPS-EfficientTAM`

`MPS-FlashDepth` is **back pocket**: no Fabric node or dependency exists yet. Its items stay tracked in this document but are out of active scope. Revisit once performance is up, then decide whether to wire it into Fabric and test it.

The order is mandatory:

1. Preserve the current working state.
2. Fix package correctness and weight loading.
3. Standardize package command-buffer and output APIs.
4. Optimize graphs, kernels, weights, precision, and compression.
5. Investigate and improve MPSGraph placement on the Apple Neural Engine.

This document is a plan only. It authorizes no implementation, build, test, branch, commit, reset, deletion, or dependency update by itself.

## Global execution guardrails

### One phase at a time

- A phase starts only after explicit user approval.
- Work from a later phase must not be pulled into an earlier phase for convenience.
- Each package receives its own commits; do not combine unrelated repositories into one conceptual change.
- At the end of every phase, stop and present the commits, changed files, validation evidence, open risks, and rejected experiments.
- Do not begin the next phase until the user explicitly approves it.

### Fabric is frozen after Phase 0

- Phase 0 may commit and clean the existing Fabric MPS branch so its current state is recoverable.
- Phases 1 through 4 modify MPS Swift packages only.
- Do not change Fabric nodes, `GraphRenderer`, node settings, node serialization, the Fabric project, or Fabric’s package revisions during Phases 1 through 4.
- Package API changes may therefore exist on package branches before Fabric adopts them.
- Fabric integration and node migration require a separate future phase and explicit approval.

### Builds and tests

- Codex does not run builds or tests unless the user explicitly authorizes them for that phase.
- Each implementation phase must prepare an exact validation checklist for the user to run.
- A phase cannot be declared validated until the requested build/test results are supplied or the user explicitly accepts the missing validation.
- Static inspection is not a substitute for runtime validation.

### Correctness

- Freeze reference inputs, weights, outputs, and temporal sequences before changing behavior.
- Compare complete tensors, not screenshots, selected values, means, or only final classifications.
- Keep algebraic graph rewrites separate from precision and compression changes.
- Validate stateful models across sequences, resets, dropped submissions, capacity exhaustion, and recovery.
- Retain the known-correct FP32 form until a replacement passes its numerical and task-level gates.
- Never accept visually plausible depth, masks, detections, landmarks, or tracks as sufficient evidence.

### Performance and accelerator claims

- Measure before and after each optimization.
- Measure the complete package path: weight load, specialization, preprocessing, graph/custom kernels, resource transitions, postprocessing, and readback.
- Do not assume that fewer operations, lower precision, fusion, quantization, zero-copy, private storage, or ANE activity is faster.
- MPSGraph optimization level 1 may place compatible regions on GPU, CPU, and ANE. There is no public supported force-ANE selector.
- Do not call a configuration “ANE optimized” without observed Neural Engine execution and a net latency or energy benefit on the tested hardware and OS.
- Core ML and CoreAI are not required for MPSGraph ANE placement and are outside this plan unless separately approved.

### Source control and recovery

- Never use destructive cleanup commands to obtain a clean tree.
- Do not discard, reset, overwrite, or silently exclude existing work.
- Every pre-existing change must be classified as intended source, intended asset, generated artifact, local-only data, or unknown.
- Unknown files remain untouched until the user decides their disposition.
- Do not rewrite or squash the Phase 0 recovery history during later phases.

## Shared validation model

Each package needs a small checked-in or reproducibly generated validation corpus appropriate to its license and repository policy.

Record at least:

- Exact checkpoint identity and checksum.
- Input fixture identity and preprocessing parameters.
- Static input and output shapes.
- Tensor dtype and layout.
- Reference tensor checksum and generation method.
- Maximum absolute error, mean absolute error, relative error, PSNR or SNR, NaN/Inf counts, and output range.
- Model-specific quality metrics.
- For temporal models, sequence length, reset points, state checksums, and accumulated drift.

Suggested starting gates, subject to package-specific tightening before implementation:

- Exact FP32 rewrite versus the frozen FP32 package: greater than 70 dB PSNR plus unchanged task metrics.
- FP16 or mixed precision versus the frozen FP32 package: investigate below 40 dB; the final acceptance threshold must be chosen per model and output.
- Compression: report the accuracy-size-latency frontier rather than accepting a universal bit-width or PSNR rule.
- Any NaN, Inf, shape change, incorrect state transition, or nondeterministic output is a failure unless explicitly expected and documented.

## Phase 0 — Recovery baseline and clean repositories

### Goal

Create a trustworthy recovery point for all existing MPS SPM work and the current Fabric MPS branch before making any new change.

### Scope

- Fabric’s current MPS branch.
- `MPS-ZipDepth`.
- `MPS-MediaPipe`.
- `MPS-FlashDepth`.
- `MPS-TAPNextPlusPlus`.
- `MPS-EfficientTAM`.

### Procedure

1. Inventory every repository:
   - Repository root.
   - Current branch and upstream.
   - Current `HEAD`.
   - Staged, unstaged, untracked, ignored, and submodule state.
   - Relevant dependency revisions and package pins.
2. Produce a pre-cleanup manifest containing the above information and a concise classification of every existing change.
3. Review untracked and ignored content without deleting it.
4. Commit all intended existing source, tests, package metadata, conversion tools, manifests, and documentation in the repository where they belong.
5. Keep checkpoints, build products, DerivedData, traces, local caches, and other large/generated files out of Git unless they are already intentional versioned assets.
6. If ignore rules are incomplete, change them only after verifying that no intended asset would become hidden.
7. Resolve obvious accidental duplicate or misplaced files only through recoverable moves and only after their intended destination is established.
8. Make repository-specific baseline commits without squashing previous work.
9. Record the final branch name, commit hash, clean status, dependency revision, and any deliberately retained local-only files for every repository.
10. Optionally create recovery tags only if the user approves the exact tag names.

### Phase 0 restrictions

- No model behavior changes.
- No API redesign.
- No weight conversion.
- No formatting sweep or unrelated cleanup.
- No build or test unless separately authorized.
- No deletion of unknown files.

### Phase 0 exit gate

- Every repository has a recorded recovery commit.
- Every repository is clean, or each remaining local-only file is explicitly documented and accepted.
- Fabric’s dependency revisions and current node source are recoverable exactly.
- The user receives all hashes and approves the baseline before Phase 1 begins.

## Phase 1 — MPS SPM correctness and weight loading

### Goal

Fix correctness defects entirely within the Swift packages, including weight-file parsing, validation, lifetime, and deterministic model construction. Do not redesign the public command-buffer API yet.

### Absolute boundary

- MPS package source, package tests, package fixtures, exporters/converters, manifests, and package documentation only.
- No Fabric files or nodes.
- No package API redesign reserved for Phase 2.
- No quantization, palettization, broad FP16 conversion, graph fusion, ANE-specific rewrite, or speculative performance kernel.

### 1.1 Freeze package references

For every supported checkpoint:

- Record the source repository and checkpoint identity.
- Record the expected parameter names, shapes, dtypes, byte counts, and layout.
- Preserve representative real inputs and trusted source-framework outputs.
- Add multi-frame references for FlashDepth, TAPNext++, TAPIR, and EfficientTAM.
- Verify reset behavior and the initial state separately from steady-state behavior.

Random tensors may exercise shape and memory safety, but they do not replace real fixtures for quality validation.

### 1.2 Make weight loading strict

Every loader should fail early and descriptively when a checkpoint is wrong.

- Validate magic/version information when the format has it.
- Validate manifest schema and package/model version compatibility.
- Validate complete expected tensor coverage.
- Reject missing, duplicate, unknown, truncated, and trailing tensor data unless the format explicitly permits it.
- Validate tensor shape, element count, dtype, byte length, storage order, alignment assumptions, and endianness.
- Use overflow-safe byte-offset and element-count calculations.
- Validate all view/slice bounds before constructing graph constants or Metal resources.
- Preserve the mapped backing storage for as long as any zero-copy view requires it.
- Avoid force unwraps and unchecked rebinding in recoverable parsing paths.
- Include tensor names and expected/actual metadata in errors without logging raw model contents.
- Verify that weight transforms reproduce the source tensors exactly before graph construction.

Copy reduction is allowed in this phase only when it is byte-for-byte equivalent, improves lifetime clarity, and is covered by loader tests. Re-encoding weights into a lower precision or compressed representation belongs to Phase 3.

### 1.3 Package-internal correctness audit

- Confirm input/output shape and dtype validation at every public boundary.
- Confirm preprocessing constants, channel order, normalization, resize/crop semantics, padding, coordinate conventions, and output scaling against the official model.
- Confirm activation variants exactly; GELU variants, SiLU, QuickGELU, and other activations are not interchangeable.
- Confirm softmax axes, transpose order, convolution grouping, dilation, padding, pixel shuffle/depth-to-space ordering, interpolation mode, and align-corners behavior.
- Confirm state buffers are initialized, updated, swapped, and reset in the correct order.
- Confirm failed or dropped executions do not publish partial output or advance recurrent state.
- Confirm all package-owned writable resources are safe for the package’s advertised number of in-flight submissions.
- Confirm custom Metal kernels initialize every output and scratch region they read.

### 1.4 Known package investigations

#### MPS-ZipDepth

- Verify every converted tensor and layer against the official implementation.
- Lock depth normalization, resize, aspect handling, and output convention.
- Verify all supported static image sizes independently.
- Treat QARep/BN fusion as Phase 3; Phase 1 validates the current unfused reference.

#### MPS-MediaPipe

- Validate generic JSON/interpreter semantics checkpoint by checkpoint.
- Verify depth-to-space ordering and rank-changing reshapes.
- Verify package-owned inference-slot and writable-buffer lifetimes.
- Node-owned CPU output rings are not changed in this plan.

#### MPS-FlashDepth

- Investigate the reported concurrent shader-compilation numerical divergence as a correctness defect.
- Use validation evidence to distinguish compiler serialization from an uninitialized-memory, bounds, scratch-aliasing, or timing race.
- Precompiled metallibs are a Phase 3 optimization and must not be described as fixing an unproven race.
- Verify temporal state and failed-frame behavior.

#### MPS-TAPNextPlusPlus and TAPIR

- Validate every checkpoint tensor, current mixed-precision boundary, point-count specialization, refinement configuration, and recurrent-state transition.
- Verify long-sequence drift and occlusion transitions.

#### MPS-EfficientTAM

- Preserve its FP32 reference behavior.
- Validate image encoder, memory encoder, prompt path, mask decoder, and video state independently before end-to-end comparison.
- Preserve existing full-tensor differential tests as mandatory gates.

### Phase 1 deliverables

- Strict loader/manifest behavior for every package.
- A documented reference corpus and model-specific metric table.
- Package tests for malformed weights, tensor metadata, preprocessing, full outputs, and temporal state.
- A list of confirmed defects and fixes, separated from suspected issues that remain unproven.
- One or more focused commits per package.

### Phase 1 exit gate

- No Fabric files changed.
- User-run package builds/tests pass on the approved targets, or missing validation is explicitly accepted.
- Frozen reference outputs are reproducible.
- All confirmed correctness changes are committed and repository hashes recorded.
- The user approves Phase 1 before any API work begins.

## Phase 2 — MPS SPM API correctness

### Goal

Give all MPS packages the same command-buffer ownership model while preserving the mandatory distinction between GPU-resident image output and CPU-readable numerical output.

### Absolute boundary

- Package APIs, package internals, package tests, samples, and package documentation only.
- No Fabric node or renderer edits.
- No quantization, layer optimization, FP16 expansion, or ANE work.

### 2.1 Mandatory command-buffer contract

All production encoding APIs must:

- Accept the caller’s existing `MPSCommandBuffer`.
- Encode into that exact wrapper.
- Never construct a second MPS wrapper around its underlying `MTLCommandBuffer`.
- Never explicitly commit the caller’s command buffer.
- Never wait for completion inside the encoding path.
- Never create a private command queue to bypass caller ownership.
- Attach any package completion, slot release, state publication, or readback handling to the live MPS command-buffer state after graph encoding.
- Remain correct if MPSGraph internally segments work or uses `commitAndContinue`.

MPSGraph’s internal scheduling is not considered a package-owned explicit commit. The package must nevertheless follow the live `MPSCommandBuffer` rather than assuming the original raw Metal command buffer remains the final segment.

### 2.2 Shared API shape

The exact Swift names should be finalized after inventorying the packages, but the semantics are mandatory:

- A common encode operation accepts prepared inputs, caller-provided output resources where appropriate, and an `MPSCommandBuffer`.
- Encoding returns a lightweight submission/result description, not a committed future.
- Resource-capacity acquisition happens before encoding.
- Capacity is released only when the final encoded work has completed or encoding fails before submission.
- Package state is published only after successful completion.
- Synchronous test helpers, if retained, must live outside the production caller-owned encode path and must not be used by Fabric rendering.

Compatibility overloads may exist temporarily only if they forward into the new implementation without wrapping or committing. A deprecated overload that still owns submission violates this phase and must not be used to claim API convergence.

### 2.3 Image-only output contract

For packages or entry points whose public output is only a GPU image:

- Keep input, inference, postprocessing, and output on the GPU/accelerator path.
- Return or populate a GPU resource suitable for later encoders on the same command-buffer dependency chain.
- Do not install CPU readback solely to signal completion.
- Do not wait, block, or synchronize with the CPU.
- Do not copy to shared CPU memory unless required by an independently approved public contract.
- Avoid completion callbacks when output lifetime can be expressed safely through caller-owned resources and command ordering.

This applies to image-output paths such as depth or segmentation textures when no numerical metadata is part of the public result.

### 2.4 Numerical-output contract and compile flag

For packages or entry points whose results must become CPU-readable numerical data:

- Preserve the existing compile-time selection between synchronous and asynchronous result handling. This is mandatory for now.
- The compile flag controls readback/result-delivery behavior; it does not transfer command-buffer ownership to the package.
- In asynchronous mode, the package encodes into the supplied MPS command buffer and arranges result delivery after the final encoded work completes. The caller remains responsible for committing.
- In synchronous mode, the package encodes into the supplied MPS command buffer and exposes the readback state needed after the caller commits and waits. The package’s production encode path still does not commit or wait.
- Keep synchronous and asynchronous numerical results byte-for-byte and semantically identical.
- Keep readback buffers distinct for overlapping submissions.
- Document which thread or executor invokes asynchronous completion and what resource lifetime the caller must maintain.
- Do not use the numerical-output compile flag for image-only paths.

If an existing compile flag currently causes the SPM itself to commit or wait, preserve the configuration choice but redefine ownership so the caller performs that operation. Fabric adoption of that changed contract is deferred to the future integration phase.

### 2.5 Package migration checklist

#### MPS-MediaPipe

- Remove nested MPS wrapper creation from the common encode path.
- Move completion and slot release to the final live command-buffer lifecycle.
- Preserve compile-time sync/async numerical output behavior for detection and landmarks.
- Keep segmentation image output GPU-resident and synchronization-free.

#### MPS-FlashDepth

- Remove temporary wrapper creation inside pipeline encoding.
- Make continuation, state publication, and resource release follow the supplied MPS wrapper.
- Treat image depth output as GPU-resident when no CPU numerical result is requested.

#### MPS-ZipDepth

- Preserve its existing correct wrapper reuse.
- Remove or isolate any production `commit:` behavior so caller ownership is unambiguous.
- Keep image output GPU-resident and synchronization-free.

#### MPS-TAPNextPlusPlus and TAPIR

- Standardize wrapper reuse and completion semantics.
- Preserve the mandatory numerical sync/async compile-time selection.
- Verify per-flight readback and state lifetimes under both configurations.

#### MPS-EfficientTAM

- Standardize command ownership across image-embedding, prompt, mask, and tracking entry points.
- Apply image-only versus numerical-output behavior per entry point rather than per package name.
- Preserve state isolation and readback semantics.

### 2.6 API conformance tests

- A package cannot explicitly commit or wait during production encoding.
- A package cannot wrap the underlying Metal command buffer a second time.
- An image-only encode can be followed by another Metal encoder consuming the output without CPU synchronization.
- Numerical asynchronous completion fires only after final output is valid.
- Numerical synchronous readback matches asynchronous readback after caller-owned commit/wait.
- Capacity cannot be released while continuation work remains in flight.
- Failed encoding releases capacity exactly once and publishes neither output nor state.

### Phase 2 deliverables

- One shared API contract document used by every package.
- Conforming package APIs and package-level contract tests.
- A migration note describing future Fabric node changes without modifying Fabric.
- Per-package commits and recorded hashes.

### Phase 2 exit gate

- No Fabric files changed.
- Every package follows the caller-owned `MPSCommandBuffer` contract.
- Image-only outputs require no CPU synchronization.
- Numerical outputs preserve the mandatory compile-time sync/async behavior without package-owned commit/wait.
- User-run package validation passes or exceptions are explicitly accepted.
- The user approves Phase 2 before optimization begins.

## Phase 3 — MPS SPM weights, quantization, and optimization

### Goal

Improve package load time, memory use, GPU execution, and model size while preserving the Phase 1 reference behavior and the Phase 2 API contract.

### Absolute boundary

- MPS package exporters, weight formats, manifests, graph construction, Metal kernels, resources, tests, benchmarks, and documentation only.
- No Fabric changes.
- No optimization is retained without isolated correctness evidence and before/after performance data.
- ANE-specific success claims and ANE-driven architecture changes remain in Phase 4.

### 3.1 Baseline before optimization

For every model and shipped static shape, record:

- Cold weight load time.
- Graph construction and specialization time.
- First inference time.
- Warm p50 and p95 package latency.
- CPU encoding time.
- GPU duration.
- Peak and steady-state memory.
- Weight file and compiled/runtime weight size.
- Allocation count after warm-up.
- Relevant task-quality metrics.

Do not compare results collected with different checkpoints, shapes, thermal conditions, or build configurations.

### 3.2 Exact graph and exporter transformations

Perform exact FP32 graph surgery before changing precision.

#### ZipDepth

- Fold inference batch normalization into preceding convolution weights and biases.
- Reparameterize each QARep block by combining its folded 3×3 branch, padded 1×1 branch, and identity kernel into one 3×3 convolution where mathematically exact.
- Verify each converted block and the complete model against the Phase 1 unfused reference.
- Move mean/std normalization only when padding and boundary semantics remain exact.
- Treat replacement of parallel dilated depthwise operations with a larger kernel as a benchmark experiment, not a predetermined improvement.

#### TAPNext++ and TAPIR

- Evaluate exact concatenation of projections that consume the same input, followed by a split.
- Evaluate exact consolidation of sliced feed-forward up-projections.
- Precompute immutable weight transposes, scale offsets, and constant transforms in the exporter.

#### All packages

- Remove runtime constant reshapes, casts, and transposes when they can be performed once during export without changing behavior.
- Prefer high-level MPSGraph operations when they give the compiler more fusion context.
- Keep source activation, padding, interpolation, and normalization behavior exact.
- Change one graph region at a time and retain its differential result.

### 3.3 Weight representation and loading efficiency

- Measure the lifetime of mapped bytes, decoded arrays, repacked `Data`, graph constants, and executable-owned storage before changing the loader.
- Eliminate duplicate whole-model copies where the graph API and lifetime rules permit safe byte-backed constants.
- Store pretransposed or fused weights directly when their conversion has passed exact validation.
- Record dtype, shape, storage order, compression scheme, axis, group/block size, scale/zero-point metadata, checksum, and exporter version in the manifest.
- Keep old-format compatibility only when it is tested and does not make corruption ambiguous.
- Treat `.mpsgraphpackage` serialization and bundled metallibs as cold-start experiments with versioned invalidation rules.

### 3.4 Precision exploration

Precision is configured explicitly; do not rely on the macOS 26 reduced-precision fast-math option.

Explore in this order:

1. FP16 weight storage with FP32 arithmetic unchanged where possible.
2. FP16 inputs and large convolution/projection operations.
3. Mixed precision with FP32 normalization, softmax, reductions, recurrent/SSM state, sensitive accumulations, prediction heads, and public outputs as needed.
4. Broader FP16 only where full-tensor and task metrics remain acceptable.

Package guidance:

- ZipDepth: strongest broad-FP16 candidate, but retain FP32 softmax/global-context reductions initially.
- MediaPipe: evaluate each checkpoint separately; do not assume all generated models share one safe precision policy.
- TAPNext++/TAPIR: begin from their existing mixed-precision design and distinguish storage precision from compute precision.
  - TAPIR status: float32 now runs a BC1S refinement mixer. At 32 points × 4 passes, graph construction fell 30 s → 2 s and per-frame CPU encode 35.9 → 25.8 ms, at float32 accuracy.
  - `float16Mixer` (the BC1S mixer in float16) is kept for evaluation. At 32 points × 4 passes the workload is CPU-bound and float16 gains only about 1.8 ms, and it misses the frame-1 occlusion tolerance (0.053 against 0.05).
  - Next: benchmark 256 points × {1, 4} passes × {float32, float16Mixer}.
  - If float16 wins where the GPU is the bottleneck, find and keep the precision-sensitive layer in float32 rather than loosening tolerances. Otherwise remove `float16Mixer`.
- FlashDepth: prioritize FP16 storage for large weights/activations while retaining FP32 normalization, softmax, Mamba/state accumulation, and sensitive reductions.
- EfficientTAM: test one stage at a time and retain its FP32 reference because blanket FP16 has shown severe degradation.

### 3.4.1 Symmetric precision tiers (cross-package goal)

Every MPS-backed Fabric node should eventually expose the same three user-facing quality tiers, with the same names and meaning:

- **Full:** float32.
- **Mixed:** float32 and float16.
- **Low:** float16 with quantized weights.

Each package maps the tiers onto what it actually implements (for example ZipDepth `ZipDepthPrecision`, TAPIR `TAPIRComputePrecision`). Design the shared API once the per-package precision options from Phase 3 have settled. Exposing the tiers in nodes is Phase 5.

### 3.4.2 Completion checklist: three tiers and ANE, every model

Requirement: every model in every active package offers float32, mixedFloat16, and float16, and is authored for the Neural Engine wherever that is viable.

What decides MPSGraph's ANE placement, from probes checked against powermetrics on 2026-09-29 (details in 4.3 TAPIR):
- In every probe run, only float16 graphs containing depthwise spatial convolutions reached the ANE (MobileNet-style: 1×1, depthwise 5×5, 1×1).
- Plain 3×3 convolution stacks, 1×1-only stacks and MLP stacks stayed on the GPU at every width and grid size tested.
- A tensor with every position on the last axis (`[1, C, 1, N]`) stayed on the GPU. The same data as a 2-D grid (`[1, C, h, w]`) reached the ANE.
- ANE compilation shows up as a build-time jump well above the GPU rate of about 1.3 ms per op.
- It also takes enough depthwise work. MobileNet blocks at 256 channels and 32×32 reached the ANE with 16 layers and not with 2, just as the pose detector only engaged after 40 ops.
- Individually, these reached the ANE inside a qualifying graph: channel LayerNorm, sigmoid GELU, erf GELU, grouped 1×1 convs, channels-last matmul linear layers, channel↔width transposes, and bilinear resize.

| Package / model | Three tiers | ANE status | Next step |
|---|---|---|---|
| ZipDepth | done | none; parked. The network is 15 dense 3×3 QARep convs, grouped convs (4, 16 and 96 groups) and a single depthwise 5×5. By the placement rules (dense 3×3 stacks stay on the GPU, and the ANE needs many depthwise blocks) that predicts GPU only, which matches the 0 mW measured earlier. No single op is to blame, so there is nothing to bisect; the weights fix the architecture | none |
| MediaPipe (11 models) | done | float16 runs on the ANE (powermetrics); up to −57% | none. The hand detector's float16 "slowdown" (1.05 → 1.42 ms) compared runs made at different times. Interleaved in one command, float16 with ANE ties float32 (1.37–1.40 against 1.35–1.41 ms) at a quarter of the CPU encode. A GPU-only float16 build (`.level0`) is about 7% faster but gives up the ANE, so keep ANE placement allowed. Benchmark lesson: interleave tiers in one command; separate runs varied by 35% |
| TAPIR | done; all three pass the PyTorch test (float16 has its own limits: tracks ≤ 0.2 px) | none; parked (no depthwise spatial convs anywhere) | none; revisit only if MPSGraph placement changes |
| TAPNext++ | out of scope (2026-09-29): Fabric's point-tracking node uses TAPIR, since TAPNext++ was too slow. Back pocket, like FlashDepth | — | — |
| EfficientTAM (7 stages) | done for the 5 weighted stages and the tracker (`EfficientTAMPrecision`, `precision:` on each stage and on `EfficientTAMVideoTracker`). Reduced tiers are 54–88 dB against float32, and the 11-frame tracker keeps ≥ 0.9998 foreground IoU against PyTorch in every tier. Mask selector and postprocessor have no weights and stay float32 only (decided 2026-09-29) | none; parked. The memory encoder has only 2 depthwise blocks, and MPSGraph needed about 16 at that size (probe: 2 no, 16 yes). The other stages are attention and dense convolutions | none. Benchmark (M1 Max, 120 frames, release): best FPS float32 55.3, mixed 56.7, float16 53.2. At 1 frame in flight: 45.5 / 45.1 / 48.7. Float16 cuts the decoder's CPU encode 1.8 → 1.0 ms; otherwise the tiers are within noise in isolation. Keep all three (under-load gains untested) |
| FlashDepth | back pocket | — | — |

### 3.5 Quantization and palettization exploration

Quantization is an experiment matrix, not a blanket conversion.

1. Use real representative inputs and model-specific output metrics.
2. Establish the uncompressed FP16 or mixed-precision baseline first.
3. Start with weight-only int8/per-channel candidates.
4. Explore int4 per-channel and per-block candidates only after int8 results are understood.
5. Explore LUT/palettized candidates separately from linear quantization.
6. Account for scale, zero-point, LUT, grouping, and alignment overhead when reporting effective bit width and size.
7. Detect layers silently skipped because their dimensions are incompatible with the selected block/group size.
8. Refine promising candidates by leaving sensitive layers uncompressed.

Initial layers to protect:

- First and last layers of each major submodel.
- Normalization parameters and bias where savings are negligible.
- Recurrent and temporal state.
- Sensitive attention, prediction, confidence, and output projections.
- Any layer that fails an isolated quality gate.

For each experiment, report:

- Actual and theoretical model size.
- Effective average bit width.
- Compression ratio including metadata overhead.
- Full-output quality metrics.
- Cold-load and steady-state latency.
- Peak memory.
- Whether dequantization fused into the consuming operation.
- Whether GPU placement or dispatch behavior changed.

Prioritize TAPNext++ and TAPIR because weight bandwidth and checkpoint size are largest. ZipDepth compression is lower priority unless load time or memory is a demonstrated problem.

### 3.6 GPU and resource optimization

- Profile first with Metal System Trace and appropriate counters.
- Remove steady-state allocation and pool package-owned transient resources.
- Precompile bundled Metal sources after separately resolving any correctness race.
- Benchmark shared, private, and heap-backed immutable weights rather than assuming one storage mode wins on unified memory.
- Evaluate native-layout preprocessing only against both GPU performance and exact preprocessing parity.
- Investigate compatible texture-backed outputs, but retain explicit copies when row alignment, stride, aliasing, or lifetime would become fragile.

FlashDepth-specific candidates, in trace-driven order:

- Large projection/matmul kernels.
- FP16 storage with FP32 accumulation.
- Dispatch and memory-traffic fusion around bias, activation, LayerScale, and residual operations.
- Attention tiling/register pressure.
- Post-ViT convolution strategy.
- Mamba/SSD parallelism.

`simdgroup_matrix`, implicit-GEMM convolution, and larger fused kernels remain prototypes until traces demonstrate a net benefit and validation demonstrates unchanged behavior.

### Phase 3 deliverables

- An exact-rewrite report for every retained graph transformation.
- A precision map for every retained model variant.
- An accuracy-size-latency-memory table for quantization and palettization candidates.
- Before/after GPU traces for retained kernel and resource optimizations.
- Rejected experiments recorded with evidence.
- Versioned weight manifests and migration documentation.
- Focused package commits and recorded hashes.

### Phase 3 exit gate

- No Fabric files changed.
- Every retained optimization passes its package-specific correctness and quality gates.
- Every retained performance change has measured package-level benefit.
- The Phase 2 command-buffer and output contract remains unchanged.
- User-run validation passes or exceptions are explicitly accepted.
- The user chooses which precision/compression variants are production candidates.
- The user approves Phase 3 before ANE work begins.

## Phase 4 — MPSGraph and Apple Neural Engine

### Goal

Measure current MPSGraph hardware placement, improve ANE eligibility where it produces a real product benefit, and retain GPU-oriented variants where they are superior.

### Architectural facts

- MPSGraph optimization level 1 can use a placement pass across GPU, CPU, and Neural Engine.
- Every reviewed package already requests level 1, so some compatible regions may already use ANE.
- MPSGraph controls placement; FP16, static shapes, supported operations, alignment, rank, and layout improve eligibility but do not guarantee placement.
- `allowFP16Intermediates` on newer OS versions is not the ANE enable switch.
- `commitAndContinue` or a “region” label does not by itself prove ANE execution.
- ANE utilization without a net latency, energy, or GPU-budget benefit is not success.

### 4.1 Placement observability

Before re-authoring any graph:

- Define a repeatable profiling recipe using Metal System Trace and available Neural Engine instrumentation.
- Validate the recipe using a small known-eligible FP16 convolution graph.
- Record current placement for every retained Phase 3 model variant by device, OS, checkpoint, shape, and precision.
- Record CPU encode time, accelerator transitions, command-buffer segmentation, GPU time, Neural Engine activity, wall latency, memory, and energy where measurable.
- Compare level 0 and level 1 only as a diagnostic experiment; do not assume level 0 is the correct GPU production mode.

### 4.2 ANE eligibility experiments

Test one variable at a time:

- Fully static executable shapes.
- Explicit FP16 tensors and dtype-matched scalar constants.
- Removal of avoidable FP32 islands.
- Rank-five-or-lower equivalent formulations where possible.
- Layout and last-dimension alignment variants.
- Fewer casts, transposes, reshapes, and host-visible boundaries.
- High-level convolution, matrix multiplication, normalization, activation, pooling, resize, and pixel-shuffle operations.
- Larger compiler-visible graph regions rather than manually fragmented micrographs.

Rules derived from other Apple model toolchains are hypotheses for MPSGraph until verified by MPSGraph traces. Do not assume that a CoreAI/Core ML eligibility rule maps exactly to MPSGraph placement.

### 4.3 Package priority

#### 1. ZipDepth

- First full-model candidate after exact QARep/BN fusion and validated mixed precision.
- Status (Phase 3, parked): even with every divide replaced by a reciprocal multiply, MPSGraph does not attempt ANE placement for the float16 graph. There is no ANE compile log, construction time stays flat (0.22 s, where MediaPipe's jumped 5–20×), and powermetrics reads 0 mW. Resolved 2026-09-29 with no bisect needed: the probes in 3.4.2 show MPSGraph keeps dense 3×3 stacks on the GPU and needs many depthwise blocks to use the ANE. ZipDepth is mostly dense 3×3 QARep convs, with one depthwise 5×5, so it stays on the GPU by architecture, not because of any one op.
- Test all shipped static resolutions separately.
- Inspect global-context softmax/reduction placement and any boundary casts.
- Accept hybrid placement only when transfers do not erase the benefit.

#### 2. MediaPipe

- Start with one representative detector or landmark checkpoint.
- Replace rank-six depth-to-space intermediates only with an exact tested formulation.
- Small models may run faster on GPU because ANE dispatch/transfer overhead can dominate; energy and freed GPU budget are valid benefits if measured.
- Generalize only to checkpoint families that show equivalent behavior.

#### 3. TAPIR

- Evaluate a coarse convolutional feature-extractor region before recurrent/refinement work.
- Keep state explicit and validate cross-accelerator transfer costs.
- Status (Phase 3, parked 2026-09-29): no TAPIR region reaches the ANE through MPSGraph.
  - **Feature extractor:** split into its own executable (kept, exact in float32). It stays on the GPU, since it's a plain 3×3 ResNet. Float16 got slightly faster: 17.1 against 18.1 ms per frame at 256 points and 1 pass.
  - **Refinement mixer:** rebuilt in grid layout (`gridMixer`, `gridMixerCore`; exact against `bc1sMixer` in float32, and not used by the model). No ANE even with no layout conversions, with state outputs dropped, or with 1 block, because it is all 1×1 and MLP work.
  - **Probe tests, kept:** `ANEPlacementProbeTests` and `TAPIRMixerANEProbeTests` in MPS-TAPNextPlusPlus, and `MediaPipeANEPrefixProbeTests` in MPS-MediaPipe.
  - **Untried:** an identity depthwise conv per mixer block as an ANE lure.

#### 4. TAPNextPlusPlus

- Remain GPU-first unless profiling reveals a large contiguous profitable ANE region.
- Do not sacrifice fused GPU attention or numerical stability merely to increase ANE utilization.

#### 5. EfficientTAM

- Preserve FP32-sensitive transformer regions.
- Evaluate convolutional regions only when the boundary is coarse enough to amortize transitions.
- Rank-six window operations require exact rank-safe alternatives before they can be candidates.

#### 6. FlashDepth

- Its custom Metal kernels remain GPU-only.
- Greater ANE use requires an alternate MPSGraph expression of major stages, not a placement flag.
- Attempt that re-authoring only if Phase 3 shows a clear product reason and a coarse partition can avoid expensive transfers.

### 4.4 Acceptance criteria

An ANE-oriented variant is retained only if:

- Instruments demonstrate Neural Engine execution for the exact tested configuration.
- Full-tensor and task-quality gates pass.
- Temporal state remains correct where applicable.
- End-to-end latency, energy, or available GPU budget improves by an agreed meaningful amount.
- CPU encode cost and accelerator transitions do not create unacceptable regressions.
- Behavior is stable across the supported OS and device matrix.
- The Phase 2 caller-owned command-buffer contract remains intact.

If partial placement is slower or less predictable, keep the GPU-oriented variant. Do not contort the model solely to obtain ANE activity.

### Phase 4 deliverables

- A placement matrix by package, checkpoint, shape, precision, device, and OS.
- Traces showing retained GPU/ANE/CPU regions and transition costs.
- Quality, latency, energy, memory, and GPU-budget comparisons.
- A documented decision for every package: retain GPU, retain automatic hybrid placement, or retain an ANE-friendly variant.
- Rejected ANE experiments recorded with evidence.
- Focused package commits and recorded hashes.

### Phase 4 exit gate

- No Fabric files changed.
- No user-facing “force ANE” claim or control has been introduced.
- Every ANE claim is supported by observed placement and a net product benefit.
- User-run validation passes or exceptions are explicitly accepted.
- The user selects the variants that may proceed to a separately approved Fabric integration phase.

## Phase boundary report template

At the end of each phase, report:

1. Repositories and exact branches touched.
2. Starting and ending commit hashes.
3. Commits created, in order.
4. Files changed by repository.
5. User-run validation requested and results received.
6. Numerical comparison results.
7. Performance and memory results where applicable.
8. Known limitations and unresolved questions.
9. Rejected experiments and why they were rejected.
10. Confirmation that Fabric nodes were untouched after Phase 0.
11. Exact proposed scope of the next phase.

Then stop and wait for explicit approval.

## Phase 5 — Fabric node cleanup and integration (tracked, not yet scheduled)

Starts only after Phases 1 through 4 and explicit approval. Node features stay the same; this phase fixes node bugs and adopts the new SPM APIs.

Tracked node items so far:

- MediaPipe detection and landmark nodes reuse one shared output buffer set across overlapping frames. A later frame can overwrite results while the previous frame's completion handler is still reading them. Give each in-flight submission its own output/readback slot (see the TAPIR readback ring in `TAPIRPointTrackingNode.swift`).
- Migrate every node to the Phase 2 SPM API. Nodes pass Fabric's `MPSCommandBuffer` as-is and never commit it. Synchronous paths use a dedicated `MPSCommandBuffer` the node creates, commits and waits on itself.
- Keep each node's existing sync/async selection working on top of the flexible SPM API.
- Pool per-frame allocations (for example the EfficientTAM tracker node's model input buffer, allocated every frame at `EfficientTAMTrackerNode.swift:344`).
- TAPIR node defaults to `computePrecision: .mixedFloat16`. Switch it to `.float32`. After the Phase 3 BC1S mixer (4 refinements, 32 points), float32 builds its graph in about 2 s against 29 s for mixedFloat16, encodes a frame in 25.8 ms against 30.0 ms, and matches PyTorch to about 4e-5 px against about 0.03 px.
- ZipDepth now offers `precision: .float16` (Phase 3). In release builds float16 cuts wall time 17% at 1024×1024 (12.55 → 10.42 ms), is flat at 384×384, and measures 49.8 dB against the float32 reference at 384. Consider using float16 for the node's larger resolutions (768 and up) or exposing it as a setting.
- Keep model compilation out of the render path (`SharedModelCache` holds its lock during a roughly 1 s compile that `execute` can trigger).
- User feedback from the first Fabric validation build (2026-09-30):
  - **All MPS nodes, Settings:** changing a setting doesn't update the menu until the settings view is closed and reopened. Remove the control-size and font-size modifiers the settings content sets; the wrapper view owns both. Precision offers only Float32 / Mixed: add float16 and use friendly labels (e.g. "High Quality / Mixed / Low"). Add the GPU-only option (below).
  - **TAPIR node:** weights seem to load on the first set of clicked points, not earlier. Port renames: Reset Tracking → Reset, Tracked Points → Points, Visibility Confidence → Confidence.
  - **MediaPipe nodes, port renames:** Landmarks (Scene Space) → a "3D" landmarks name (exact name to confirm), Previous Region / Previous Rotation → Tracked Region / Tracked Rotation, Redetect every n frames → Re-Detect Interval.
- Compute-units option in every MPS SPM's contract, exposed as a node Setting next to precision (implemented 2026-09-30: `MediaPipeComputeUnits`, `ZipDepthComputeUnits`, `TAPIRComputeUnits` (in `TAPIRConfiguration`), `EfficientTAMComputeUnits` on every stage and the tracker; Fabric `MPSModelComputeUnits` / `modelComputeUnits` with a "Compute" row on all 10 MPS nodes; precision tiers likewise via `MPSModelPrecision` / `modelPrecision`):
  - **Values:** `.gpuAndNeuralEngine` (default, today's behaviour) and `.gpuOnly`, with the same names in every package, like the precision tiers.
  - **Mapping:** MPSGraph `optimizationLevel`: `.level1` lets the placement pass use the ANE or CPU; `.level0` keeps everything on the GPU. MPSGraph can forbid the ANE but cannot force it; in practice only float16 graphs with enough depthwise work reach it (see 3.4.2).
  - **Scope:** the option is chosen when the graph is built, so in nodes it is a Settings value with a custom initializer, not a port. Changing it rebuilds the model. Fold it into the shared configuration from 3.4.1 as one value holding precision and compute units.
  - **Before committing per package:** measure both settings interleaved in one command. `.level0` also drops MPSGraph's other level-1 optimizations. The MediaPipe hand detector as the reference: float32 tied either way, and float16 GPU-only was about 7% faster in wall time but used about 4× the CPU encode.
  - **Starting point:** MediaPipe's test-only `MediaPipeMPSGraph.compilesForGPUOnly` hook (benchmark env `MEDIAPIPE_GPU_ONLY=1`) becomes this option there.

## Back pocket — MPS-FlashDepth (not in active scope)

Tracked for later; not worked on until explicitly pulled in.

- Correctness: `encode()` swaps the Mamba state buffers as soon as it encodes (`swapAllStateBuffers()`), before the GPU has run anything. A dropped or failed command buffer still advances the recurrent state. The swap should happen only once the work is known to have been submitted successfully.
- Correctness: investigate the concurrent shader-compilation numerical divergence as a possible race or uninitialized-memory bug.
- API: remove the temporary `MPSCommandBuffer` wrapper inside `encodePipeline`, plus the `commit:` parameter.
- Performance: `simdgroup_matrix` matmul, attention register pressure, bias/activation/LayerScale/residual fusion, post-ViT convolutions, Mamba SSD parallelism, float16 storage.
- ANE: its custom Metal kernels are GPU-only; ANE use would require re-expressing major stages in MPSGraph.

## Explicitly deferred until Phase 5 (Fabric integration)

- Updating Fabric package revisions.
- Changing any Fabric node to call the new package APIs.
- Adding node output/readback rings.
- Changing node compile-flag behavior.
- Pooling Fabric-owned per-frame resources.
- Changing node settings, ports, serialization, registration, or UI.
- Iterator batching or iterator semantic changes.
- Adding user-facing precision, compression, backend, or energy settings.
- End-to-end Fabric performance tuning.

The future integration phase must begin from the Phase 0 Fabric recovery commit and explicitly select the package commits produced by Phases 1 through 4.
