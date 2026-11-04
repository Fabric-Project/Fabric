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

    public let inputWidth = ParameterPort(parameter: IntParameter("Width", 1920, 1, 8192, .inputfield, "Output image width in pixels"))
    public let inputHeight = ParameterPort(parameter: IntParameter("Height", 1080, 1, 8192, .inputfield, "Output image height in pixels"))
    public let inputBorder = ParameterPort(parameter: BoolParameter("Border", true, .toggle, "Show 1px border with black inset"))
    public let inputGreys = ParameterPort(parameter: BoolParameter("Greys", true, .toggle, "Show 5×2 greyscale gradient cells"))
    public let inputDiagonals = ParameterPort(parameter: BoolParameter("Diagonals", true, .toggle, "Show corner-to-corner diagonal lines"))
    public let inputCircle = ParameterPort(parameter: BoolParameter("Circle", true, .toggle, "Show centred circle"))
    public let inputGrid = ParameterPort(parameter: BoolParameter("Grid", true, .toggle, "Show 1px grid lines"))
    public let inputGridSpacing = ParameterPort(parameter: IntParameter("Grid Spacing", 40, 2, 4096, .inputfield, "Grid line spacing in pixels"))
    public let inputText = ParameterPort(parameter: BoolParameter("Text", true, .toggle, "Show centred text label"))
    public let inputTextString = ParameterPort(parameter: StringParameter("Label", "Fabric", .inputfield, "Text to display on the test card"))
    public let outputTexturePort = NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Generated test card image")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputWidth", port: self.inputWidth),
            PortDeclaration(key: "inputHeight", port: self.inputHeight),
            PortDeclaration(key: "inputBorder", port: self.inputBorder),
            PortDeclaration(key: "inputGreys", port: self.inputGreys),
            PortDeclaration(key: "inputDiagonals", port: self.inputDiagonals),
            PortDeclaration(key: "inputCircle", port: self.inputCircle),
            PortDeclaration(key: "inputGrid", port: self.inputGrid),
            PortDeclaration(key: "inputGridSpacing", port: self.inputGridSpacing),
            PortDeclaration(key: "inputText", port: self.inputText),
            PortDeclaration(key: "inputTextString", port: self.inputTextString),
            PortDeclaration(key: "outputTexturePort", port: self.outputTexturePort),
        ]
    }

    private var computePipeline: MTLComputePipelineState?

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

    private var cachedTextTexture: MTLTexture?
    private var cachedTextString: String?
    private var cachedTextOutputSize: (Int, Int)?

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

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let width = max(1, self.inputWidth.value ?? 1920)
        let height = max(1, self.inputHeight.value ?? 1080)

        guard let pipeline = self.computePipeline else
        {
            throw FabricError(.execution(.gpu),
                              severity: .recoverable,
                              message: "Test Card compute pipeline is unavailable")
        }

        let outImage = try renderer.newImage(withWidth: width, height: height)

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu),
                              severity: .recoverable,
                              message: "Could not create Test Card compute encoder")
        }

        let showText = self.inputText.value ?? true
        let textString = self.inputTextString.value ?? "Fabric"
        let textTex = showText ? self.textTexture(device: renderer.context.device, text: textString, outputWidth: width, outputHeight: height) : nil
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
