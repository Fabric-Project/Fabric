import Foundation
import Metal
import Satin
import simd

public final class DepthOfFieldNode: Node
{
    public override class var name: String { "Depth Of Field" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Blur) }
    public override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    public override class var nodeTimeMode: Node.TimeMode { .None }
    public override class var nodeDescription: String { "Applies a bokeh depth-of-field pass using a color image and matching depth image." }

    public let inputImage = NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input color image to blur")
    public let inputDepthImage = NodePort<FabricImage>(name: "Depth Image", kind: .Inlet, description: "Input depth image for focus reconstruction")
    public let inputFocusDistance = ParameterPort(parameter: FloatParameter("Focus Distance", 4.0, 0.001, 1000.0, .slider, "Distance from the camera that stays sharp"))
    public let inputFocusRange = ParameterPort(parameter: FloatParameter("Focus Range", 1.5, 0.001, 1000.0, .slider, "Full depth band that remains acceptably sharp"))
    public let inputMaxBlurRadius = ParameterPort(parameter: FloatParameter("Max Blur Radius", 18.0, 0.0, 32.0, .slider, "Maximum circle-of-confusion radius in full-resolution pixels"))
    public let inputResolutionScale = ParameterPort(parameter: FloatParameter("Resolution Scale", 0.5, 0.25, 1.0, .slider, "Internal processing resolution relative to the input image"))
    public let inputBlend = ParameterPort(parameter: FloatParameter("Blend", 1.0, 0.0, 4.0, .slider, "Blend multiplier applied to the near and far compositing ramps"))
    public let outputImage = NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Depth-of-field processed image")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputImage", port: self.inputImage),
            PortDeclaration(key: "inputDepthImage", port: self.inputDepthImage),
            PortDeclaration(key: "inputFocusDistance", port: self.inputFocusDistance),
            PortDeclaration(key: "inputFocusRange", port: self.inputFocusRange),
            PortDeclaration(key: "inputMaxBlurRadius", port: self.inputMaxBlurRadius),
            PortDeclaration(key: "inputResolutionScale", port: self.inputResolutionScale),
            PortDeclaration(key: "inputBlend", port: self.inputBlend),
            PortDeclaration(key: "outputImage", port: self.outputImage),
        ]
    }

    private let postProcessor: BokehDepthOfFieldPostProcessEncoder
    private let fallbackCamera: PerspectiveCamera

    public required init(context: Context)
    {
        self.postProcessor = BokehDepthOfFieldPostProcessEncoder(context: context)
        self.fallbackCamera = PerspectiveCamera(context: context)
        self.fallbackCamera.position = simd_float3(0.0, 0.0, 2.0)
        self.fallbackCamera.lookAt(target: .zero)
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        self.postProcessor = BokehDepthOfFieldPostProcessEncoder(context: decodeContext.documentContext)
        self.fallbackCamera = PerspectiveCamera(context: decodeContext.documentContext)
        self.fallbackCamera.position = simd_float3(0.0, 0.0, 2.0)
        self.fallbackCamera.lookAt(target: .zero)
        try super.init(from: decoder)
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let colorImage = self.inputImage.value,
              let depthImage = self.inputDepthImage.value
        else
        {
            self.outputImage.send(nil)
            return
        }
        let colorTexture = colorImage.texture

        if renderer.currentCamera == nil
        {
            self.fallbackCamera.aspect = Float(colorTexture.width) / Float(max(colorTexture.height, 1))
        }

        self.postProcessor.colorTexture = colorTexture
        self.postProcessor.depthTexture = depthImage.texture
        self.postProcessor.sceneCamera = renderer.currentCamera ?? self.fallbackCamera
        self.postProcessor.focusDistance = self.inputFocusDistance.value ?? 4.0
        self.postProcessor.focusRange = self.inputFocusRange.value ?? 1.5
        self.postProcessor.maxBlurRadius = self.inputMaxBlurRadius.value ?? 18.0
        self.postProcessor.resolutionScale = self.inputResolutionScale.value ?? 0.5
        self.postProcessor.blend = self.inputBlend.value ?? 1.0
        self.postProcessor.resize(size: (Float(colorTexture.width), Float(colorTexture.height)), scaleFactor: 1.0)
        try self.postProcessor.draw(frame: executionInfo.timing, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)

        guard let processedTexture = self.postProcessor.outputTexture else
        {
            self.outputImage.send(nil)
            return
        }

        let outputImage = try renderer.newImage(withWidth: processedTexture.width,
                                                height: processedTexture.height,
                                                format: processedTexture.pixelFormat)
        outputImage.textureTransform = colorImage.textureTransform
        try self.copyTexture(processedTexture, to: outputImage.texture, using: commandBuffer)
        self.outputImage.send(outputImage)
    }

    private func copyTexture(_ source: MTLTexture, to destination: MTLTexture, using commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else
        {
            throw FabricError(.execution(.gpu),
                              severity: .recoverable,
                              message: "Could not create \(self) copy blit encoder")
        }
        blitEncoder.label = "\(self.title) Copy"
        blitEncoder.copy(from: source,
                         sourceSlice: 0,
                         sourceLevel: 0,
                         sourceOrigin: .init(x: 0, y: 0, z: 0),
                         sourceSize: .init(width: source.width, height: source.height, depth: 1),
                         to: destination,
                         destinationSlice: 0,
                         destinationLevel: 0,
                         destinationOrigin: .init(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()
    }
}
