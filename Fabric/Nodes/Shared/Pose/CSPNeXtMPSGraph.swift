// CSPNeXtMPSGraph.swift
//
// Shared MPSGraph building blocks for CSPNeXt — the backbone RTMPose and
// RTMDet both use (mmdetection's models/backbones/cspnext.py; confirmed
// distinct from the older CSPDarknet/YOLOX backbone that happens to live in
// the same source file, csp_darknet.py — easy to grep the wrong class) —
// plus mmcv's ConvModule/DepthwiseSeparableConvModule conventions in
// general. BatchNorm is folded into the preceding conv at export time
// (export_weights.py), so only plain/depthwise convs are needed here.
//
// Extracted from RTMPoseMPSGraph.swift (originally written and validated
// there to ~1e-5/2e-6 against the PyTorch reference for RTMPose-Hand) so
// RTMDetMPSGraph.swift's backbone doesn't duplicate it — CSPNeXtPAFPN's
// downsample/out convs and RTMDetSepBNHead's stacked convs also reuse the
// depthwise-separable ConvModule pattern first written here for
// CSPNeXtBlock.conv2.

import Foundation
import MetalPerformanceShadersGraph

enum CSPNeXtMPSGraph
{
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

    /// DepthwiseSeparableConvModule: depthwise NxN (stride, groups=channels)
    /// + pointwise 1x1, each its own ConvModule (BN-folded + SiLU). Stride
    /// applies to the depthwise stage only, matching mmcv's own layout —
    /// the pointwise stage only mixes channels. `exportName` is a prefix;
    /// the two stages are `\(exportName)_depthwise` / `\(exportName)_pointwise`
    /// (matching export_weights.py's export_cspnext_block naming).
    static func depthwiseSeparableConvModule(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportName: String, stride: Int) -> MPSGraphTensor
    {
        let depthwiseChannels = weights.shape(named: "\(exportName)_depthwise.weight")[0]
        var out = convModule(graph: graph, weights: weights, x: x, exportName: "\(exportName)_depthwise", stride: stride, groups: depthwiseChannels)
        out = convModule(graph: graph, weights: weights, x: out, exportName: "\(exportName)_pointwise", stride: 1)
        return out
    }

    /// CSPNeXtBlock: conv1 is a plain ConvModule if `useDepthwise` is false,
    /// else depthwise-separable (conditional on the SAME use_depthwise flag
    /// as the enclosing CSPLayer/backbone/neck — confirmed against
    /// mmdetection's layers/csp_layer.py CSPNeXtBlock.__init__). conv2 is
    /// depthwise-separable UNCONDITIONALLY — hardcoded in CSPNeXtBlock
    /// regardless of use_depthwise, confirmed same source. RTMPose's
    /// checkpoints have use_depthwise=false (the original, validated
    /// default here); RTMDet-nano has it true.
    static func cspNeXtBlock(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportPrefix: String, addIdentity: Bool, useDepthwise: Bool = false) -> MPSGraphTensor
    {
        let identity = x
        var out = useDepthwise
            ? depthwiseSeparableConvModule(graph: graph, weights: weights, x: x, exportName: "\(exportPrefix).conv1", stride: 1)
            : convModule(graph: graph, weights: weights, x: x, exportName: "\(exportPrefix).conv1", stride: 1)
        out = depthwiseSeparableConvModule(graph: graph, weights: weights, x: out, exportName: "\(exportPrefix).conv2", stride: 1)

        if addIdentity
        {
            out = graph.addition(out, identity, name: nil)
        }
        return out
    }

