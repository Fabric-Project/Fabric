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
import Metal
import MetalPerformanceShadersGraph
import simd

final class RTMPoseMPSGraph
{
    private let graph = MPSGraph()
    private let weights: RTMPoseWeights
    private let device: MPSGraphDevice
    private let commandQueue: MTLCommandQueue
    private let inputPreprocessor: RTMPoseInputPreprocessor

    private let inputTensor: MPSGraphTensor
    /// [stem, stage1, stage2, stage3, stage4] — exposed for bisecting a
    /// mismatch against the PyTorch reference stage-by-stage. Only used by
    /// the debug/validation entry points below, not the hot path.
    private let backboneStageTensors: [MPSGraphTensor]
    private let backboneOutputTensor: MPSGraphTensor
    private let simccXTensor: MPSGraphTensor
    private let simccYTensor: MPSGraphTensor
    private let inferenceStateLock = NSLock()
    private var inferenceIsInFlight = false

    /// Compiled once at init — MPSGraph.run(feeds:targetTensors:) is a
    /// convenience method that re-validates/optimizes the graph on every
    /// call (measured ~65ms/call here, dominating the whole budget). The
    /// compiled MPSGraphExecutable skips that per-call cost; only this is
    /// used by the hot path (run(image:regionOfInterest:)).
    private let executable: MPSGraphExecutable

    private static let keypointCount = 21
    private static let inputSize = 256 // square input, matches Hand5's 256x256

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

        let input = self.graph.placeholder(
            shape: [1, 3, NSNumber(value: Self.inputSize), NSNumber(value: Self.inputSize)],
            dataType: .float32,
            name: "input"
        )
        self.inputTensor = input

        let stageTensors = CSPNeXtMPSGraph.buildBackboneStages(graph: self.graph, weights: self.weights, input: input, deepenFactor: 0.67)
        self.backboneStageTensors = stageTensors
        let backboneOutput = stageTensors.last!
        self.backboneOutputTensor = backboneOutput
        let (simccX, simccY) = Self.buildHead(graph: self.graph, weights: self.weights, features: backboneOutput)
        self.simccXTensor = simccX
        self.simccYTensor = simccY

        let inputType = MPSGraphShapedType(shape: input.shape!, dataType: .float32)
        let feedShapes: [MPSGraphTensor: MPSGraphShapedType] = [input: inputType]
        let compilationDescriptor = Self.performanceCompilationDescriptor()
        self.executable = self.graph.compile(
            with: self.device,
            feeds: feedShapes,
            targetTensors: [simccX, simccY],
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

        // Level 1 performs the placement and additional optimization passes.
        // The old `.performance` optimization profile is both the default and
        // deprecated on every OS version Fabric supports.
        descriptor.optimizationLevel = .level1
        descriptor.waitForCompilationCompletion = true

        // Apple currently exposes reduced precision only on OS 26+. It allows
        // selected multi-pass GPU intermediates (currently Conv2D Winograd)
        // to use FP16 while the graph inputs, weights, and outputs stay FP32.
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
        {
            descriptor.reducedPrecisionFastMath = .allowFP16Intermediates
        }

        return descriptor
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

    /// Crop/scale/normalize and inference are submitted to the same queue.
    /// The input stays GPU-resident from FabricImage through the first graph op.
    func run(image: FabricImage,
             regionOfInterest: simd_float4) throws -> (simccX: [Float], simccY: [Float])
    {
        let normalizedInput = try self.inputPreprocessor.encode(
            image: image,
            regionOfInterest: regionOfInterest,
            commandQueue: self.commandQueue
        )
        let inputData = MPSGraphTensorData(
            normalizedInput,
            shape: self.inputTensor.shape!,
            dataType: .float32
        )

        let results = self.executable.run(with: self.commandQueue, inputs: [inputData], results: nil, executionDescriptor: nil)

        let simccX = Self.floatArray(from: results[0])
        let simccY = Self.floatArray(from: results[1])
        return (simccX, simccY)
    }

    /// Submits preprocessing and inference without waiting for GPU completion.
    /// Returns false when an inference is already in flight so callers can
    /// drop the newer frame instead of accumulating latency in the GPU queue.
    @discardableResult
    func submit(image: FabricImage,
                regionOfInterest: simd_float4,
                completion: @escaping (Result<(simccX: [Float], simccY: [Float]), any Error>) -> Void) throws -> Bool
    {
        guard self.beginInference() else { return false }

        do
        {
            guard let commandBuffer = self.commandQueue.makeCommandBuffer() else
            {
                throw FabricError(
                    .execution(.gpu),
                    severity: .recoverable,
                    message: "Could not create asynchronous RTMPose command buffer"
                )
            }

            let normalizedInput = try self.inputPreprocessor.encode(
                image: image,
                regionOfInterest: regionOfInterest,
                commandBuffer: commandBuffer
            )
            let inputData = MPSGraphTensorData(
                normalizedInput,
                shape: self.inputTensor.shape!,
                dataType: .float32
            )

            let executionDescriptor = MPSGraphExecutableExecutionDescriptor()
            executionDescriptor.waitUntilCompleted = false
            executionDescriptor.completionHandler = { [weak self] results, error in
                guard let self else { return }

                let inferenceResult: Result<(simccX: [Float], simccY: [Float]), any Error>
                if let error
                {
                    inferenceResult = .failure(error)
                }
                else if results.count >= 2
                {
                    inferenceResult = .success((
                        simccX: Self.floatArray(from: results[0]),
                        simccY: Self.floatArray(from: results[1])
                    ))
                }
                else
                {
                    inferenceResult = .failure(FabricError(
                        .execution(.gpu),
                        severity: .recoverable,
                        message: "Asynchronous RTMPose inference returned incomplete outputs"
                    ))
                }

                self.finishInference()
                completion(inferenceResult)
            }

            let mpsCommandBuffer = MPSCommandBuffer(commandBuffer: commandBuffer)
            _ = self.executable.encode(
                to: mpsCommandBuffer,
                inputs: [inputData],
                results: nil,
                executionDescriptor: executionDescriptor
            )
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

    // MARK: - Head
    //
    // Shared CSPNeXt backbone building blocks (convModule, cspNeXtBlock,
    // channelAttention, cspLayer, sppBottleneck, buildBackboneStages) moved
    // to CSPNeXtMPSGraph.swift, since RTMDetMPSGraph's backbone reuses them
    // verbatim — CSPNeXt is RTMPose's and RTMDet's shared backbone.

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
        uv = CSPNeXtMPSGraph.silu(graph: graph, x: uv) // [B,K,1152]

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
