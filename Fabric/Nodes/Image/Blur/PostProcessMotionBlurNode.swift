import Foundation
import Metal
import Satin

public final class PostProcessMotionBlurNode: Node
{
    public override class var name: String { "Post Process Motion Blur" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Blur) }
    public override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    public override class var nodeTimeMode: Node.TimeMode { .None }
    public override class var nodeDescription: String { "Applies Satin's velocity-buffer motion blur to an input image." }

    public override class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        super.registerPorts(context: context) + [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input color image to blur")),
            ("inputVelocityImage", NodePort<FabricImage>(name: "Velocity Image", kind: .Inlet, description: "Input motion-vector image used to drive blur direction and length")),
            ("inputDepthImage", NodePort<FabricImage>(name: "Depth Image", kind: .Inlet, description: "Optional input depth image for neighborhood rejection")),
            ("inputShutterAngle", ParameterPort(parameter: FloatParameter("Shutter Angle", 180.0, 0.0, 720.0 * 64.0, .slider, "Exposure as degrees of one frame interval"))),
            ("inputSamples", ParameterPort(parameter: IntParameter("Samples", 16, 1, 32, .slider, "Number of velocity samples used during reconstruction"))),
            ("inputJitter", ParameterPort(parameter: FloatParameter("Jitter", 1.0, 0.0, 1.0, .slider, "Blue-noise jitter amount for sampling"))),
            ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Motion-blurred image")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputVelocityImage: NodePort<FabricImage> { port(named: "inputVelocityImage") }
    public var inputDepthImage: NodePort<FabricImage> { port(named: "inputDepthImage") }
    public var inputShutterAngle: ParameterPort<Float> { port(named: "inputShutterAngle") }
    public var inputSamples: ParameterPort<Int> { port(named: "inputSamples") }
    public var inputJitter: ParameterPort<Float> { port(named: "inputJitter") }
    public var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

    private let postProcessor: MotionBlurPostProcessEncoder

    public required init(context: Context)
    {
        self.postProcessor = MotionBlurPostProcessEncoder(context: context)
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        self.postProcessor = MotionBlurPostProcessEncoder(context: decodeContext.documentContext)
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
              let velocityTexture = self.inputVelocityImage.value?.texture
        else
        {
            self.outputImage.send(nil)
            return
        }

        self.postProcessor.colorTexture = colorTexture
        self.postProcessor.velocityTexture = velocityTexture
        self.postProcessor.depthTexture = self.inputDepthImage.value?.texture
        self.postProcessor.motionBlurMaterial.shutterAngle = self.inputShutterAngle.value ?? 180.0
        self.postProcessor.motionBlurMaterial.samples = Int32(self.inputSamples.value ?? 16)
        self.postProcessor.motionBlurMaterial.jitter = self.inputJitter.value ?? 1.0
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
                              message: "Could not create \(debugName) copy blit encoder")
        }
        blitEncoder.label = "\(self.typeName) Copy"
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
