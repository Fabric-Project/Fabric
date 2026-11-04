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

    public let inputImage = NodePort<FabricImage>(
        name: "Image",
        kind: .Inlet,
        description: "Input image to measure"
    )
    public let outputWidth = NodePort<Float>(
        name: "Width",
        kind: .Outlet,
        description: "Image width in pixels"
    )
    public let outputHeight = NodePort<Float>(
        name: "Height",
        kind: .Outlet,
        description: "Image height in pixels"
    )

    override public func bindPorts()
    {
        super.bindPorts()
        self.legacyOutputResolution = findPort(named: "legacyOutputResolution")
    }

    private enum CodingKeys: String, CodingKey
    {
        case legacyOutputResolution
    }

    /// Whether this node came from a document old enough to have had a
    /// Resolution outlet, which it keeps so that document's wires to it hold.
    private let hasLegacyResolution: Bool

    public required init(context: Context)
    {
        self.hasLegacyResolution = false
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hasLegacyResolution = try container.decodeIfPresent(Bool.self, forKey: .legacyOutputResolution) ?? false

        try super.init(from: decoder)
    }

    override public func encode(to encoder: any Encoder) throws
    {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        if self.hasLegacyResolution { try container.encode(true, forKey: .legacyOutputResolution) }
    }

    override public func declaredPorts() -> [PortDeclaration]
    {
        let storedPorts = [
            PortDeclaration(key: "inputImage", port: self.inputImage),
            PortDeclaration(key: "outputWidth", port: self.outputWidth),
            PortDeclaration(key: "outputHeight", port: self.outputHeight),
        ]

        guard hasLegacyResolution else { return super.declaredPorts() + storedPorts }
        return super.declaredPorts() + storedPorts + [
            PortDeclaration(key: "legacyOutputResolution", port: NodePort<simd_float2>(name: "Resolution", kind: .Outlet)),
        ]
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
}
