import Foundation
import Satin
import simd
import Metal

public class SolidColorProviderNode: Node
{
    public override class var name: String { "Solid Color" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Generator) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Fill a texture with a uniform colour" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputWidth", ParameterPort(parameter: IntParameter("Width", 1920, 1, 8192, .inputfield, "Output width in pixels"))),
            ("inputHeight", ParameterPort(parameter: IntParameter("Height", 1080, 1, 8192, .inputfield, "Output height in pixels"))),
            ("inputColor", ParameterPort(parameter: Float4Parameter("Color", simd_float4(0, 0, 0, 1), .colorpicker, "Fill colour (RGBA)"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Solid colour image")),
        ]
    }

    public var inputWidth: ParameterPort<Int> { port(named: "inputWidth") }
    public var inputHeight: ParameterPort<Int> { port(named: "inputHeight") }
    public var inputColor: ParameterPort<simd_float4> { port(named: "inputColor") }
    public var outputTexturePort: NodePort<FabricImage> { port(named: "outputTexturePort") }

    @ObservationIgnored private var computePipeline: MTLComputePipelineState?

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
        guard let shaderURL = Bundle.module.url(forResource: "SolidColor", withExtension: "metal", subdirectory: "Compute"),
              let source = try? String(contentsOf: shaderURL, encoding: .utf8),
              let library = try? device.makeLibrary(source: source, options: nil),
              let function = library.makeFunction(name: "solidColorFill")
        else { return }

        self.computePipeline = try? device.makeComputePipelineState(function: function)
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let width = max(1, self.inputWidth.value ?? 1920)
        let height = max(1, self.inputHeight.value ?? 1080)
        let color = self.inputColor.value ?? simd_float4(0, 0, 0, 1)

        guard let pipeline = self.computePipeline,
              let outImage = context.graphRenderer?.newImage(withWidth: width, height: height),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return }

        var colorValue = color
        computeEncoder.setComputePipelineState(pipeline)
        computeEncoder.setTexture(outImage.texture, index: 0)
        computeEncoder.setBytes(&colorValue, length: MemoryLayout<simd_float4>.size, index: 0)

        let threadGroupSize = MTLSize(width: min(16, width), height: min(16, height), depth: 1)
        let threadGroups = MTLSize(
            width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()

        self.outputTexturePort.send(outImage)
    }
}
