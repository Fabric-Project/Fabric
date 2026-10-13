//
//  ImageDimensions.swift
//  Fabric
//
//  Created by Anton Marini on 10/15/25.
//

import Foundation
import Metal
import Satin
import simd

public final class ImageDimensions: Node
{
    override public class var name: String { "Image Dimensions" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String {
        "Returns an image's width and height in pixels."
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            (
                "inputImage",
                NodePort<FabricImage>(
                    name: "Image",
                    kind: .Inlet,
                    description: "Input image to measure"
                )
            ),
            (
                "outputWidth",
                NodePort<Float>(
                    name: "Width",
                    kind: .Outlet,
                    description: "Image width in pixels"
                )
            ),
            (
                "outputHeight",
                NodePort<Float>(
                    name: "Height",
                    kind: .Outlet,
                    description: "Image height in pixels"
                )
            ),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var outputWidth: NodePort<Float> { port(named: "outputWidth") }
    public var outputHeight: NodePort<Float> { port(named: "outputHeight") }

    private enum LegacyCodingKeys: String, CodingKey
    {
        case inputTexturePort
        case outputResolutionPort
    }

    /// The ports a document from before the registry saved as properties of
    /// their own, standing in for the declared Image inlet and adding the
    /// Resolution outlet that document had.
    private let legacyInputImage: NodePort<FabricImage>?
    private let legacyResolution: NodePort<simd_float2>?

    public required init(context: Context)
    {
        self.legacyInputImage = nil
        self.legacyResolution = nil
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        self.legacyInputImage = try legacyContainer.decodeIfPresent(
            NodePort<FabricImage>.self,
            forKey: .inputTexturePort
        )
        self.legacyResolution = try legacyContainer.decodeIfPresent(
            NodePort<simd_float2>.self,
            forKey: .outputResolutionPort
        )

        try super.init(from: decoder)
    }

    override public func declaredPorts() -> [PortDeclaration]
    {
        var declarations = super.declaredPorts()

        if let legacyInputImage,
           let index = declarations.firstIndex(where: { $0.registryKey == "inputImage" })
        {
            declarations[index] = PortDeclaration(registryKey: "inputImage", port: legacyInputImage)
        }

        if let legacyResolution
        {
            declarations.append(PortDeclaration(registryKey: "legacyOutputResolution", port: legacyResolution))
        }

        return declarations
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard self.inputImage.valueDidChange else { return }

        guard let image = self.inputImage.value else {
            self.outputWidth.send(nil)
            self.outputHeight.send(nil)
            self.legacyOutputResolution?.send(nil)
            return
        }

        let width = Float(image.presentationSize.width)
        let height = Float(image.presentationSize.height)

        self.outputWidth.send(width)
        self.outputHeight.send(height)
        self.legacyOutputResolution?.send(simd_float2(width, height))
    }

    private var legacyOutputResolution: NodePort<simd_float2>?
    {
        self.findPort(named: "legacyOutputResolution")
    }
}
