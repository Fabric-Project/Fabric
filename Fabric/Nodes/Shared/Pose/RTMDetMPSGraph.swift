// RTMDetMPSGraph.swift
//
// From-scratch MPSGraph reimplementation of RTMDet-nano (CSPNeXt backbone +
// CSPNeXtPAFPN neck + RTMDetSepBNHead), built once from exported weights and
// run per-frame on GPU via Metal Performance Shaders Graph — no CoreML.
// Serves both the person and hand detectors: same architecture, different
// weight files (RTMModelCache's old CoreML-backed detector path is retired
// in favor of this).
//
// Architecture confirmed against the actual mmdetection/mmengine source
// installed in the rtmpose-convert conda env (not assumed from memory —
// CSPDarknet/CSPNeXt share a source file and are easy to confuse), and
// export_weights.py's exhaustive key-consumption check passed (246/246
// tensors accounted for) for both the person and hand checkpoints.
//
// Layout convention: NCHW throughout (matches PyTorch's OIHW conv weight
// layout directly, no transposes needed).

import Foundation
import Metal
import MetalPerformanceShadersGraph
import simd

final class RTMDetMPSGraph
{
    private let graph = MPSGraph()
    private let weights: RTMPoseWeights
    private let device: MPSGraphDevice
    private let commandQueue: MTLCommandQueue
    private let inputPreprocessor: RTMPoseInputPreprocessor

    private let inputTensor: MPSGraphTensor
    private let inferenceStateLock = NSLock()
    private var inferenceIsInFlight = false

    /// Compiled once at init, for the same reason as RTMPoseMPSGraph:
    /// MPSGraph.run(feeds:targetTensors:) re-validates/optimizes on every
    /// call. Target order is [scores0,scores1,scores2,boxes0,boxes1,boxes2]
    /// — RTMDetDecoder-facing code depends on this order matching level
    /// index, since MPSGraphExecutable's results array has no names.
    private let executable: MPSGraphExecutable

    private static let inputSize = 320 // square input, matches both the person and hand nano configs
    /// Also referenced by RTMDetInference when decoding this model's output.
    static let strides = [8, 16, 32]

    /// Per-level (height, width) of the score/box-distance feature maps —
    /// `inputSize / stride` for each of `strides` — exposed so callers can
    /// reshape the raw per-level float arrays without recomputing this.
    let levelSizes: [(height: Int, width: Int)]

    init(weightsBinaryURL: URL, weightsManifestURL: URL, commandQueue: MTLCommandQueue) throws
    {
        self.weights = try RTMPoseWeights(binaryURL: weightsBinaryURL, manifestURL: weightsManifestURL)
        let metalDevice = commandQueue.device
        self.device = MPSGraphDevice(mtlDevice: metalDevice)
        self.commandQueue = commandQueue
        self.inputPreprocessor = try RTMPoseInputPreprocessor(
            device: metalDevice,
            outputWidth: Self.inputSize,
            outputHeight: Self.inputSize
        )
        self.levelSizes = Self.strides.map { (Self.inputSize / $0, Self.inputSize / $0) }

        let input = self.graph.placeholder(
            shape: [1, 3, NSNumber(value: Self.inputSize), NSNumber(value: Self.inputSize)],
            dataType: .float32,
            name: "input"
        )
        self.inputTensor = input

        // RTMDet-nano: deepen_factor=0.33, backbone.use_depthwise=true.
        // out_indices=(2,3,4) default — stage2/3/4 feed the neck as P3/P4/P5.
        let backboneStages = CSPNeXtMPSGraph.buildBackboneStages(graph: self.graph, weights: self.weights, input: input, deepenFactor: 0.33, useDepthwise: true)
        let neckInputs = Array(backboneStages[2...4])
        let neckOutputs = Self.buildNeck(graph: self.graph, weights: self.weights, backboneOutputs: neckInputs, numCSPBlocks: 1)
        let (scores, boxDistances) = Self.buildHead(graph: self.graph, weights: self.weights, neckOutputs: neckOutputs, stackedConvs: 2, strides: Self.strides)

        let targetTensors = scores + boxDistances

        let inputType = MPSGraphShapedType(shape: input.shape!, dataType: .float32)
        let feedShapes: [MPSGraphTensor: MPSGraphShapedType] = [input: inputType]
        let compilationDescriptor = Self.performanceCompilationDescriptor()
        self.executable = self.graph.compile(
            with: self.device,
            feeds: feedShapes,
            targetTensors: targetTensors,
            targetOperations: nil,
            compilationDescriptor: compilationDescriptor
        )
        self.executable.specialize(
            with: self.device,
            inputTypes: [inputType],
            compilationDescriptor: compilationDescriptor
        )
    }

