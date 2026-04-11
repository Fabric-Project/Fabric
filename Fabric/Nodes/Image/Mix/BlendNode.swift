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

    override public class var sourceShaderName: String { "BlendShader" }
    override public class var defaultImageInputCountHint: Int? { 2 }

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

    private static let modeMap: [String: Float] = {
        var map = [String: Float]()
        for (index, name) in modeNames.enumerated() {
            map[name] = Float(index)
        }
        return map
    }()

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

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputMode.valueDidChange,
           let modeName = self.inputMode.value,
           let modeValue = Self.modeMap[modeName]
        {
            if let modeParam = self.postMaterial.parameters.params.first(where: { $0.label == "Mode" }) as? FloatParameter {
                modeParam.value = modeValue
            }
        }

        super.execute(context: context, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }
}
