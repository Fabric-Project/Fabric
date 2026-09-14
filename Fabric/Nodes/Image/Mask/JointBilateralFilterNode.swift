//
//  JointBilateralFilterNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Edge-aware smoothing of one image (the "signal") guided by another (the
/// "guide") -- MediaPipe's own documented fix for the soft, blurry edges a
/// low-resolution segmentation mask gets from plain bilinear upsampling
/// ("consider applying a joint bilateral filter to the segmentation mask
/// with the image"), but a generic primitive: works on any {signal, guide}
/// pair, not segmentation-specific, so it's built standalone rather than
/// folded into MediaPipe Selfie Segmentation. See
/// Fabric/Compute/Mask/JointBilateralFilter.metal for the actual algorithm.
///
/// Structural pattern mirrors LucasKanadeOpticalFlowNode (plain Node
/// subclass, own compute pipeline loaded in init, direct dispatch against
/// the shared per-frame command buffer) -- BaseEffectTwoChannelNode exists
/// but lives in Fabric/Nodes/Deprecated/, not used for new work.
public class JointBilateralFilterNode: Node
{
    override public class var name: String { "Joint Bilateral Filter" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Mask) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Edge-aware smoothing of Signal, guided by Guide's own edges -- smooths flat regions while snapping back to sharp transitions wherever Guide has one. Recovers detail a low-resolution mask lost to plain bilinear upsampling." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputSignal", NodePort<FabricImage>(name: "Signal", kind: .Inlet, description: "Image or mask to smooth")),
            ("inputGuide", NodePort<FabricImage>(name: "Guide", kind: .Inlet, description: "Sharp reference image whose edges constrain the smoothing (e.g. the original camera frame a mask was derived from). Passes Signal through unchanged when unconnected.")),
            ("inputRadius", ParameterPort(parameter: IntParameter("Radius", 5, 1, 16, .slider, "Kernel half-width in pixels"))),
            ("inputSpatialSigma", ParameterPort(parameter: FloatParameter("Spatial Sigma", 3.0, 0.1, 16.0, .slider, "Spatial falloff -- larger blurs further"))),
            ("inputRangeSigma", ParameterPort(parameter: FloatParameter("Range Sigma", 0.1, 0.01, 1.0, .slider, "Guide-luma-difference tolerance treated as still the same surface -- smaller snaps to edges more aggressively"))),

            ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Signal, edge-aware smoothed using Guide")),
        ]
    }

    public var inputSignal: NodePort<FabricImage> { port(named: "inputSignal") }
    public var inputGuide: NodePort<FabricImage> { port(named: "inputGuide") }
    public var inputRadius: ParameterPort<Int> { port(named: "inputRadius") }
    public var inputSpatialSigma: ParameterPort<Float> { port(named: "inputSpatialSigma") }
    public var inputRangeSigma: ParameterPort<Float> { port(named: "inputRangeSigma") }
    public var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

    private struct FilterUniforms
    {
        var radius: Int32
        var spatialSigma: Float
        var rangeSigma: Float
    }

    private var pipeline: MTLComputePipelineState?

    public required init(context: Context)
    {
        super.init(context: context)
        self.setupComputePipeline()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        self.setupComputePipeline()
    }

    private func setupComputePipeline()
    {
        let device = self.context.device
        let compiler = MetalFileCompiler(watch: false)

        guard
            let shaderURL = Bundle.module.url(forResource: "JointBilateralFilter", withExtension: "metal", subdirectory: "Compute/Mask"),
            let source = try? compiler.parse(shaderURL),
            let library = try? device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: "jointBilateralFilter")
        else { return }

        self.pipeline = try? device.makeComputePipelineState(function: function)
    }

    public override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        guard
            self.inputSignal.valueDidChange
                || self.inputGuide.valueDidChange
                || self.inputRadius.valueDidChange
                || self.inputSpatialSigma.valueDidChange
                || self.inputRangeSigma.valueDidChange
        else { return }

        guard let signalImage = self.inputSignal.value else
        {
            self.outputImage.send(nil)
            return
        }

        guard let guideImage = self.inputGuide.value else
        {
            // No guide to constrain the smoothing against -- pass the
            // signal through unchanged rather than fail, matching how
            // other nodes here degrade gracefully when an optional
            // reference input is unconnected.
            self.outputImage.send(signalImage)
            return
        }

        guard let pipeline = self.pipeline else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "\(self) compute pipeline is unavailable")
        }

        let signalTexture = signalImage.texture
        let outImage = try renderer.newImage(withWidth: signalTexture.width, height: signalTexture.height)
        outImage.textureTransform = signalImage.textureTransform

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create \(self) compute encoder")
        }

        var uniforms = FilterUniforms(
            radius: Int32(max(1, self.inputRadius.value ?? 5)),
            spatialSigma: max(0.001, self.inputSpatialSigma.value ?? 3.0),
            rangeSigma: max(0.001, self.inputRangeSigma.value ?? 0.1)
        )

        encoder.label = "Joint Bilateral Filter"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(signalTexture, index: 0)
        encoder.setTexture(guideImage.texture, index: 1)
        encoder.setTexture(outImage.texture, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<FilterUniforms>.stride, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: signalTexture.width, height: signalTexture.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        encoder.endEncoding()

        self.outputImage.send(outImage)
    }
}
