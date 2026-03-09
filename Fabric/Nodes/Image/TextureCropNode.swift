import Foundation
import Satin
import simd
import Metal

/// Crops a rectangular sub-region from an input texture using a blit encoder.
public class TextureCropNode: Node
{
    public override class var name: String { "Texture Crop" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .BaseEffect) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Crops a rectangular region from a texture" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputTexture", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Source texture to crop")),
            ("inputCropX", ParameterPort(parameter: IntParameter("Crop X", 0, 0, 16384, .inputfield, "X origin of crop region"))),
            ("inputCropY", ParameterPort(parameter: IntParameter("Crop Y", 0, 0, 16384, .inputfield, "Y origin of crop region"))),
            ("inputCropWidth", ParameterPort(parameter: IntParameter("Crop Width", 1920, 1, 16384, .inputfield, "Width of crop region"))),
            ("inputCropHeight", ParameterPort(parameter: IntParameter("Crop Height", 1080, 1, 16384, .inputfield, "Height of crop region"))),
            ("outputTexture", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Cropped texture")),
        ]
    }

    public var inputTexture: NodePort<FabricImage> { port(named: "inputTexture") }
    public var inputCropX: ParameterPort<Int> { port(named: "inputCropX") }
    public var inputCropY: ParameterPort<Int> { port(named: "inputCropY") }
    public var inputCropWidth: ParameterPort<Int> { port(named: "inputCropWidth") }
    public var inputCropHeight: ParameterPort<Int> { port(named: "inputCropHeight") }
    public var outputTexture: NodePort<FabricImage> { port(named: "outputTexture") }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let sourceImage = inputTexture.value,
              let graphRenderer = context.graphRenderer else { return }

        let srcTex = sourceImage.texture
        let x = max(0, min(inputCropX.value ?? 0, srcTex.width - 1))
        let y = max(0, min(inputCropY.value ?? 0, srcTex.height - 1))
        let w = max(1, min(inputCropWidth.value ?? 1920, srcTex.width - x))
        let h = max(1, min(inputCropHeight.value ?? 1080, srcTex.height - y))

        guard let outImage = graphRenderer.newImage(withWidth: w, height: h) else { return }

        guard let encoder = commandBuffer.makeBlitCommandEncoder() else { return }
        encoder.copy(
            from: srcTex,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: x, y: y, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: outImage.texture,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()

        outputTexture.send(outImage)
    }
}
