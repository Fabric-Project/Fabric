//
//  MPSGuidedFilterNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal
import MetalPerformanceShaders

/// Edge-aware smoothing of one image (the "signal") guided by another (the
/// "guide") -- same job as JointBilateralFilterNode, via Apple's own
/// MPSImageGuidedFilter (He/Sun/Tang's Guided Image Filter,
/// https://arxiv.org/pdf/1505.00996.pdf) instead of a hand-written bilateral
/// kernel. Guided filter fits a local linear model (output = a*guide + b)
/// per window via box-filtered statistics -- O(1) per radius rather than
/// the bilateral filter's O(r^2) per pixel, and structurally avoids the
/// gradient-reversal/halo artifacts a bilateral filter can show near strong
/// edges. It is not the same algorithm and will not match pixel-for-pixel;
/// this node exists as a same-contract A/B comparison peer.
///
/// Uses MPSImageGuidedFilter's per-channel regression/reconstruction
/// overload (encodeRegression/encodeReconstruction with separate A/B
/// coefficient textures) rather than the single-coefficients-texture
/// overload, since that overload requires a single-channel source texture
/// -- the per-channel overload instead regresses each of Signal's channels
/// independently against Guide's RGB, matching JointBilateralFilterNode's
/// own "works on any {signal, guide} pair" contract rather than restricting
/// Signal to a single channel.
///
/// Regression and reconstruction both run at Signal's own resolution (no
/// downsample step) -- same same-resolution assumption
/// JointBilateralFilterNode documents, not the multi-resolution joint-
/// upsampling mode this filter also supports.
public class MPSGuidedFilterNode: Node
{
    override public class var name: String { "Guided Filter" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Edge-aware smoothing of Signal, guided by Guide's own edges, a fast, halo-resistant alternative to Joint Bilateral Filter for the same job (e.g. recovering detail a low-resolution mask lost to plain bilinear upsampling)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputSignal", NodePort<FabricImage>(name: "Signal", kind: .Inlet, description: "Image or mask to smooth")),
            ("inputGuide", NodePort<FabricImage>(name: "Guide", kind: .Inlet, description: "Sharp reference image whose edges constrain the smoothing (e.g. the original camera frame a mask was derived from). Passes Signal through unchanged when unconnected.")),
            ("inputRadius", ParameterPort(parameter: IntParameter("Radius", 5, 1, 16, .slider, "Local window half-width in pixels -- MPSImageGuidedFilter's own kernelDiameter is 2x this plus 1"))),
            ("inputEpsilon", ParameterPort(parameter: FloatParameter("Epsilon", 0.0001, 0.000001, 0.1, .slider, "Regularization -- smaller preserves edges more aggressively, larger smooths more (this filter's counterpart to Joint Bilateral Filter's Range Sigma)"))),

            ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Signal, edge-aware smoothed using Guide via MPSImageGuidedFilter")),
        ]
    }

    public var inputSignal: NodePort<FabricImage> { port(named: "inputSignal") }
    public var inputGuide: NodePort<FabricImage> { port(named: "inputGuide") }
    public var inputRadius: ParameterPort<Int> { port(named: "inputRadius") }
    public var inputEpsilon: ParameterPort<Float> { port(named: "inputEpsilon") }
    public var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

    /// Recreated whenever the active radius (kernelDiameter) differs from
    /// whatever it was last built for -- MPSImageGuidedFilter's window size
    /// is fixed at init, unlike epsilon/reconstructScale/reconstructOffset,
    /// which are plain settable properties on an existing instance.
    private var filter: MPSImageGuidedFilter?
    private var filterKernelDiameter: Int?

    /// Recreated whenever Signal's resolution changes. Coefficients are an
    /// intermediate the caller owns (per this filter's two-stage design,
    /// meant to allow e.g. temporal filtering of coefficients) -- unused
    /// here beyond the one regression->reconstruction pass per frame.
    private var coefficientsA: MTLTexture?
    private var coefficientsB: MTLTexture?
    private var coefficientsSize: (width: Int, height: Int)?

    private func guidedFilter(kernelDiameter: Int) -> MPSImageGuidedFilter
    {
        if let existing = self.filter, self.filterKernelDiameter == kernelDiameter { return existing }
        let created = MPSImageGuidedFilter(device: self.context.device, kernelDiameter: kernelDiameter)
        self.filter = created
        self.filterKernelDiameter = kernelDiameter
        return created
    }

    private func coefficientsTextures(width: Int, height: Int) throws -> (a: MTLTexture, b: MTLTexture)
    {
        if let a = self.coefficientsA, let b = self.coefficientsB, let size = self.coefficientsSize, size.width == width, size.height == height
        {
            return (a, b)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        guard
            let a = self.context.device.makeTexture(descriptor: descriptor),
            let b = self.context.device.makeTexture(descriptor: descriptor)
        else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "\(self) could not allocate coefficients textures")
        }
        a.label = "MPS Guided Filter coefficients A"
        b.label = "MPS Guided Filter coefficients B"

        self.coefficientsA = a
        self.coefficientsB = b
        self.coefficientsSize = (width, height)
        return (a, b)
    }

    public override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        guard
            self.inputSignal.valueDidChange
                || self.inputGuide.valueDidChange
                || self.inputRadius.valueDidChange
                || self.inputEpsilon.valueDidChange
        else { return }

        guard let signalImage = self.inputSignal.value else
        {
            self.outputImage.send(nil)
            return
        }

        guard let guideImage = self.inputGuide.value else
        {
            // No guide to constrain the smoothing against -- pass the
            // signal through unchanged, matching JointBilateralFilterNode's
            // own degrade-gracefully behavior.
            self.outputImage.send(signalImage)
            return
        }

        let signalTexture = signalImage.texture
        let width = signalTexture.width, height = signalTexture.height

        let radius = max(1, self.inputRadius.value ?? 5)
        let kernelDiameter = radius * 2 + 1
        let epsilon = max(0.000001, self.inputEpsilon.value ?? 0.0001)

        let filter = self.guidedFilter(kernelDiameter: kernelDiameter)
        filter.epsilon = epsilon

        let (coefficientsA, coefficientsB) = try self.coefficientsTextures(width: width, height: height)

        let outImage = try renderer.newImage(withWidth: width, height: height)
        outImage.textureTransform = signalImage.textureTransform

        filter.encodeRegression(
            commandBuffer: commandBuffer,
            source: signalTexture,
            guidance: guideImage.texture,
            weights: nil,
            destinationCoefficientsA: coefficientsA,
            destinationCoefficientsB: coefficientsB
        )
        filter.encodeReconstruction(
            commandBuffer: commandBuffer,
            guidance: guideImage.texture,
            coefficientsA: coefficientsA,
            coefficientsB: coefficientsB,
            destination: outImage.texture
        )

        self.outputImage.send(outImage)
    }
}
