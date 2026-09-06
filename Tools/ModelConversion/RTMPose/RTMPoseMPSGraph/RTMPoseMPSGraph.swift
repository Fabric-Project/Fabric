// RTMPoseMPSGraph.swift
//
// From-scratch MPSGraph reimplementation of RTMPose-Hand-Medium
// (CSPNeXt backbone + RTMCCHead), built once from exported weights and
// run per-frame on GPU via Metal Performance Shaders Graph — no CoreML.
//
// Architecture and shapes confirmed against the actual checkpoint via
// export_weights.py's exhaustive key-consumption check (134/134 tensors
// accounted for). use_rel_bias=false, pos_enc=false confirmed from the
// live config — the GAU head never invokes rope()/rel_pos_bias().
//
// Layout convention: NCHW throughout for the backbone (matches PyTorch's
// OIHW conv weight layout directly, no transposes needed there). Linear
// weights are [out, in] in PyTorch; transposed once at graph-build time
// (not per-frame) to [in, out] for matmul.

import Foundation
import MetalPerformanceShadersGraph

final class RTMPoseMPSGraph
{
    private let graph = MPSGraph()
    private let weights: RTMPoseWeights
    private let device: MPSGraphDevice
    private let commandQueue: MTLCommandQueue

    private let inputTensor: MPSGraphTensor
    /// [stem, stage1, stage2, stage3, stage4] — exposed for bisecting a
    /// mismatch against the PyTorch reference stage-by-stage. Only used by
    /// the debug/validation entry points below, not the hot path.
    private let backboneStageTensors: [MPSGraphTensor]
    private let backboneOutputTensor: MPSGraphTensor
    private let simccXTensor: MPSGraphTensor
    private let simccYTensor: MPSGraphTensor

    /// Compiled once at init — MPSGraph.run(feeds:targetTensors:) is a
    /// convenience method that re-validates/optimizes the graph on every
    /// call (measured ~65ms/call here, dominating the whole budget). The
    /// compiled MPSGraphExecutable skips that per-call cost; only this is
    /// used by the hot path (run(pixels:)).
    private let executable: MPSGraphExecutable

    private static let keypointCount = 21
    private static let inputSize = 256 // square input, matches Hand5's 256x256

    init(weightsBinaryURL: URL, weightsManifestURL: URL, metalDevice: MTLDevice) throws
    {
        self.weights = try RTMPoseWeights(binaryURL: weightsBinaryURL, manifestURL: weightsManifestURL)
        self.device = MPSGraphDevice(mtlDevice: metalDevice)
        guard let commandQueue = metalDevice.makeCommandQueue() else
        {
            throw NSError(domain: "RTMPoseMPSGraph", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create MTLCommandQueue"])
        }
        self.commandQueue = commandQueue

        let input = self.graph.placeholder(
            shape: [1, 3, NSNumber(value: Self.inputSize), NSNumber(value: Self.inputSize)],
            dataType: .float32,
            name: "input"
        )
        self.inputTensor = input

        let stageTensors = Self.buildBackboneStages(graph: self.graph, weights: self.weights, input: input)
        self.backboneStageTensors = stageTensors
        let backboneOutput = stageTensors.last!
        self.backboneOutputTensor = backboneOutput
        let (simccX, simccY) = Self.buildHead(graph: self.graph, weights: self.weights, features: backboneOutput)
        self.simccXTensor = simccX
        self.simccYTensor = simccY

        let feedShapes: [MPSGraphTensor: MPSGraphShapedType] = [input: MPSGraphShapedType(shape: input.shape!, dataType: .float32)]
        self.executable = self.graph.compile(with: self.device, feeds: feedShapes, targetTensors: [simccX, simccY], targetOperations: nil, compilationDescriptor: nil)
    }

    /// Backbone output only (768x8x8 feature map), for bisecting a
    /// mismatch against the PyTorch reference — isolates whether the bug
    /// is in CSPNeXt or in RTMCCHead.
    func runBackboneOnly(pixels: [Float]) -> [Float]
    {
        self.runBackboneStage(pixels: pixels, stageIndex: self.backboneStageTensors.count - 1)
    }

    /// stageIndex: 0=stem, 1=stage1, 2=stage2, 3=stage3, 4=stage4.
    func runBackboneStage(pixels: [Float], stageIndex: Int) -> [Float]
    {
        let inputData = MPSGraphTensorData(
            device: self.device,
            data: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.stride),
            shape: self.inputTensor.shape!,
            dataType: .float32
        )
        let target = self.backboneStageTensors[stageIndex]
        let results = self.graph.run(feeds: [self.inputTensor: inputData], targetTensors: [target], targetOperations: nil)
        return Self.floatArray(from: results[target]!)
    }

