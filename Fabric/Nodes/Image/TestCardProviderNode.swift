//
//  TestCardProviderNode.swift
//  Fabric
//
//  Created by Claude on 3/1/26.
//

import Foundation
import Satin
import simd
import Metal
import AppKit

public class TestCardProviderNode: Node
{
    public override class var name: String { "Test Card" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Generator) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Generate a test card with toggleable border, diagonals, circle, grey ramp, and grid" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputWidth", ParameterPort(parameter: IntParameter("Width", 1920, 1, 8192, .inputfield, "Output image width in pixels"))),
            ("inputHeight", ParameterPort(parameter: IntParameter("Height", 1080, 1, 8192, .inputfield, "Output image height in pixels"))),
            ("inputBorder", ParameterPort(parameter: BoolParameter("Border", true, .toggle, "Show 1px border with black inset"))),
            ("inputGreys", ParameterPort(parameter: BoolParameter("Greys", true, .toggle, "Show 5×2 greyscale gradient cells"))),
            ("inputDiagonals", ParameterPort(parameter: BoolParameter("Diagonals", true, .toggle, "Show corner-to-corner diagonal lines"))),
            ("inputCircle", ParameterPort(parameter: BoolParameter("Circle", true, .toggle, "Show centred circle"))),
            ("inputGrid", ParameterPort(parameter: BoolParameter("Grid", true, .toggle, "Show 1px grid lines"))),
            ("inputGridSpacing", ParameterPort(parameter: IntParameter("Grid Spacing", 40, 2, 4096, .inputfield, "Grid line spacing in pixels"))),
            ("inputText", ParameterPort(parameter: BoolParameter("Text", true, .toggle, "Show centred text label"))),
            ("inputTextString", ParameterPort(parameter: StringParameter("Label", "Fabric", .inputfield, "Text to display on the test card"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Generated test card image")),
        ]
    }

    public var inputWidth: ParameterPort<Int> { port(named: "inputWidth") }
    public var inputHeight: ParameterPort<Int> { port(named: "inputHeight") }
    public var inputBorder: ParameterPort<Bool> { port(named: "inputBorder") }
    public var inputGreys: ParameterPort<Bool> { port(named: "inputGreys") }
    public var inputDiagonals: ParameterPort<Bool> { port(named: "inputDiagonals") }
    public var inputCircle: ParameterPort<Bool> { port(named: "inputCircle") }
    public var inputGrid: ParameterPort<Bool> { port(named: "inputGrid") }
    public var inputGridSpacing: ParameterPort<Int> { port(named: "inputGridSpacing") }
    public var inputText: ParameterPort<Bool> { port(named: "inputText") }
    public var inputTextString: ParameterPort<String> { port(named: "inputTextString") }
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
        let compiler = MetalFileCompiler(watch: false)
        guard let shaderURL = Bundle.module.url(forResource: "TestCard", withExtension: "metal", subdirectory: "Compute"),
              let source = try? compiler.parse(shaderURL),
              let library = try? device.makeLibrary(source: source, options: nil),
              let function = library.makeFunction(name: "testCardGenerate")
        else { return }

        self.computePipeline = try? device.makeComputePipelineState(function: function)
    }

    // Must match TestCardFlags in TestCard.metal
    private struct TestCardFlags {
        var showBorder: UInt32
        var showGreys: UInt32
        var showDiagonals: UInt32
        var showCircle: UInt32
        var showGrid: UInt32
        var gridSpacing: UInt32
        var showText: UInt32
        var textX: UInt32
        var textY: UInt32
        var textW: UInt32
        var textH: UInt32
    }

    @ObservationIgnored private var cachedTextTexture: MTLTexture?
    @ObservationIgnored private var cachedTextString: String?
    @ObservationIgnored private var cachedTextOutputSize: (Int, Int)?

    private func textTexture(device: MTLDevice, text: String, outputWidth: Int, outputHeight: Int) -> MTLTexture?
    {
        let key = (outputWidth, outputHeight)
        if text == cachedTextString, key.0 == cachedTextOutputSize?.0, key.1 == cachedTextOutputSize?.1,
           let cached = cachedTextTexture { return cached }

        let fontSize = CGFloat(min(outputWidth, outputHeight)) * 0.08
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)

        let texW = Int(ceil(size.width))
        let texH = Int(ceil(size.height))
        guard texW > 0, texH > 0 else { return nil }

        guard let cgContext = CGContext(
            data: nil,
            width: texW,
            height: texH,
            bitsPerComponent: 8,
            bytesPerRow: texW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip for AppKit coordinate system
        cgContext.translateBy(x: 0, y: CGFloat(texH))
        cgContext.scaleBy(x: 1, y: -1)

        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        (text as NSString).draw(at: .zero, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: texW,
            height: texH,
            mipmapped: false
        )
        desc.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        texture.replace(
            region: MTLRegionMake2D(0, 0, texW, texH),
            mipmapLevel: 0,
            withBytes: cgContext.data!,
            bytesPerRow: texW * 4
        )

        cachedTextTexture = texture
        cachedTextString = text
        cachedTextOutputSize = key
        return texture
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let width = max(1, self.inputWidth.value ?? 1920)
        let height = max(1, self.inputHeight.value ?? 1080)

        guard let pipeline = self.computePipeline,
              let outImage = context.graphRenderer?.newImage(withWidth: width, height: height),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return }

        let showText = self.inputText.value ?? true
        let textString = self.inputTextString.value ?? "Fabric"
        let textTex = showText ? self.textTexture(device: context.graphRenderer!.context.device, text: textString, outputWidth: width, outputHeight: height) : nil
        let texW = UInt32(textTex?.width ?? 0)
        let texH = UInt32(textTex?.height ?? 0)
        let textX = (UInt32(width) - texW) / 2
        let textY = UInt32(height) * 2 / 3

        var flags = TestCardFlags(
            showBorder: (self.inputBorder.value ?? true) ? 1 : 0,
            showGreys: (self.inputGreys.value ?? true) ? 1 : 0,
            showDiagonals: (self.inputDiagonals.value ?? true) ? 1 : 0,
            showCircle: (self.inputCircle.value ?? true) ? 1 : 0,
            showGrid: (self.inputGrid.value ?? false) ? 1 : 0,
            gridSpacing: UInt32(max(2, self.inputGridSpacing.value ?? 100)),
            showText: (showText && textTex != nil) ? 1 : 0,
            textX: textX,
            textY: textY,
            textW: texW,
            textH: texH
        )

        computeEncoder.setComputePipelineState(pipeline)
        computeEncoder.setTexture(outImage.texture, index: 0)
        computeEncoder.setTexture(textTex, index: 1)
        computeEncoder.setBytes(&flags, length: MemoryLayout<TestCardFlags>.size, index: 0)

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
