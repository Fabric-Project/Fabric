//
//  MPSGuidedFilterNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal
import MetalPerformanceShaders

/// Edge-aware refinement of a single-channel mask (the "signal") guided by a
/// color image (the "guide") -- same job as JointBilateralFilterNode, via
/// Apple's own MPSImageGuidedFilter (He/Sun/Tang's Guided Image Filter,
/// https://arxiv.org/pdf/1505.00996.pdf) instead of a hand-written bilateral
/// kernel. Guided filter fits a local linear model (output = a*guide + b)
/// per window via box-filtered statistics -- O(1) per radius rather than
/// the bilateral filter's O(r^2) per pixel, and structurally avoids the
/// gradient-reversal/halo artifacts a bilateral filter can show near strong
/// edges. It is not the same algorithm and will not match pixel-for-pixel;
/// this node exists as a same-contract A/B comparison peer.
///
/// The Guide is the first input and defines the output, like the first image
/// input of BaseImageNode. Regression runs at the Signal's presentation
/// resolution against a canonical copy of the Guide at that same resolution.
/// Reconstruction then applies those coefficients to a canonical,
/// presentation-resolution Guide. This is the fast guided-filter path: the
/// expensive regression can stay at mask resolution while reconstruction
/// restores the Guide-sized output.
///
/// Uses MPSImageGuidedFilter's scalar-mask overload. Its RGBA coefficient
/// texture stores three slopes for Guide RGB plus one intercept, so edges in
/// every guide color channel can constrain the output mask.
public class MPSGuidedFilterNode: Node
{
    override public class var name: String { "Guided Filter" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Mask) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Fast edge-aware mask refinement. Fits scalar-mask coefficients against an RGB Guide at the Signal's resolution, then reconstructs at the Guide's presentation resolution." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputGuide", NodePort<FabricImage>(name: "Guide", kind: .Inlet, description: "Sharp reference image whose edges constrain the smoothing (e.g. the original camera frame a mask was derived from). Sets the size and orientation of the output. Passes Signal through unchanged when unconnected.")),
            ("inputSignal", NodePort<FabricImage>(name: "Signal", kind: .Inlet, description: "Single-channel mask to refine. Regression runs at this image's presentation resolution")),
            ("inputRadius", ParameterPort(parameter: IntParameter("Radius", 5, 0, 16, .slider, "Local window half-width in Signal presentation pixels -- MPSImageGuidedFilter's kernelDiameter is 2x this plus 1"))),
            ("inputEpsilon", ParameterPort(parameter: FloatParameter("Epsilon", 0.0001, 0.000001, 0.1, .slider, "Regularization -- smaller preserves edges more aggressively, larger smooths more (this filter's counterpart to Joint Bilateral Filter's Range Sigma)"))),

            ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Single-channel Float32 mask refined using the RGB Guide, at the Guide's presentation size in canonical orientation")),
        ]
    }

    public var inputGuide: NodePort<FabricImage> { port(named: "inputGuide") }
    public var inputSignal: NodePort<FabricImage> { port(named: "inputSignal") }
    public var inputRadius: ParameterPort<Int> { port(named: "inputRadius") }
    public var inputEpsilon: ParameterPort<Float> { port(named: "inputEpsilon") }
    public var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

    private struct ResampleUniforms
    {
        var textureTransform: simd_float4x4
    }

    /// Recreated whenever the active radius (kernelDiameter) differs from
    /// whatever it was last built for -- MPSImageGuidedFilter's window size
    /// is fixed at init, unlike epsilon/reconstructScale/reconstructOffset,
    /// which are plain settable properties on an existing instance.
    private var filter: MPSImageGuidedFilter?
    private var filterKernelDiameter: Int?

    /// Recreated whenever the active regression resolution changes.
    /// Coefficients are an intermediate the caller owns, per this filter's
    /// two-stage design, which allows temporal filtering. They are unused
    /// here beyond the one regression->reconstruction pass per frame.
    private var coefficients: MTLTexture?
    private var coefficientsSize: (width: Int, height: Int)?

    private var resamplePipeline: MTLComputePipelineState?

    public required init(context: Context)
    {
        super.init(context: context)
        self.setupResamplePipeline()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        self.setupResamplePipeline()
    }

    private func setupResamplePipeline()
    {
        let device = self.context.device
        let compiler = MetalFileCompiler(watch: false)

        guard
            let shaderURL = Bundle.module.url(forResource: "CanonicalResample", withExtension: "metal", subdirectory: "Compute/Mask"),
            let source = try? compiler.parse(shaderURL),
            let library = try? device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: "resampleToCanonical")
        else
        {
            print("Guided Filter: could not load or compile CanonicalResample.metal")
            return
        }

        self.resamplePipeline = try? device.makeComputePipelineState(function: function)
    }

    private func guidedFilter(kernelDiameter: Int) -> MPSImageGuidedFilter
    {
        if let existing = self.filter, self.filterKernelDiameter == kernelDiameter { return existing }
        let created = MPSImageGuidedFilter(device: self.context.device, kernelDiameter: kernelDiameter)
        self.filter = created
        self.filterKernelDiameter = kernelDiameter
        return created
    }

    private func coefficientsTexture(width: Int, height: Int) throws -> MTLTexture
    {
        if let coefficients = self.coefficients, let size = self.coefficientsSize, size.width == width, size.height == height
        {
            return coefficients
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        guard let coefficients = self.context.device.makeTexture(descriptor: descriptor)
        else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "\(self) could not allocate coefficients texture")
        }
        coefficients.label = "MPS Guided Filter RGB coefficients and intercept"

        self.coefficients = coefficients
        self.coefficientsSize = (width, height)
        return coefficients
    }

    private static func pixelSize(of image: FabricImage) -> (width: Int, height: Int)
    {
        (
            max(1, Int(image.presentationSize.width.rounded())),
            max(1, Int(image.presentationSize.height.rounded()))
        )
    }

    private func canonicalTexture(
        of image: FabricImage,
        width: Int,
        height: Int,
        format: MTLPixelFormat,
        renderer: GraphRenderer,
        commandBuffer: MTLCommandBuffer,
        temporaries: inout [FabricImage]
    ) throws -> MTLTexture
    {
        let isAlreadyCanonical = image.textureTransform == matrix_identity_float4x4
            && image.texture.width == width
            && image.texture.height == height
            && image.texture.pixelFormat == format
        if isAlreadyCanonical { return image.texture }

        guard let pipeline = self.resamplePipeline else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "\(self) resample pipeline is unavailable")
        }
        let resampled = try renderer.newImage(withWidth: width, height: height, format: format)
        resampled.textureTransform = matrix_identity_float4x4
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create \(self) resample encoder")
        }

        var uniforms = ResampleUniforms(textureTransform: image.textureTransform)
        encoder.label = "Guided Filter Canonical Resample"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(image.texture, index: 0)
        encoder.setTexture(resampled.texture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<ResampleUniforms>.stride, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        encoder.endEncoding()

        temporaries.append(resampled)
        return resampled.texture
    }

    public override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        guard
            self.inputGuide.valueDidChange
                || self.inputSignal.valueDidChange
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

        let signalSize = Self.pixelSize(of: signalImage)
        let guideSize = Self.pixelSize(of: guideImage)

        let radius = max(0, self.inputRadius.value ?? 5)
        let kernelDiameter = radius * 2 + 1
        let epsilon = max(0.000001, self.inputEpsilon.value ?? 0.0001)

        let filter = self.guidedFilter(kernelDiameter: kernelDiameter)
        filter.epsilon = epsilon

        let coefficients = try self.coefficientsTexture(width: signalSize.width, height: signalSize.height)
        var temporaries: [FabricImage] = []
        let regressionSource = try self.canonicalTexture(
            of: signalImage,
            width: signalSize.width,
            height: signalSize.height,
            format: .r32Float,
            renderer: renderer,
            commandBuffer: commandBuffer,
            temporaries: &temporaries
        )
        let regressionGuide = try self.canonicalTexture(
            of: guideImage,
            width: signalSize.width,
            height: signalSize.height,
            format: .rgba16Float,
            renderer: renderer,
            commandBuffer: commandBuffer,
            temporaries: &temporaries
        )
        let reconstructionGuide = try self.canonicalTexture(
            of: guideImage,
            width: guideSize.width,
            height: guideSize.height,
            format: .rgba16Float,
            renderer: renderer,
            commandBuffer: commandBuffer,
            temporaries: &temporaries
        )
        let outImage = try renderer.newImage(withWidth: guideSize.width, height: guideSize.height, format: .r32Float)
        outImage.textureTransform = matrix_identity_float4x4

        filter.encodeRegression(
            to: commandBuffer,
            sourceTexture: regressionSource,
            guidanceTexture: regressionGuide,
            weightsTexture: nil,
            destinationCoefficientsTexture: coefficients
        )

        filter.encodeReconstruction(
            to: commandBuffer,
            guidanceTexture: reconstructionGuide,
            coefficientsTexture: coefficients,
            destinationTexture: outImage.texture
        )

        let retainedImages = temporaries + [signalImage, guideImage]
        commandBuffer.addCompletedHandler { _ in
            withExtendedLifetime(retainedImages) {}
        }

        self.outputImage.send(outImage)
    }
}