    private static func performanceCompilationDescriptor() -> MPSGraphCompilationDescriptor
    {
        let descriptor = MPSGraphCompilationDescriptor()
        descriptor.optimizationLevel = .level1
        descriptor.waitForCompilationCompletion = true
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
        {
            descriptor.reducedPrecisionFastMath = .allowFP16Intermediates
        }
        return descriptor
    }

    /// Crop/scale/normalize and inference are submitted to the same queue.
    /// Returns 3 score arrays and 3 box-distance arrays, in level order
    /// (index 0 = stride 8, the largest feature map). Scores are already
    /// sigmoid-probabilities and box distances are already absolute pixel
    /// units (both baked into the graph in buildHead) — RTMDetDecoder does
    /// not need to know this is an MPSGraph result rather than a CoreML one.
    func run(image: FabricImage, regionOfInterest: simd_float4) throws -> (scores: [[Float]], boxDistances: [[Float]])
    {
        let normalizedInput = try self.inputPreprocessor.encode(
            image: image,
            regionOfInterest: regionOfInterest,
            commandQueue: self.commandQueue
        )
        let inputData = MPSGraphTensorData(normalizedInput, shape: self.inputTensor.shape!, dataType: .float32)

        let results = self.executable.run(with: self.commandQueue, inputs: [inputData], results: nil, executionDescriptor: nil)

        let levelCount = Self.strides.count
        let scores = (0..<levelCount).map { Self.floatArray(from: results[$0]) }
        let boxDistances = (levelCount..<(2 * levelCount)).map { Self.floatArray(from: results[$0]) }
        return (scores, boxDistances)
    }

