//
//  DepthCalibrationNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Calibrates an affine-invariant relative depth image (e.g. Zip Depth's
/// output) into Satin's reverse-Z scene depth, using a handful of
/// image-space points with known metric depth as calibration anchors.
///
/// Monocular relative-depth models are only correct up to an unknown global
/// scale and shift per image: metricDepth = scale * relativeDepth + offset.
/// Given calibration points (e.g. face landmarks with a known world-space Z),
/// this node solves that affine fit by least squares and remaps every texel
/// through it, then through Satin's own reverse-Z projection formula --
/// derived from `perspectiveMatrixf` in SatinCore/Transforms.mm, not a
/// generic textbook formula, so it matches what Satin's rasterizer actually
/// produces at the same near/far for real geometry.
public final class DepthCalibrationNode: Node
{
    override public class var name: String { "Depth Calibration" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String {
        "Calibrates affine-invariant relative depth (e.g. Zip Depth) into Satin's reverse-Z scene depth, using image-space points with known metric depth as calibration anchors."
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputRelativeDepth", NodePort<FabricImage>(
                name: "Relative Depth",
                kind: .Inlet,
                description: "Single-channel Float32 affine-invariant relative depth, e.g. from Zip Depth"
            )),
            ("inputImagePoints", NodePort<ContiguousArray<simd_float2>>(
                name: "Image Points",
                kind: .Inlet,
                description: "Calibration points in unit coordinates, matching the image the relative depth was estimated from"
            )),
            ("inputKnownDepths", NodePort<ContiguousArray<Float>>(
                name: "Known Depths",
                kind: .Inlet,
                description: "Known metric depth at each calibration point, matched to Image Points by index"
            )),
            ("inputNear", ParameterPort(parameter: FloatParameter(
                "Near", 0.01, 0.001, 1000.0, .slider, "Near clipping distance, matching the camera that will render occluded geometry"
            ))),
            ("inputFar", ParameterPort(parameter: FloatParameter(
                "Far", 100.0, 0.001, 1000.0, .slider, "Far clipping distance, matching the camera that will render occluded geometry"
            ))),
            ("outputSceneDepth", NodePort<FabricImage>(
                name: "Scene Depth",
                kind: .Outlet,
                description: "Reverse-Z NDC depth for the given near/far, single-channel Float32"
            )),
        ]
    }

    public var inputRelativeDepth: NodePort<FabricImage> { port(named: "inputRelativeDepth") }
    public var inputImagePoints: NodePort<ContiguousArray<simd_float2>> { port(named: "inputImagePoints") }
    public var inputKnownDepths: NodePort<ContiguousArray<Float>> { port(named: "inputKnownDepths") }
    public var inputNear: ParameterPort<Float> { port(named: "inputNear") }
    public var inputFar: ParameterPort<Float> { port(named: "inputFar") }
    public var outputSceneDepth: NodePort<FabricImage> { port(named: "outputSceneDepth") }

    private var samplePipeline: MTLComputePipelineState?
    private var remapPipeline: MTLComputePipelineState?

    // Mirrors DepthCalibrationRemapUniforms in DepthCalibration.metal exactly.
    private struct RemapUniforms
    {
        var scale: Float
        var offset: Float
        var near: Float
        var far: Float
    }

    // Written from a command buffer completion handler (an arbitrary Metal
    // callback thread), read from execute() (the graph render thread) --
    // genuinely concurrent, not just theoretically.
    private let calibrationLock = NSLock()
    private var calibrationScale: Float = 1.0
    private var calibrationOffset: Float = 0.0

    public required init(context: Context)
    {
        super.init(context: context)
        self.setupComputePipelines()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        self.setupComputePipelines()
    }

    private func setupComputePipelines()
    {
        let device = self.context.device
        guard
            let shaderURL = Bundle.module.url(
                forResource: "DepthCalibration",
                withExtension: "metal",
                subdirectory: "Compute/DepthCalibration"
            ),
            let source = try? String(contentsOf: shaderURL, encoding: .utf8),
            let library = try? device.makeLibrary(source: source, options: nil)
        else
        {
            // Without this, a missing resource or shader compile failure
            // leaves both pipelines nil and execute() throws "unavailable"
            // every frame with no clue why -- indistinguishable from a
            // build/packaging mistake unless it's logged here.
            print("Depth Calibration: could not load or compile DepthCalibration.metal")
            return
        }

        func pipeline(_ name: String) -> MTLComputePipelineState?
        {
            guard let function = library.makeFunction(name: name) else
            {
                print("Depth Calibration: missing Metal function \(name)")
                return nil
            }
            return try? device.makeComputePipelineState(function: function)
        }

        self.samplePipeline = pipeline("depthCalibrationSampleRelativeDepth")
        self.remapPipeline = pipeline("depthCalibrationRemapToSceneDepth")
    }

    override public func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        guard
            self.inputRelativeDepth.valueDidChange
                || self.inputImagePoints.valueDidChange
                || self.inputKnownDepths.valueDidChange
                || self.inputNear.valueDidChange
                || self.inputFar.valueDidChange
                || self.isDirty
        else { return }

        guard let relativeDepthImage = self.inputRelativeDepth.value else
        {
            self.outputSceneDepth.send(nil)
            return
        }
        guard let samplePipeline, let remapPipeline else
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Depth Calibration compute kernels are unavailable"
            )
        }

        let width = relativeDepthImage.texture.width
        let height = relativeDepthImage.texture.height
        let near = self.inputNear.value ?? 0.01
        let far = max(self.inputFar.value ?? 100.0, near + 0.001)

        let outputImage = try renderer.newImage(withWidth: width, height: height, format: .r32Float)
        outputImage.texture.label = "Depth Calibration Scene Depth"

        commandBuffer.pushDebugGroup("Depth Calibration \(width)×\(height)")
        defer { commandBuffer.popDebugGroup() }

        self.calibrationLock.lock()
        var uniforms = RemapUniforms(
            scale: self.calibrationScale,
            offset: self.calibrationOffset,
            near: near,
            far: far
        )
        self.calibrationLock.unlock()

        guard let remapEncoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Could not create the Depth Calibration remap encoder"
            )
        }
        remapEncoder.label = "Depth Calibration Remap"
        remapEncoder.setComputePipelineState(remapPipeline)
        remapEncoder.setTexture(relativeDepthImage.texture, index: 0)
        remapEncoder.setTexture(outputImage.texture, index: 1)
        remapEncoder.setBytes(&uniforms, length: MemoryLayout<RemapUniforms>.stride, index: 0)
        remapEncoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        remapEncoder.endEncoding()

        // This frame's calibration points are sampled and fit on the CPU
        // asynchronously, updating calibrationScale/calibrationOffset for a
        // LATER frame's remap above -- not this one. Reading the sampled
        // buffer back now would mean waiting on this frame's own GPU work,
        // exactly the stall Zip Depth (this node's usual upstream source)
        // spent a long session eliminating. One frame of latency on the
        // calibration coefficients is not visible for anchoring occlusion
        // depth to a handful of landmark points.
        self.encodeCalibrationSampling(
            samplePipeline: samplePipeline,
            relativeDepthTexture: relativeDepthImage.texture,
            presentationWidth: width,
            presentationHeight: height,
            commandBuffer: commandBuffer
        )

        // `commandBuffer` is Fabric's shared per-frame buffer -- this node
        // never waits on it, so it's still in flight when execute() returns.
        // GraphRendererTextureCache recycles a managed FabricImage's texture
        // the instant its last Swift reference drops, with no regard for
        // whether the GPU is still using it. Keep both alive until this
        // buffer's GPU work actually completes.
        commandBuffer.addCompletedHandler { [inputImage = relativeDepthImage, outputImage] _ in
            withExtendedLifetime((inputImage, outputImage)) {}
        }

        self.outputSceneDepth.send(outputImage)
    }

    private func encodeCalibrationSampling(
        samplePipeline: MTLComputePipelineState,
        relativeDepthTexture: MTLTexture,
        presentationWidth: Int,
        presentationHeight: Int,
        commandBuffer: MTLCommandBuffer
    )
    {
        let imagePoints = self.inputImagePoints.value ?? []
        let knownDepths = self.inputKnownDepths.value ?? []
        let pointCount = min(imagePoints.count, knownDepths.count)
        guard pointCount > 0 else { return }

        // Inverts FacePoseAnalysisNode / HandPoseAnalysisNode's unit-coordinate
        // convention (x in -1...1, y in -aspect...aspect, aspect = height/width)
        // so points from those nodes land on the correct texel.
        let width = Float(presentationWidth)
        let height = Float(presentationHeight)
        let aspect = height / width
        var pixelPoints = [simd_float2](repeating: .zero, count: pointCount)
        for index in 0 ..< pointCount
        {
            let unitPoint = imagePoints[index]
            pixelPoints[index] = simd_float2(
                remap(unitPoint.x, -1.0, 1.0, 0.0, width),
                remap(unitPoint.y, -aspect, aspect, 0.0, height)
            )
        }
        let knownDepthValues = Array(knownDepths.prefix(pointCount))

        guard
            let pixelPointsBuffer = self.context.device.makeBuffer(
                bytes: pixelPoints,
                length: pointCount * MemoryLayout<simd_float2>.stride
            ),
            let sampledValuesBuffer = self.context.device.makeBuffer(
                length: pointCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ),
            let sampleEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return }

        sampleEncoder.label = "Depth Calibration Sample"
        sampleEncoder.setComputePipelineState(samplePipeline)
        sampleEncoder.setTexture(relativeDepthTexture, index: 0)
        sampleEncoder.setBuffer(pixelPointsBuffer, offset: 0, index: 0)
        sampleEncoder.setBuffer(sampledValuesBuffer, offset: 0, index: 1)
        sampleEncoder.dispatchThreads(
            MTLSize(width: pointCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(pointCount, samplePipeline.threadExecutionWidth),
                height: 1,
                depth: 1
            )
        )
        sampleEncoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            let sampledRelativeDepths = Array(UnsafeBufferPointer(
                start: sampledValuesBuffer.contents().assumingMemoryBound(to: Float.self),
                count: pointCount
            ))
            self?.updateCalibration(relativeDepths: sampledRelativeDepths, knownDepths: knownDepthValues)
        }
    }

    // Closed-form 1D least squares for metricDepth = scale * relativeDepth +
    // offset. A single point can't solve two unknowns, so scale is fixed at
    // 1 (pure shift) in that case.
    private func updateCalibration(relativeDepths: [Float], knownDepths: [Float])
    {
        guard relativeDepths.count == knownDepths.count, relativeDepths.isEmpty == false else { return }

        let count = Float(relativeDepths.count)
        let meanRelative = relativeDepths.reduce(0, +) / count
        let meanKnown = knownDepths.reduce(0, +) / count

        let scale: Float
        if relativeDepths.count < 2
        {
            scale = 1.0
        }
        else
        {
            var covariance: Float = 0
            var variance: Float = 0
            for index in 0 ..< relativeDepths.count
            {
                let relativeDelta = relativeDepths[index] - meanRelative
                covariance += relativeDelta * (knownDepths[index] - meanKnown)
                variance += relativeDelta * relativeDelta
            }
            scale = variance > 1e-6 ? covariance / variance : 1.0
        }
        let offset = meanKnown - scale * meanRelative

        self.calibrationLock.lock()
        self.calibrationScale = scale
        self.calibrationOffset = offset
        self.calibrationLock.unlock()
    }
}