    /// `pixels` is planar float32 RGB, already normalized (ImageNet mean/std
    /// applied by the caller — this graph has no baked-in preprocessing,
    /// unlike CoreML's ImageType), shape [3, 256, 256], row-major per channel.
    func run(pixels: [Float]) -> (simccX: [Float], simccY: [Float])
    {
        let inputData = MPSGraphTensorData(
            device: self.device,
            data: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.stride),
            shape: self.inputTensor.shape!,
            dataType: .float32
        )

        let results = self.executable.run(with: self.commandQueue, inputs: [inputData], results: nil, executionDescriptor: nil)

        let simccX = Self.floatArray(from: results[0])
        let simccY = Self.floatArray(from: results[1])
        return (simccX, simccY)
    }

    private static func floatArray(from tensorData: MPSGraphTensorData) -> [Float]
    {
        let count = tensorData.shape.map(\.intValue).reduce(1, *)
        var values = [Float](repeating: 0, count: count)
        tensorData.mpsndarray().readBytes(&values, strideBytes: nil)
        return values
    }

    // MARK: - Shared building blocks

    static func convBNFolded(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportName: String, stride: Int, groups: Int = 1) -> MPSGraphTensor
    {
        let weightShape = weights.shape(named: "\(exportName).weight") // [out, in/groups, kH, kW]
        let kernelHeight = weightShape[2]
        let kernelWidth = weightShape[3]
        let padding = (kernelHeight - 1) / 2 // all convs here use "same"-style symmetric padding for odd kernels

        let weightTensor = weights.constant(graph, named: "\(exportName).weight")
        let biasTensor = weights.constant(graph, named: "\(exportName).bias")

        let descriptor = MPSGraphConvolution2DOpDescriptor(
            strideInX: stride, strideInY: stride,
            dilationRateInX: 1, dilationRateInY: 1,
            groups: groups,
            paddingLeft: padding, paddingRight: padding,
            paddingTop: padding, paddingBottom: padding,
            paddingStyle: .explicit,
            dataLayout: .NCHW,
            weightsLayout: .OIHW
        )!

        let conv = graph.convolution2D(x, weights: weightTensor, descriptor: descriptor, name: nil)
        let outChannels = weightShape[0]
        let biasReshaped = graph.reshape(biasTensor, shape: [1, NSNumber(value: outChannels), 1, 1], name: nil)
        return graph.addition(conv, biasReshaped, name: nil)
    }

    static func silu(graph: MPSGraph, x: MPSGraphTensor) -> MPSGraphTensor
    {
        graph.multiplication(x, graph.sigmoid(with: x, name: nil), name: nil)
    }

    /// ConvModule: conv+BN (folded) + SiLU.
    static func convModule(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportName: String, stride: Int, groups: Int = 1) -> MPSGraphTensor
    {
        silu(graph: graph, x: convBNFolded(graph: graph, weights: weights, x: x, exportName: exportName, stride: stride, groups: groups))
    }

    /// CSPNeXtBlock: conv1 (plain 3x3 ConvModule) -> conv2 (5x5 depthwise +
    /// 1x1 pointwise ConvModules) -> optional residual add.
    static func cspNeXtBlock(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportPrefix: String, addIdentity: Bool) -> MPSGraphTensor
    {
        let identity = x
        var out = convModule(graph: graph, weights: weights, x: x, exportName: "\(exportPrefix).conv1", stride: 1)

        let depthwiseChannels = weights.shape(named: "\(exportPrefix).conv2_depthwise.weight")[0]
        out = convModule(graph: graph, weights: weights, x: out, exportName: "\(exportPrefix).conv2_depthwise", stride: 1, groups: depthwiseChannels)
        out = convModule(graph: graph, weights: weights, x: out, exportName: "\(exportPrefix).conv2_pointwise", stride: 1)

        if addIdentity
        {
            out = graph.addition(out, identity, name: nil)
        }
        return out
    }

    /// PyTorch nn.Hardsigmoid: clamp(x/6 + 0.5, 0, 1) — NOT the same as
    /// plain sigmoid. Confirmed from mmdetection's se_layer.py ChannelAttention,
    /// which uses nn.Hardsigmoid() specifically, not Sigmoid.
    private static func hardSigmoid(graph: MPSGraph, x: MPSGraphTensor) -> MPSGraphTensor
    {
        let scaled = graph.addition(
            graph.multiplication(x, graph.constant(1.0 / 6.0, dataType: .float32), name: nil),
            graph.constant(0.5, dataType: .float32),
            name: nil
        )
        let clampedLow = graph.maximum(scaled, graph.constant(0.0, dataType: .float32), name: nil)
        return graph.minimum(clampedLow, graph.constant(1.0, dataType: .float32), name: nil)
    }

    /// ChannelAttention: global-avg-pool -> 1x1 conv (with bias, no norm/act) -> hardsigmoid -> channel-wise scale.
    static func channelAttention(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportPrefix: String) -> MPSGraphTensor
    {
        let pooled = graph.mean(of: x, axes: [2, 3], name: nil) // [B,C,1,1]

        let fcWeight = weights.constant(graph, named: "\(exportPrefix).fc.weight") // [C,C,1,1]
        let fcBias = weights.constant(graph, named: "\(exportPrefix).fc.bias")
        let descriptor = MPSGraphConvolution2DOpDescriptor(
            strideInX: 1, strideInY: 1, dilationRateInX: 1, dilationRateInY: 1, groups: 1,
            paddingLeft: 0, paddingRight: 0, paddingTop: 0, paddingBottom: 0,
            paddingStyle: .explicit, dataLayout: .NCHW, weightsLayout: .OIHW
        )!
        var gate = graph.convolution2D(pooled, weights: fcWeight, descriptor: descriptor, name: nil)
        let outChannels = weights.shape(named: "\(exportPrefix).fc.bias")[0]
        gate = graph.addition(gate, graph.reshape(fcBias, shape: [1, NSNumber(value: outChannels), 1, 1], name: nil), name: nil)
        gate = hardSigmoid(graph: graph, x: gate)

        return graph.multiplication(x, gate, name: nil) // broadcasts [B,C,1,1] over [B,C,H,W]
    }

    /// CSPLayer: main_conv/short_conv (1x1) -> N blocks on main branch ->
    /// concat(main, short) -> optional channel attention -> final_conv (1x1).
    private static func cspLayer(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportPrefix: String, numBlocks: Int, addIdentity: Bool) -> MPSGraphTensor
    {
        var main = convModule(graph: graph, weights: weights, x: x, exportName: "\(exportPrefix).main_conv", stride: 1)
        let short = convModule(graph: graph, weights: weights, x: x, exportName: "\(exportPrefix).short_conv", stride: 1)

        for blockIndex in 0..<numBlocks
        {
            main = cspNeXtBlock(graph: graph, weights: weights, x: main, exportPrefix: "\(exportPrefix).block\(blockIndex)", addIdentity: addIdentity)
        }

        var combined = graph.concatTensors([main, short], dimension: 1, name: nil)
        combined = channelAttention(graph: graph, weights: weights, x: combined, exportPrefix: "\(exportPrefix).attention")
        return convModule(graph: graph, weights: weights, x: combined, exportName: "\(exportPrefix).final_conv", stride: 1)
    }

    /// SPPBottleneck: 1x1 conv -> three parallel "same"-padded max pools
    /// (kernels 5,9,13) -> concat with the pre-pool feature -> 1x1 conv.
    private static func sppBottleneck(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportPrefix: String) -> MPSGraphTensor
    {
        let reduced = convModule(graph: graph, weights: weights, x: x, exportName: "\(exportPrefix).conv1", stride: 1)

        var pooled: [MPSGraphTensor] = [reduced]
        for kernelSize in [5, 9, 13]
        {
            let pad = kernelSize / 2
            let descriptor = MPSGraphPooling2DOpDescriptor(
                kernelWidth: kernelSize, kernelHeight: kernelSize,
                strideInX: 1, strideInY: 1,
                dilationRateInX: 1, dilationRateInY: 1,
                paddingLeft: pad, paddingRight: pad, paddingTop: pad, paddingBottom: pad,
                paddingStyle: .explicit, dataLayout: .NCHW
            )!
            pooled.append(graph.maxPooling2D(withSourceTensor: reduced, descriptor: descriptor, name: nil))
        }

        let concatenated = graph.concatTensors(pooled, dimension: 1, name: nil)
        return convModule(graph: graph, weights: weights, x: concatenated, exportName: "\(exportPrefix).conv2", stride: 1)
    }

    // MARK: - Backbone

    /// Returns [stem, stage1, stage2, stage3, stage4] for stage-by-stage
    /// bisection against the PyTorch reference.
    private static func buildBackboneStages(graph: MPSGraph, weights: RTMPoseWeights, input: MPSGraphTensor) -> [MPSGraphTensor]
    {
        var x = convModule(graph: graph, weights: weights, x: input, exportName: "backbone.stem0", stride: 2)
        x = convModule(graph: graph, weights: weights, x: x, exportName: "backbone.stem1", stride: 1)
        x = convModule(graph: graph, weights: weights, x: x, exportName: "backbone.stem2", stride: 1)

        var stageOutputs: [MPSGraphTensor] = [x]

        // P5 base block counts [3,6,6,3] * deepen_factor(0.67), rounded, min 1 —
        // matches export_weights.py's export_backbone exactly.
        let numBlocksPerStage = [2, 4, 4, 2]
        let hasSPP = [false, false, false, true]

        for stageIndex in 0..<4
        {
            let stagePrefix = "backbone.stage\(stageIndex + 1)"
            x = convModule(graph: graph, weights: weights, x: x, exportName: "\(stagePrefix).downsample", stride: 2)

            if hasSPP[stageIndex]
            {
                x = sppBottleneck(graph: graph, weights: weights, x: x, exportPrefix: "\(stagePrefix).spp")
            }

            x = cspLayer(graph: graph, weights: weights, x: x, exportPrefix: "\(stagePrefix).csp", numBlocks: numBlocksPerStage[stageIndex], addIdentity: stageIndex != 3)
            stageOutputs.append(x)
        }

        return stageOutputs // [stem, stage1, stage2, stage3, stage4]
    }

    // MARK: - Head

    /// ScaleNorm(x) = x / clamp(||x||_2 over last axis * dim^-0.5, min=eps) * g
    private static func scaleNorm(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportName: String, dim: Int, eps: Float = 1e-5) -> MPSGraphTensor
    {
        let g = weights.constant(graph, named: "\(exportName).g") // shape [1]
        let squared = graph.multiplication(x, x, name: nil)
        let sumSquared = graph.reductionSum(with: squared, axis: -1, name: nil)
        let norm = graph.squareRoot(with: sumSquared, name: nil)
        let scaleConstant = graph.constant(Double(pow(Float(dim), -0.5)), dataType: .float32)
        let scaledNorm = graph.multiplication(norm, scaleConstant, name: nil)
        let epsConstant = graph.constant(Double(eps), dataType: .float32)
        let clamped = graph.maximum(scaledNorm, epsConstant, name: nil)
        return graph.multiplication(graph.division(x, clamped, name: nil), g, name: nil)
    }

    /// PyTorch Linear weight is [out, in]; transpose once at graph-build
    /// time (not per-frame) so matmul is x[...,in] @ weightT[in,out].
    private static func linearNoBias(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportName: String) -> MPSGraphTensor
    {
        let weight = weights.constant(graph, named: exportName)
        let weightT = graph.transposeTensor(weight, dimension: 0, withDimension: 1, name: nil)
        return graph.matrixMultiplication(primary: x, secondary: weightT, name: nil)
    }

    /// RTMCCBlock (GAU), self-attn, use_rel_bias=false, pos_enc=false.
    /// num_token=21 (K), in/out_token_dims=256, hidden(e)=512, s=128.
    private static func gau(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor) -> MPSGraphTensor
    {
        let e = 512
        let s = 128
        let sqrtS = Float(s).squareRoot()

        let normed = scaleNorm(graph: graph, weights: weights, x: x, exportName: "head.gau_ln", dim: 256)
        var uv = linearNoBias(graph: graph, weights: weights, x: normed, exportName: "head.gau_uv.weight")
        uv = silu(graph: graph, x: uv) // [B,K,1152]

        let u = graph.sliceTensor(uv, dimension: 2, start: 0, length: e, name: nil)
        let v = graph.sliceTensor(uv, dimension: 2, start: e, length: e, name: nil)
        let base = graph.sliceTensor(uv, dimension: 2, start: 2 * e, length: s, name: nil) // [B,K,128]

        let baseExpanded = graph.expandDims(base, axis: 2, name: nil) // [B,K,1,128]
        let gamma = weights.constant(graph, named: "head.gau_gamma") // [2,128]
        let beta = weights.constant(graph, named: "head.gau_beta") // [2,128]
        let gammaBroadcast = graph.reshape(gamma, shape: [1, 1, 2, 128], name: nil)
        let betaBroadcast = graph.reshape(beta, shape: [1, 1, 2, 128], name: nil)
        let baseScaled = graph.addition(graph.multiplication(baseExpanded, gammaBroadcast, name: nil), betaBroadcast, name: nil) // [B,K,2,128]

        let q = graph.sliceTensor(baseScaled, dimension: 2, start: 0, length: 1, name: nil) // [B,K,1,128]
        let k = graph.sliceTensor(baseScaled, dimension: 2, start: 1, length: 1, name: nil)
        let qSqueezed = graph.squeeze(q, axis: 2, name: nil) // [B,K,128]
        let kSqueezed = graph.squeeze(k, axis: 2, name: nil)

        let kTransposed = graph.transposeTensor(kSqueezed, dimension: 1, withDimension: 2, name: nil) // [B,128,K]
        var qk = graph.matrixMultiplication(primary: qSqueezed, secondary: kTransposed, name: nil) // [B,K,K]
        qk = graph.division(qk, graph.constant(Double(sqrtS), dataType: .float32), name: nil)
        qk = graph.reLU(with: qk, name: nil)
        let kernel = graph.multiplication(qk, qk, name: nil) // square(relu(.))

        let attended = graph.matrixMultiplication(primary: kernel, secondary: v, name: nil) // [B,K,512]
        let gated = graph.multiplication(u, attended, name: nil)
        let projected = linearNoBias(graph: graph, weights: weights, x: gated, exportName: "head.gau_o.weight") // [B,K,256]

        let resScale = weights.constant(graph, named: "head.gau_res_scale") // [256]
        let scaledShortcut = graph.multiplication(x, resScale, name: nil)
        return graph.addition(scaledShortcut, projected, name: nil)
    }

    private static func buildHead(graph: MPSGraph, weights: RTMPoseWeights, features: MPSGraphTensor) -> (simccX: MPSGraphTensor, simccY: MPSGraphTensor)
    {
        // final_layer: Conv2d(768, 21, kernel=7, pad=3), WITH bias, no BN/act.
        let finalWeight = weights.constant(graph, named: "head.final_layer.weight")
        let finalBias = weights.constant(graph, named: "head.final_layer.bias")
        let finalDescriptor = MPSGraphConvolution2DOpDescriptor(
            strideInX: 1, strideInY: 1, dilationRateInX: 1, dilationRateInY: 1, groups: 1,
            paddingLeft: 3, paddingRight: 3, paddingTop: 3, paddingBottom: 3,
            paddingStyle: .explicit, dataLayout: .NCHW, weightsLayout: .OIHW
        )!
        var featureMap = graph.convolution2D(features, weights: finalWeight, descriptor: finalDescriptor, name: nil) // [1,21,8,8]
        featureMap = graph.addition(featureMap, graph.reshape(finalBias, shape: [1, NSNumber(value: Self.keypointCount), 1, 1], name: nil), name: nil)

        // flatten(2): [1,21,8,8] -> [1,21,64]
        let flattened = graph.reshape(featureMap, shape: [1, NSNumber(value: Self.keypointCount), 64], name: nil)

        let normed = scaleNorm(graph: graph, weights: weights, x: flattened, exportName: "head.mlp_scalenorm", dim: 64)
        let hidden = linearNoBias(graph: graph, weights: weights, x: normed, exportName: "head.mlp_linear.weight") // [1,21,256]

        let gauOutput = gau(graph: graph, weights: weights, x: hidden) // [1,21,256]

        let simccX = linearNoBias(graph: graph, weights: weights, x: gauOutput, exportName: "head.cls_x.weight") // [1,21,512]
        let simccY = linearNoBias(graph: graph, weights: weights, x: gauOutput, exportName: "head.cls_y.weight")
        return (simccX, simccY)
    }
}