    /// Async counterpart of run(), matching RTMPoseMPSGraph.submit()'s
    /// contract exactly: encodes onto one command buffer without waiting,
    /// drops the call (returns false, never invokes `completion`) if an
    /// inference is already in flight.
    @discardableResult
    func submit(image: FabricImage, regionOfInterest: simd_float4, completion: @escaping (Result<(scores: [[Float]], boxDistances: [[Float]]), any Error>) -> Void) throws -> Bool
    {
        guard self.beginInference() else { return false }

        do
        {
            guard let commandBuffer = self.commandQueue.makeCommandBuffer() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create asynchronous RTMDet command buffer")
            }

            let normalizedInput = try self.inputPreprocessor.encode(image: image, regionOfInterest: regionOfInterest, commandBuffer: commandBuffer)
            let inputData = MPSGraphTensorData(normalizedInput, shape: self.inputTensor.shape!, dataType: .float32)

            let levelCount = Self.strides.count
            let executionDescriptor = MPSGraphExecutableExecutionDescriptor()
            executionDescriptor.waitUntilCompleted = false
            executionDescriptor.completionHandler = { [weak self] results, error in
                guard let self else { return }

                let inferenceResult: Result<(scores: [[Float]], boxDistances: [[Float]]), any Error>
                if let error
                {
                    inferenceResult = .failure(error)
                }
                else if results.count >= 2 * levelCount
                {
                    let scores = (0..<levelCount).map { Self.floatArray(from: results[$0]) }
                    let boxDistances = (levelCount..<(2 * levelCount)).map { Self.floatArray(from: results[$0]) }
                    inferenceResult = .success((scores: scores, boxDistances: boxDistances))
                }
                else
                {
                    inferenceResult = .failure(FabricError(.execution(.gpu), severity: .recoverable, message: "Asynchronous RTMDet inference returned incomplete outputs"))
                }

                self.finishInference()
                completion(inferenceResult)
            }

            let mpsCommandBuffer = MPSCommandBuffer(commandBuffer: commandBuffer)
            _ = self.executable.encode(to: mpsCommandBuffer, inputs: [inputData], results: nil, executionDescriptor: executionDescriptor)
            mpsCommandBuffer.commit()
            return true
        }
        catch
        {
            self.finishInference()
            throw error
        }
    }

    private func beginInference() -> Bool
    {
        self.inferenceStateLock.lock()
        defer { self.inferenceStateLock.unlock() }

        guard self.inferenceIsInFlight == false else { return false }
        self.inferenceIsInFlight = true
        return true
    }

    private func finishInference()
    {
        self.inferenceStateLock.lock()
        self.inferenceIsInFlight = false
        self.inferenceStateLock.unlock()
    }

    private static func floatArray(from tensorData: MPSGraphTensorData) -> [Float]
    {
        let count = tensorData.shape.map(\.intValue).reduce(1, *)
        var values = [Float](repeating: 0, count: count)
        tensorData.mpsndarray().readBytes(&values, strideBytes: nil)
        return values
    }

    // MARK: - Neck (CSPNeXtPAFPN)

    /// Top-down (reduce + nearest-2x-upsample + concat + CSPLayer) then
    /// bottom-up (depthwise-separable downsample + concat + CSPLayer)
    /// fusion across the 3 backbone stage outputs (P3/P4/P5, strides
    /// 8/16/32), then a per-level depthwise-separable 3x3 conv to a
    /// uniform channel count. CSPLayers here have NO channel attention
    /// (CSPNeXtPAFPN never passes channel_attention=true, unlike the
    /// backbone) and num_csp_blocks is used as-is, not deepen-factor-scaled
    /// (confirmed against mmdetection's necks/cspnext_pafpn.py).
    private static func buildNeck(graph: MPSGraph, weights: RTMPoseWeights, backboneOutputs: [MPSGraphTensor], numCSPBlocks: Int) -> [MPSGraphTensor]
    {
        let levelCount = backboneOutputs.count

        var innerOutputs: [MPSGraphTensor] = [backboneOutputs[levelCount - 1]]
        for reduceIndex in 0..<(levelCount - 1)
        {
            let sourceLevel = levelCount - 1 - reduceIndex
            let reduced = CSPNeXtMPSGraph.convModule(graph: graph, weights: weights, x: innerOutputs[0], exportName: "neck.reduce_layers\(reduceIndex)", stride: 1)
            innerOutputs[0] = reduced

            let upsampled = Self.nearestUpsample2x(graph: graph, x: reduced)
            let featLow = backboneOutputs[sourceLevel - 1]
            let concatenated = graph.concatTensors([upsampled, featLow], dimension: 1, name: nil)
            let innerOut = CSPNeXtMPSGraph.cspLayer(
                graph: graph, weights: weights, x: concatenated, exportPrefix: "neck.top_down_blocks\(reduceIndex)",
                numBlocks: numCSPBlocks, addIdentity: false, hasChannelAttention: false, useDepthwise: true
            )
            innerOutputs.insert(innerOut, at: 0)
        }

        var outputs: [MPSGraphTensor] = [innerOutputs[0]]
        for idx in 0..<(levelCount - 1)
        {
            let featLow = outputs[outputs.count - 1]
            let featHigh = innerOutputs[idx + 1]
            let downsampled = CSPNeXtMPSGraph.depthwiseSeparableConvModule(graph: graph, weights: weights, x: featLow, exportName: "neck.downsamples\(idx)", stride: 2)
            let concatenated = graph.concatTensors([downsampled, featHigh], dimension: 1, name: nil)
            let out = CSPNeXtMPSGraph.cspLayer(
                graph: graph, weights: weights, x: concatenated, exportPrefix: "neck.bottom_up_blocks\(idx)",
                numBlocks: numCSPBlocks, addIdentity: false, hasChannelAttention: false, useDepthwise: true
            )
            outputs.append(out)
        }

        return outputs.enumerated().map { index, tensor in
            CSPNeXtMPSGraph.depthwiseSeparableConvModule(graph: graph, weights: weights, x: tensor, exportName: "neck.out_convs\(index)", stride: 1)
        }
    }

    /// nn.Upsample(scale_factor=2, mode='nearest'): each source pixel
    /// becomes a 2x2 block in the output. Implemented as reshape-broadcast-
    /// reshape rather than MPSGraph's resize op, to avoid depending on an
    /// exact resize-mode/alignment API this session couldn't verify against
    /// a live build — this construction's output ordering is unambiguous
    /// (h0,h0,h1,h1,... per axis) and needs no such verification.
    private static func nearestUpsample2x(graph: MPSGraph, x: MPSGraphTensor) -> MPSGraphTensor
    {
        let shape = x.shape!.map(\.intValue)
        let (batch, channels, height, width) = (shape[0], shape[1], shape[2], shape[3])

        let reshaped = graph.reshape(x, shape: [
            NSNumber(value: batch), NSNumber(value: channels),
            NSNumber(value: height), 1,
            NSNumber(value: width), 1,
        ], name: nil)
        let broadcasted = graph.broadcast(reshaped, shape: [
            NSNumber(value: batch), NSNumber(value: channels),
            NSNumber(value: height), 2,
            NSNumber(value: width), 2,
        ], name: nil)
        return graph.reshape(broadcasted, shape: [
            NSNumber(value: batch), NSNumber(value: channels),
            NSNumber(value: height * 2), NSNumber(value: width * 2),
        ], name: nil)
    }

    // MARK: - Head (RTMDetSepBNHead)

    /// share_conv=False → independent weights per FPN level (confirmed
    /// against both the person and hand configs — re-check share_conv
    /// before reusing this for a different checkpoint). Per level: a cls
    /// branch and a reg branch, each `stackedConvs` depthwise-separable 3x3
    /// convs, then a bare 1x1 conv (bias, no BN/activation — rtm_cls/
    /// rtm_reg are plain nn.Conv2d, not ConvModule) to (score, box
    /// distance). Sigmoid and the *stride multiply are baked in here since
    /// this is our own runtime with no separate Python decode step:
    /// RTMDetSepBNHead.forward() itself returns raw pre-sigmoid logits, and
    /// (with exp_on_reg=false, confirmed for both configs) box distances
    /// already *stride — mmdet's own predict_by_feat applies both at
    /// inference time, reproduced here instead.
    private static func buildHead(graph: MPSGraph, weights: RTMPoseWeights, neckOutputs: [MPSGraphTensor], stackedConvs: Int, strides: [Int]) -> (scores: [MPSGraphTensor], boxDistances: [MPSGraphTensor])
    {
        var scores: [MPSGraphTensor] = []
        var boxDistances: [MPSGraphTensor] = []

        for (levelIndex, feature) in neckOutputs.enumerated()
        {
            var clsFeat = feature
            for convIndex in 0..<stackedConvs
            {
                clsFeat = CSPNeXtMPSGraph.depthwiseSeparableConvModule(graph: graph, weights: weights, x: clsFeat, exportName: "head.cls_convs\(levelIndex)_\(convIndex)", stride: 1)
            }
            let clsScore = graph.sigmoid(
                with: CSPNeXtMPSGraph.convBNFolded(graph: graph, weights: weights, x: clsFeat, exportName: "head.rtm_cls\(levelIndex)", stride: 1),
                name: nil
            )
            scores.append(clsScore)

            var regFeat = feature
            for convIndex in 0..<stackedConvs
            {
                regFeat = CSPNeXtMPSGraph.depthwiseSeparableConvModule(graph: graph, weights: weights, x: regFeat, exportName: "head.reg_convs\(levelIndex)_\(convIndex)", stride: 1)
            }
            let rawBoxDistance = CSPNeXtMPSGraph.convBNFolded(graph: graph, weights: weights, x: regFeat, exportName: "head.rtm_reg\(levelIndex)", stride: 1)
            let strideConstant = graph.constant(Double(strides[levelIndex]), dataType: .float32)
            boxDistances.append(graph.multiplication(rawBoxDistance, strideConstant, name: nil))
        }

        return (scores, boxDistances)
    }
}
