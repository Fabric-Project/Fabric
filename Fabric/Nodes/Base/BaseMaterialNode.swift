//
//  BaseMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal
import SwiftUI

/// How a material shapes the points it draws. Meshes of triangles drawn with the material are
/// unaffected, so one material serves both.
public enum MaterialPointSprite: String, CaseIterable, Codable, Sendable
{
    /// No material-level point sprite controls.
    case none = "None"
    /// Square points, as the GPU draws them.
    case square = "Square"
    /// Round points with a soft edge: adds a Point Softness input.
    case disc = "Disc"
    /// Each point shows an image: adds a Point Sprite Image input.
    case image = "Image"

    var satinPointSprite: Satin.PointSprite
    {
        switch self
        {
        case .none, .square: return .square
        case .disc: return .disc
        case .image: return .texture
        }
    }
}

/// The settings every material node shares.
public struct MaterialSettings: NodeSettings
{
    public var pointSprite: MaterialPointSprite

    public init(pointSprite: MaterialPointSprite)
    {
        self.pointSprite = pointSprite
    }

    private enum CodingKeys: String, CodingKey
    {
        case pointSprite = "materialPointSprite"
    }
}

public class BaseMaterialNode : Node
{
    override public class var name:String {  "Material" }
    override public class var nodeType:Node.NodeType { .Material }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Base class for material nodes" }

