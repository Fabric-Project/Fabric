# MPS Implementation Review: CoreAI / ANE Skill Suggestions

I've finished the review and made no changes. The skills weren't installed as Claude skills: I found `working-with-coreai`, `model-authoring` and `model-compression-exploration` under `~/.codex/skills` and read them from there.

**Short version:** those skills are written for a PyTorch → CoreAI export pipeline. The Neural Engine (ANE) can only be reached through CoreML or CoreAI, never through MPSGraph, and that conflicts with your MPS-first policy. Most of the value is in their GPU rules (precision, weight compression, fusing layers ahead of time), and those apply directly to the MPSGraph and Metal code. That's where the biggest gains are.

## 1. Changes that apply to every package

**a. The FP16 speed-up never runs on macOS 15, including your machine.**
ZipDepth, MediaPipe, FlashDepth's patch embed and TAPNext only turn on `reducedPrecisionFastMath = .allowFP16Intermediates` inside `#available(macOS 26.0, …)` (for example `MPS-ZipDepth/Sources/MPSZipDepth/ZipDepthMPSGraph.swift:92`). You're on Darwin 24.6 (macOS 15), so those graphs currently run entirely in float32. The skills recommend float16 weights by default, keeping float32 only for normalization, attention and recurrent state. TAPNext's `mixedFloat16` path already does this with explicit casts that work on macOS 15; ZipDepth and MediaPipe don't.

**b. All weights are stored as float32, and each one is copied three times at load.**
- In `*Weights.constant()`, the memory-mapped `Data` is copied into a `[Float]`, then into a new `Data`, then into the MPSGraph constant. For TAPNext that means about 741 MiB of weights passing through several copies at load time.
- Storing float16 on disk and passing a `Data` slice straight to `graph.constant` halves the size and removes the intermediate copies.
- Beyond that, MPSGraph on macOS 15 / iOS 18 can store weights compressed and expand them during the matrix multiply: 8-bit and 4-bit values (`dequantize(_:scaleTensor:zeroPointTensor:…)`) or lookup-table compression (`dequantize(_:LUTTensor:…)`). This is where the compression skill fits. Compress per channel, leave the first and last layers uncompressed (the skill reports up to +9 dB PSNR from that alone), and gate on its quality thresholds: 8-bit ≥ 50 dB, 4-bit ≥ 35 dB. TAPNext and TAPIR would benefit most.

**c. Fuse layers ahead of time.** The skills say to use the fewest, highest-level operations and to merge consecutive convolutions that have no activation between them.
- **ZipDepth `qaRepBlock`:** a 3×3 conv with batch norm, a 1×1 conv with batch norm, and an identity path. That's QARepVGG, which was designed to collapse exactly into one 3×3 conv plus bias. There are 16 of these blocks.
- **ZipDepth `minimalMultiScale`:** a depthwise 3×3 plus a depthwise 3×3 with dilation 2 gives the same result as a single depthwise 5×5.
- **Batch norm:** ZipDepth runs every batch norm as a separate multiply and add; it can be folded into the preceding conv's weights. The mean/std input normalization can go into the first conv or the preprocessing kernel.
- **TAPNext:** `linear_x` and `linear_y` read the same input and can be one matmul. `ffw_up` is two sliced matmuls that can be one `[768, 6144]` matmul. The RMSNorm `scale + 1` and the weight transposes done at graph-build time can be precomputed.

**d. Data layout.** Every graph takes an NHWC input and immediately transposes it to NCHW. The preprocessing kernels, such as `MPS-MediaPipe/Sources/MPSMediaPipe/Utils/Compute/MediaPipeCropPreprocess.metal:67`, could write NCHW (optionally float16) directly and apply the normalization there.

## 2. Per package

**FlashDepth has the biggest GPU-side gains.**
- The `flashDepthLinear` kernel is a scalar float32 tiled matrix multiply with one output per thread. Rewriting it with `simdgroup_matrix` (supported on M1 and later), half-precision inputs and float32 accumulation should be the largest single speed-up of any item here.
- The fused attention kernel holds `q[64]` and `acc[64]` in float32 registers for every thread. That's the same register pressure you moved off MPSGraph to avoid. It also rescales with `exp` after every key instead of once per tile.
- The LayerScale and residual add could run at the end of the projection and `fc2` kernels. That removes 24 dispatches and 24 round trips through memory per frame.
- The post-ViT stage uses direct convolutions marked "correctness-first", and the Mamba SSD step runs as one threadgroup. These are probably the next bottlenecks.

**TAPNext and TAPIR:** the mixed-precision structure already matches the skills' GPU rules. What's left is compressing the weights (item 1b) and fusing the matmuls (item 1c).

**EfficientTAM:** keeping explicit attention because the fused version measured slower on an M1 Max is the right kind of decision. It runs in float32 by design; a TAPNext-style mixed path (float16 convs and projections only) is worth trying, checked against the PSNR thresholds.

**MediaPipe:** these models take about 0.5 ms, so precision changes are low priority.

## 3. Node side

- **Likely race condition in the MediaPipe nodes.** For example, `MediaPipeHandDetectionNode.outputBuffers` is a single shared set, reused every frame. The model allows 16 frames in flight, and the completion handler reads those buffers while the next frame's GPU work can already be writing them. Each in-flight slot needs its own output buffers. I found this by reading the code, not by running it.
- **Iterators.** Inside an Iterator, every hand or face runs as a separate synchronous command buffer with its own wait. Compiling the landmark model once for a fixed batch size N would replace N waits with one.
- **ZipDepth output copy.** The depth output is copied into a texture with a blit every frame. A texture created directly over that output buffer (`makeTexture(descriptor:offset:bytesPerRow:)`) would avoid the copy.

## 4. Where the Neural Engine could help

The case for the Neural Engine in Fabric is that it sits idle while inference competes with rendering on the GPU. It has real costs, though:
- It only runs through CoreML or CoreAI, which goes against your MPS-first policy.
- CoreAI's Swift API, as the skill shows it, is async `run(inputs:)`. I saw nothing showing it can encode into Fabric's command buffer, so results would arrive later, like the current `submit()` path.
- It needs an OS version check, since Fabric targets macOS 15.

Ranked by how well each model fits the skills' Neural Engine rules (fixed shapes, float16 only, strides of 2 or 3, conv-heavy):
1. **ZipDepth: strong fit.** The code itself calls it "the official ZipDepth-base NPU graph", and it's static-shaped with stride-2 convs, ReLU and batch norm. It's worth one experiment through the existing `inspect_coreml_compute_plan` tool.
2. **MediaPipe detectors:** worth considering only for energy use on iOS.
3. **EfficientTAM, FlashDepth, TAPNext: poor fit.** EfficientTAM loses too much accuracy in float16. FlashDepth has long-sequence attention plus Mamba state. TAPNext has 741 MiB of weights and recurrent state that's sensitive to float16.

**Possible macOS 26 route:** Metal 4's ML command encoder can run an exported model on the GPU inside a Metal command buffer, and its tensor matmul maps onto the GPU's neural accelerators on M5-class chips. Both need macOS 26. The matmul could eventually replace FlashDepth's hand-written matmul kernel.

## 5. Suggested order

1. Explicit float16 weights and a mixed-precision path for ZipDepth, plus fixing the fast-math gate (1a, 1b)
2. Folding ZipDepth's blocks ahead of time (1c)
3. `simdgroup_matrix` matrix multiply and attention in FlashDepth
4. The per-slot output buffers in the MediaPipe nodes
5. Weight compression for TAPNext and TAPIR
6. Optionally, a Neural Engine experiment on ZipDepth
