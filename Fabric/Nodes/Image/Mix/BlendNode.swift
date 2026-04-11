//
//  BlendNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import simd
import Metal

public class BlendNode: BaseImageNode
{
    override public class var name: String { "Blend" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Mix) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Blend two images using a selectable blend mode" }

    override public class var defaultImageInputCountHint: Int? { 2 }

    required init(context: Context) {
        let url = Bundle.module.url(forResource: "Additive", withExtension: "metal", subdirectory: "EffectsTwoChannel/Mix")!
        try! super.init(context: context, fileURL: url)
    }

    required init(context: Context, fileURL: URL) throws {
        try super.init(context: context, fileURL: fileURL)
    }

    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }

    private static let modeNames: [String] = [
        "Additive",
        "Average",
        "Color",
        "Color Burn",
        "Color Dodge",
        "Darken",
        "Difference",
        "Exclusion",
        "Glow",
        "Hard Light",
        "Hard Mix",
        "Hue",
        "Lighten",
        "Linear Burn",
        "Linear Dodge",
        "Linear Light",
        "Luminosity",
        "Multiply",
        "Negation",
        "Overlay",
        "Phoenix",
        "Pin Light",
        "Reflect",
        "Saturation",
        "Screen",
        "Soft Light",
        "Subtract",
        "Vivid Light",
    ]

    override public var materialSyncExcludedLabels: Set<String> { ["Mode"] }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return [
            ("Mode", ParameterPort(parameter: StringParameter("Mode", "Additive", modeNames, .dropdown, "Blend mode"))),
        ] + ports
    }

    // Port Proxy
    public var inputMode: ParameterPort<String> { port(named: "Mode") }

    private func shaderURL(for modeName: String) -> URL? {
        Bundle.module.url(forResource: modeName, withExtension: "metal", subdirectory: "EffectsTwoChannel/Mix")
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputMode.valueDidChange,
           let modeName = self.inputMode.value,
           let url = self.shaderURL(for: modeName)
        {
            if let sourceShader = self.postMaterial.shader as? SourceShader {
                sourceShader.pipelineURL = url
                sourceShader.reloadFromSource()
            }
        }

        super.execute(context: context, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }
}
