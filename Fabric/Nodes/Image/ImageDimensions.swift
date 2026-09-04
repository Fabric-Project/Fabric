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

    public required init(context: Context)
    {
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyInputImage = try legacyContainer.decodeIfPresent(
            NodePort<FabricImage>.self,
            forKey: .inputTexturePort
        )
        let legacyResolution = try legacyContainer.decodeIfPresent(
            NodePort<simd_float2>.self,
            forKey: .outputResolutionPort
        )

        try super.init(from: decoder)

        if let legacyInputImage {
            self.removePort(self.inputImage)
            self.addDynamicPort(legacyInputImage, name: "inputImage")
        }

        if let legacyResolution {
            self.addDynamicPort(legacyResolution, name: "legacyOutputResolution")
        }
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