    // Port Registration
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputReceivesLighting", ParameterPort(parameter:BoolParameter("Receives Lighting", true, .button, "When enabled, the material responds to scene lighting") ) ),
            ("inputWriteDepth", ParameterPort(parameter:BoolParameter("Write Depth", true, .button, "When enabled, writes depth values to the depth buffer") ) ),
            ("inputDepthTest", ParameterPort(parameter:BoolParameter("Depth Test", true, .button, "When enabled, performs depth testing against existing geometry") ) ),
            ("inputBlending", ParameterPort(parameter:StringParameter("Blending Mode", "Disabled", ["Disabled", "Alpha", "Additive", "Subtractive"], .dropdown, "Blending mode for combining with background pixels") ) ),
            ("outputMaterial",  NodePort<Satin.Material>(name: "Material", kind: .Outlet, description: "The configured material")),
        ]
    }
    
    // Port Proxy
    public var inputReceivesLighting:ParameterPort<Bool>    { port(named: "inputReceivesLighting") }
    public var inputWriteDepth:ParameterPort<Bool>          { port(named: "inputWriteDepth") }
    public var inputDepthTest:ParameterPort<Bool>           { port(named: "inputDepthTest") }
    public var inputBlending:ParameterPort<String>          { port(named: "inputBlending") }
    public var outputMaterial:NodePort<Satin.Material>            { port(named: "outputMaterial") }
    
    open var material: Satin.Material {
        fatalError("Subclasses must override material")
    }

    // MARK: - Point Sprite

    /// How the material shapes points. It changes which inputs the node has, so it is a setting.
    public private(set) var pointSprite: MaterialPointSprite = .none
    {
        didSet
        {
            guard pointSprite != oldValue else { return }
            rebuildPointSpritePorts()
            pointSpriteNeedsApply = true
            markDirty()
            subtitleSubject.send()
            performOnMainAsync { [weak self] in self?._materialSettingsModelStorage?.refreshFromNode() }
        }
    }

    /// The material hasn't taken `pointSprite` yet: applied on the next execution, once the
    /// subclass's material exists.
    private var pointSpriteNeedsApply = true
    // Resolved when the point sprite changes, so execution looks up nothing.
    /// Present only while point sprites are enabled.
    public private(set) var inputPointSize: ParameterPort<Float>?
    private var pointSpriteSoftnessPort: ParameterPort<Float>?
    private var pointSpriteImagePort: NodePort<FabricImage>?

    private static let pointSizeName = "inputPointSize"
    private static let pointSpriteSoftnessName = "inputPointSpriteSoftness"
    private static let pointSpriteImageName = "inputPointSpriteImage"

    override public var settings: (any NodeSettings)? { MaterialSettings(pointSprite: pointSprite) }

    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? MaterialSettings else { return }
        pointSprite = settings.pointSprite
        super.apply(settings)
    }

    public required init(context: Context)
    {
        super.init(context: context)
        rebuildPointSpritePorts()
    }

    /// A material node whose points are shaped by `settings` from the start.
    public convenience init(context: Context, settings: MaterialSettings)
    {
        self.init(context: context)
        setSettings(settings)
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        // Observers don't run in an initializer: rebuild here, so a saved sprite input finds its
        // saved port by registry key.
        pointSprite = (try? MaterialSettings(from: decoder))?.pointSprite ?? .none
        rebuildPointSpritePorts()
    }

    /// Keep size and mode-specific controls together after the other inputs.
    private func rebuildPointSpritePorts()
    {
        let existingSize: Port? = findPort(named: Self.pointSizeName)
        if pointSprite == .none, let existingSize { removePort(existingSize) }
        if pointSprite != .none, existingSize == nil
        {
            addDynamicPort(ParameterPort(parameter: FloatParameter("Point Size", 1.0, 0.5, 64.0, .slider,
                                                                   "Size of each point in pixels")),
                           name: Self.pointSizeName)
        }
        inputPointSize = findPort(named: Self.pointSizeName)

        let existingSoftness: Port? = findPort(named: Self.pointSpriteSoftnessName)
        let existingImage: Port? = findPort(named: Self.pointSpriteImageName)

        if pointSprite != .disc, let existingSoftness { removePort(existingSoftness) }
        if pointSprite != .image, let existingImage { removePort(existingImage) }

        if pointSprite == .disc, existingSoftness == nil
        {
            addDynamicPort(ParameterPort(parameter: FloatParameter("Point Softness", 0.1, 0.0, 1.0, .slider,
                                                                   "How much of each point's radius fades out at its edge")),
                           name: Self.pointSpriteSoftnessName)
        }
        if pointSprite == .image, existingImage == nil
        {
            addDynamicPort(NodePort<FabricImage>(name: "Point Sprite Image", kind: .Inlet, description: "The image each point shows"),
                           name: Self.pointSpriteImageName)
        }

        pointSpriteSoftnessPort = findPort(named: Self.pointSpriteSoftnessName)
        pointSpriteImagePort = findPort(named: Self.pointSpriteImageName)

        let spritePorts: [Port] = [inputPointSize, pointSpriteSoftnessPort, pointSpriteImagePort].compactMap { $0 }
        let otherInlets = ports.filter { port in port.kind == .Inlet && !spritePorts.contains { $0 === port } }
        let outlets = ports.filter { $0.kind == .Outlet }
        reorderPorts(otherInlets + spritePorts + outlets)
    }

    override public func deriveSubtitle() -> String?
    {
        pointSprite == .none ? nil : "\(pointSprite.rawValue) Points"
    }

    /// Gives the material the point sprite, and whatever of its inputs changed.
    private func evaluatePointSprite(material: Satin.Material) -> Bool
    {
        var changed = false
        if pointSpriteNeedsApply
        {
            pointSpriteNeedsApply = false
            material.pointSprite = pointSprite.satinPointSprite
            if pointSprite == .none { material.set("Point Size", Float(1.0)) }
            if pointSprite != .image
            {
                material.pointSpriteTexture = nil
                material.pointSpriteTextureTransform = matrix_identity_float4x4
            }
            changed = true
        }
        if let inputPointSize, inputPointSize.valueDidChange || changed
        {
            material.set("Point Size", inputPointSize.value ?? 1.0)
            changed = true
        }
        if let pointSpriteSoftnessPort, pointSpriteSoftnessPort.valueDidChange || changed
        {
            material.pointSpriteSoftness = pointSpriteSoftnessPort.value ?? 0.1
            changed = true
        }
        if let pointSpriteImagePort, pointSpriteImagePort.valueDidChange || changed
        {
            material.pointSpriteTexture = pointSpriteImagePort.value?.texture
            material.pointSpriteTextureTransform = pointSpriteImagePort.value?.textureTransform ?? matrix_identity_float4x4
            changed = true
        }
        return changed
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    override public var settingsSize: SettingsViewSize { .Mini }

    override public func settingsView() -> AnyView
    {
        performOnMainSync { AnyView(MaterialSettingsView(model: materialSettingsModel)) }
    }

    @MainActor
    @Observable final class SettingsModel
    {
        var pointSprite: MaterialPointSprite
        {
            didSet
            {
                guard let node, pointSprite != node.pointSprite else { return }
                node.setSettings(MaterialSettings(pointSprite: pointSprite))
            }
        }

        private weak var node: BaseMaterialNode?

        init(node: BaseMaterialNode)
        {
            self.node = node
            self.pointSprite = node.pointSprite
        }

        func refreshFromNode()
        {
            guard let node, pointSprite != node.pointSprite else { return }
            pointSprite = node.pointSprite
        }
    }

    /// Nil until a settings view asks for it.
    private var _materialSettingsModelStorage: SettingsModel?

    var materialSettingsModel: SettingsModel
    {
        performOnMainSync
        {
            if let model = _materialSettingsModelStorage { return model }
            let model = SettingsModel(node: self)
            _materialSettingsModelStorage = model
            return model
        }
    }
        
    public func evaluate(material:Satin.Material, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = false
        
        if self.inputBlending.valueDidChange
        {
            material.blending = self.blendingMode()
            shouldOutput = true
        }
        
        if self.inputReceivesLighting.valueDidChange,
           let lighting = self.inputReceivesLighting.value
        {
            material.lighting = lighting
            shouldOutput = true
        }
        
        if  self.inputWriteDepth.valueDidChange,
            let depthWrite = self.inputWriteDepth.value
        {
            material.depthWriteEnabled = depthWrite
            shouldOutput = true
        }
        
        if self.inputDepthTest.valueDidChange,
           let depthTest = self.inputDepthTest.value
        {
            material.depthCompareFunction = (depthTest) ? .greaterEqual : .always
            shouldOutput = true
        }
        
        if self.evaluatePointSprite(material: material)
        {
            shouldOutput = true
        }

        // We use this for disconnect / reconnect logic...
        // Maybe this needs to go into a super call? :X
        if self.isDirty
        {
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    public override func execute(renderer:GraphRenderer, executionInfo:GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        let shouldOutput = self.evaluate(material: self.material, atTime: executionInfo.timing.time)

        if shouldOutput
        {
            self.outputMaterial.send(self.material)
        }
     }
    
    private func blendingMode() -> Blending
    {
        switch self.inputBlending.value
        {
        case "Disabled":
            return .disabled
            
        case "Alpha":
            return .alpha

        case "Additive":
            return .additive
            
        case "Subtractive":
            return .subtract

        default: return .subtract
        }
    }
}

/// The material settings: how points are shaped.
struct MaterialSettingsView: View
{
    @Bindable var model: BaseMaterialNode.SettingsModel

    var body: some View
    {
        Picker("Point Sprite", selection: $model.pointSprite)
        {
            ForEach(MaterialPointSprite.allCases, id: \.self) { sprite in
                Text(sprite.rawValue).tag(sprite)
            }
        }
        .help("How the material shapes points. None hides point sprite controls; Square draws them as the GPU does; Disc rounds them; Image shows an image on each. Meshes of triangles are unaffected.")
    }
}
