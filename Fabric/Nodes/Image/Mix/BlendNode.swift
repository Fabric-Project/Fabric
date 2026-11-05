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

    /// BaseImageNode derives a name from its shader file; Blend is always "Blend"
    /// (unless the user renames it, which `userName` handles in the base class).
    override public func deriveSubtitle() -> String? { nil }

    override public class var defaultImageInputCountHint: Int? { 2 }

    /// The first mode's shader, which a document without a saved file opens with.
    override public class var sourceShaderURL: URL? {
        Bundle.module.url(forResource: "Additive", withExtension: "metal", subdirectory: "EffectsTwoChannel/Mix")
    }

    required init(context: Context) {
        guard let url = Bundle.module.url(forResource: "Additive", withExtension: "metal", subdirectory: "EffectsTwoChannel/Mix") else
        {
            fatalError("Missing bundled Additive blend shader.")
        }

        do
        {
            try super.init(context: context, fileURL: url)
        }
        catch
        {
            fatalError("Could not initialize Blend node: \(error.localizedDescription)")
        }
    }

    public override class func initWithContext(context: Context) throws -> Node {
        guard let url = Bundle.module.url(forResource: "Additive", withExtension: "metal", subdirectory: "EffectsTwoChannel/Mix") else
        {
            throw FabricError(.loading(.resourceNotFound),
                              severity: .fatal,
                              message: "Missing bundled Additive blend shader.")
        }

        return try Self(context: context, fileURL: url)
    }

    required init(context: Context, fileURL: URL) throws {
        try super.init(context: context, fileURL: fileURL)
    }

    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
        // The shader follows the saved Mode, not a saved file.
        if let modeName = self.inputMode.value, let url = self.shaderURL(for: modeName) {
            self.loadShader(at: url, as: url)
        }
    }

    /// The shader follows the Mode inlet, which can be wired, so Blend has no
    /// file setting: the file is not the node's to set.
    override public var settings: (any NodeSettings)? { nil }

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

    // Ports
    public let inputMode = ParameterPort(parameter: StringParameter("Mode", "Additive", modeNames, .dropdown, "Blend mode"))

    override public func fixedPortDeclarations() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "Mode", port: self.inputMode),
        ] + super.fixedPortDeclarations()
    }

    private func shaderURL(for modeName: String) -> URL? {
        Bundle.module.url(forResource: modeName, withExtension: "metal", subdirectory: "EffectsTwoChannel/Mix")
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        if self.inputMode.valueDidChange,
           let modeName = self.inputMode.value,
           let url = self.shaderURL(for: modeName)
        {
            // A reload of a template every mode shares: no settings change, and
            // the ports stay as they are.
            self.loadShader(at: url, as: url)
        }

        try super.execute(renderer: renderer, executionInfo: executionInfo, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }
}
