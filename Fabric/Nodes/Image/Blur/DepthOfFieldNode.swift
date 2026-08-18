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

    public override class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        super.registerPorts(context: context) + [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input color image to blur")),
            ("inputDepthImage", NodePort<FabricImage>(name: "Depth Image", kind: .Inlet, description: "Input depth image for focus reconstruction")),
            ("inputFocusDistance", ParameterPort(parameter: FloatParameter("Focus Distance", 4.0, 0.001, 1000.0, .slider, "Distance from the camera that stays sharp"))),
            ("inputFocusRange", ParameterPort(parameter: FloatParameter("Focus Range", 1.5, 0.001, 1000.0, .slider, "Full depth band that remains acceptably sharp"))),
            ("inputMaxBlurRadius", ParameterPort(parameter: FloatParameter("Max Blur Radius", 18.0, 0.0, 32.0, .slider, "Maximum circle-of-confusion radius in full-resolution pixels"))),
            ("inputResolutionScale", ParameterPort(parameter: FloatParameter("Resolution Scale", 0.5, 0.25, 1.0, .slider, "Internal processing resolution relative to the input image"))),
            ("inputBlend", ParameterPort(parameter: FloatParameter("Blend", 1.0, 0.0, 4.0, .slider, "Blend multiplier applied to the near and far compositing ramps"))),
            ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Depth-of-field processed image")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputDepthImage: NodePort<FabricImage> { port(named: "inputDepthImage") }
    public var inputFocusDistance: ParameterPort<Float> { port(named: "inputFocusDistance") }
    public var inputFocusRange: ParameterPort<Float> { port(named: "inputFocusRange") }
    public var inputMaxBlurRadius: ParameterPort<Float> { port(named: "inputMaxBlurRadius") }
    public var inputResolutionScale: ParameterPort<Float> { port(named: "inputResolutionScale") }
    public var inputBlend: ParameterPort<Float> { port(named: "inputBlend") }
    public var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

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
        guard
              let colorTexture = self.inputImage.value?.texture,
              let depthTexture = self.inputDepthImage.value?.texture
        else
        {
            self.outputImage.send(nil)
            return
        }

        if renderer.currentCamera == nil
        {
            self.fallbackCamera.aspect = Float(colorTexture.width) / Float(max(colorTexture.height, 1))
        }

        self.postProcessor.colorTexture = colorTexture
        self.postProcessor.depthTexture = depthTexture
        self.postProcessor.sceneCamera = renderer.currentCamera ?? self.fallbackCamera
        self.postProcessor.focusDistance = self.inputFocusDistance.value ?? 4.0
        self.postProcessor.focusRange = self.inputFocusRange.value ?? 1.5
        self.postProcessor.maxBlurRadius = self.inputMaxBlurRadius.value ?? 18.0
        self.postProcessor.resolutionScale = self.inputResolutionScale.value ?? 0.5
        self.postProcessor.blend = self.inputBlend.value ?? 1.0
        self.postProcessor.resize(size: (Float(colorTexture.width), Float(colorTexture.height)), scaleFactor: 1.0)
        self.postProcessor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)

        guard let processedTexture = self.postProcessor.outputTexture else
        {
            self.outputImage.send(nil)
            return
        }

        let outputImage = try renderer.newImage(withWidth: processedTexture.width,
                                                height: processedTexture.height,
                                                format: processedTexture.pixelFormat)

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
        blitEncoder.label = "\(self.canonicalName) Copy"
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