    /// PyTorch nn.Hardsigmoid: clamp(x/6 + 0.5, 0, 1) — NOT the same as
    /// plain sigmoid. Confirmed from mmdetection's se_layer.py ChannelAttention,
    /// which uses nn.Hardsigmoid() specifically, not Sigmoid.
    static func hardSigmoid(graph: MPSGraph, x: MPSGraphTensor) -> MPSGraphTensor
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
    /// main_conv/short_conv/final_conv are always plain ConvModules, never
    /// depthwise, regardless of use_depthwise — confirmed against
    /// mmdetection's layers/csp_layer.py: that flag only reaches the
    /// block(...) constructor, not these three.
    static func cspLayer(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportPrefix: String, numBlocks: Int, addIdentity: Bool, hasChannelAttention: Bool = true, useDepthwise: Bool = false) -> MPSGraphTensor
    {
        var main = convModule(graph: graph, weights: weights, x: x, exportName: "\(exportPrefix).main_conv", stride: 1)
        let short = convModule(graph: graph, weights: weights, x: x, exportName: "\(exportPrefix).short_conv", stride: 1)

        for blockIndex in 0..<numBlocks
        {
            main = cspNeXtBlock(graph: graph, weights: weights, x: main, exportPrefix: "\(exportPrefix).block\(blockIndex)", addIdentity: addIdentity, useDepthwise: useDepthwise)
        }

        var combined = graph.concatTensors([main, short], dimension: 1, name: nil)
        if hasChannelAttention
        {
            combined = channelAttention(graph: graph, weights: weights, x: combined, exportPrefix: "\(exportPrefix).attention")
        }
        return convModule(graph: graph, weights: weights, x: combined, exportName: "\(exportPrefix).final_conv", stride: 1)
    }

    /// SPPBottleneck: 1x1 conv -> three parallel "same"-padded max pools
    /// (kernels 5,9,13) -> concat with the pre-pool feature -> 1x1 conv.
    static func sppBottleneck(graph: MPSGraph, weights: RTMPoseWeights, x: MPSGraphTensor, exportPrefix: String) -> MPSGraphTensor
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

    /// Returns [stem, stage1, stage2, stage3, stage4] — CSPNeXt.arch_settings
    /// ['P5']'s base block counts before deepen_factor scaling are always
    /// [3,6,6,3] (confirmed against mmdetection's backbones/cspnext.py;
    /// widen_factor only affects channel counts, which are read from weight
    /// shapes and need no parameter here). Stages are 1-indexed in export
    /// names (backbone.stage1..stage4) to match export_weights.py.
    /// `useDepthwise` (CSPNeXt.__init__'s own flag — false for RTMPose's
    /// checkpoints, true for RTMDet-nano) makes the per-stage downsample
    /// conv depthwise-separable instead of plain, and cascades into each
    /// stage's CSPLayer (its blocks' conv1, specifically — conv2 is always
    /// depthwise). The stem is unaffected either way — CSPNeXt.__init__
    /// builds it from three explicit ConvModule calls regardless.
    static func buildBackboneStages(graph: MPSGraph, weights: RTMPoseWeights, input: MPSGraphTensor, deepenFactor: Float, useDepthwise: Bool = false) -> [MPSGraphTensor]
    {
        var x = convModule(graph: graph, weights: weights, x: input, exportName: "backbone.stem0", stride: 2)
        x = convModule(graph: graph, weights: weights, x: x, exportName: "backbone.stem1", stride: 1)
        x = convModule(graph: graph, weights: weights, x: x, exportName: "backbone.stem2", stride: 1)

        var stageOutputs: [MPSGraphTensor] = [x]

        let baseBlocksP5: [Float] = [3, 6, 6, 3]
        let numBlocksPerStage = baseBlocksP5.map { max(Int(($0 * deepenFactor).rounded()), 1) }
        let hasSPP = [false, false, false, true]

        for stageIndex in 0..<4
        {
            let stagePrefix = "backbone.stage\(stageIndex + 1)"
            x = useDepthwise
                ? depthwiseSeparableConvModule(graph: graph, weights: weights, x: x, exportName: "\(stagePrefix).downsample", stride: 2)
                : convModule(graph: graph, weights: weights, x: x, exportName: "\(stagePrefix).downsample", stride: 2)

            if hasSPP[stageIndex]
            {
                x = sppBottleneck(graph: graph, weights: weights, x: x, exportPrefix: "\(stagePrefix).spp")
            }

            x = cspLayer(graph: graph, weights: weights, x: x, exportPrefix: "\(stagePrefix).csp", numBlocks: numBlocksPerStage[stageIndex], addIdentity: stageIndex != 3, useDepthwise: useDepthwise)
            stageOutputs.append(x)
        }

        return stageOutputs // [stem, stage1, stage2, stage3, stage4]
    }
}
