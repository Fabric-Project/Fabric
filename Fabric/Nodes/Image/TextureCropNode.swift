import Foundation
import Satin
import simd
import Metal

/// Crops a presentation-space rectangle and returns an identity-oriented image.
public class TextureCropNode: Node
{
    private final class PostMaterial: SourceMaterial {}

    public override class var name: String { "Texture Crop" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .BaseEffect) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Crops a rectangular region from a texture" }

    public let inputTexture = NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Source texture to crop")
    public let inputCropX = ParameterPort(parameter: IntParameter("Crop X", 0, 0, 16384, .inputfield, "X origin of crop region"))
    public let inputCropY = ParameterPort(parameter: IntParameter("Crop Y", 0, 0, 16384, .inputfield, "Y origin of crop region"))
    public let inputCropWidth = ParameterPort(parameter: IntParameter("Crop Width", 1920, 1, 16384, .inputfield, "Width of crop region"))
    public let inputCropHeight = ParameterPort(parameter: IntParameter("Crop Height", 1080, 1, 16384, .inputfield, "Height of crop region"))
    public let outputTexture = NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Cropped texture")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTexture", port: self.inputTexture),
            PortDeclaration(key: "inputCropX", port: self.inputCropX),
            PortDeclaration(key: "inputCropY", port: self.inputCropY),
            PortDeclaration(key: "inputCropWidth", port: self.inputCropWidth),
            PortDeclaration(key: "inputCropHeight", port: self.inputCropHeight),
            PortDeclaration(key: "outputTexture", port: self.outputTexture),
        ]
    }

    private struct CropUniforms
    {
        var origin: simd_float2
        var size: simd_float2
        var textureTransform: simd_float4x4
    }

    private let cropMaterial: PostMaterial
    private let cropProcessor: PostProcessEncoder
    private lazy var cropUniformsBuffer = StructBuffer<CropUniforms>(device: self.context.device,
                                                                     count: 1,
                                                                     label: "Texture Crop Uniforms")

    public required init(context: Context)
    {
        let material = PostMaterial(context: context, pipelineURL: Self.shaderURL())
        self.cropMaterial = material
        self.cropProcessor = PostProcessEncoder(context: context,
                                                material: material,
                                                depthPixelFormat: .invalid,
                                                stencilPixelFormat: .invalid,
                                                frameBufferOnly: false)
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        guard let context = decoder.context?.documentContext as? Context else {
            fatalError("Required Decode Context Not set")
        }

        let material = PostMaterial(context: context, pipelineURL: Self.shaderURL())
        self.cropMaterial = material
        self.cropProcessor = PostProcessEncoder(context: context,
                                                material: material,
                                                depthPixelFormat: .invalid,
                                                stencilPixelFormat: .invalid,
                                                frameBufferOnly: false)
        try super.init(from: decoder)
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let sourceImage = inputTexture.value else { return }

        let presentationWidth = max(1, Int(sourceImage.presentationSize.width.rounded()))
        let presentationHeight = max(1, Int(sourceImage.presentationSize.height.rounded()))
        let cropX = max(0, min(inputCropX.value ?? 0, presentationWidth - 1))
        let cropY = max(0, min(inputCropY.value ?? 0, presentationHeight - 1))
        let cropWidth = max(1, min(inputCropWidth.value ?? 1920, presentationWidth - cropX))
        let cropHeight = max(1, min(inputCropHeight.value ?? 1080, presentationHeight - cropY))

        let outImage = try renderer.newImage(withWidth: cropWidth, height: cropHeight)
        let cropUniforms = CropUniforms(origin: simd_float2(Float(cropX) / Float(presentationWidth),
                                                            Float(cropY) / Float(presentationHeight)),
                                        size: simd_float2(Float(cropWidth) / Float(presentationWidth),
                                                          Float(cropHeight) / Float(presentationHeight)),
                                        textureTransform: sourceImage.textureTransform)
        self.cropUniformsBuffer.update(data: [cropUniforms])
        self.cropMaterial.set(self.cropUniformsBuffer, index: FragmentBufferIndex.Custom0)
        self.cropMaterial.set(sourceImage.texture, index: FragmentTextureIndex.Custom0)
        self.cropProcessor.resize(size: (width: Float(cropWidth), height: Float(cropHeight)),
                                  scaleFactor: 1)

        let cropRenderPassDescriptor = MTLRenderPassDescriptor()
        cropRenderPassDescriptor.colorAttachments[0].texture = outImage.texture
        try self.cropProcessor.draw(frame: executionInfo.timing,
                                    renderPassDescriptor: cropRenderPassDescriptor,
                                    commandBuffer: commandBuffer)

        outputTexture.send(outImage)
    }

    private static func shaderURL() -> URL
    {
        guard let shaderURL = Bundle.module.url(forResource: "TextureCropShader",
                                                withExtension: "metal",
                                                subdirectory: "Shaders") else {
            fatalError("TextureCropShader.metal is missing from the Fabric resource bundle")
        }

        return shaderURL
    }
}
