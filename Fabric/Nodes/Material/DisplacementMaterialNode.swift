//
//  DisplacementMaterial.swift
//  Fabric
//
//  Created by Anton Marini on 7/4/25.
//

import Foundation
import Satin
import simd
import Metal

public class DisplacementMaterialNode: BaseMaterialNode
{
    public class DisplacementMaterial : SourceMaterial { }
    
    public override class var name:String {  "Displacement Material" }
    override public class var nodeDescription: String { "Displace Geometry using an Images luminance or rgb values."}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return [
            ("inputTexture", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Color texture to apply to displaced geometry")),
            ("inputDisplacementTexture", NodePort<FabricImage>(name: "Displacement Image", kind: .Inlet, description: "Grayscale image for vertex displacement")),
            ("inputPointSpriteTexture", NodePort<FabricImage>(name: "Point Sprite Image", kind: .Inlet, description: "Texture for point sprite rendering")),
        ] + ports
    }

    // Proxy Params
    public var inputTexture: NodePort<FabricImage> { _inputTexture }
    private var _inputTexture: NodePort<FabricImage>!
    public var inputDisplacementTexture: NodePort<FabricImage> { _inputDisplacementTexture }
    private var _inputDisplacementTexture: NodePort<FabricImage>!
    public var inputPointSpriteTexture: NodePort<FabricImage> { _inputPointSpriteTexture }
    private var _inputPointSpriteTexture: NodePort<FabricImage>!
    public var inputAmount: ParameterPort<Float> { _inputAmount }
    private var _inputAmount: ParameterPort<Float>!
    public var inputLumaVsRGBAmount: ParameterPort<Float> { _inputLumaVsRGBAmount }
    private var _inputLumaVsRGBAmount: ParameterPort<Float>!
    public var inputMinPointSize: ParameterPort<Float> { _inputMinPointSize }
    private var _inputMinPointSize: ParameterPort<Float>!
    public var inputMaxPointSize: ParameterPort<Float> { _inputMaxPointSize }
    private var _inputMaxPointSize: ParameterPort<Float>!
    public var inputBrightness: ParameterPort<Float> { _inputBrightness }
    private var _inputBrightness: ParameterPort<Float>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputTexture = findPort(named: "inputTexture")
        self._inputDisplacementTexture = findPort(named: "inputDisplacementTexture")
        self._inputPointSpriteTexture = findPort(named: "inputPointSpriteTexture")
        self._inputAmount = findPort(named: "Amount")
        self._inputLumaVsRGBAmount = findPort(named: "Luma Vs RGB")
        self._inputMinPointSize = findPort(named: "Min Point Size")
        self._inputMaxPointSize = findPort(named: "Max Point Size")
        self._inputBrightness = findPort(named: "Brightness")
    }
    
    
    public override var material: DisplacementMaterial {
        return _material
    }
    
    private let _material: DisplacementMaterial

    private static func makeMaterial(context: Context) -> DisplacementMaterial {
        guard let shaderURL = Bundle.module.url(forResource: "DisplacementMaterial", withExtension: "metal", subdirectory: "Materials") else {
            fatalError("Missing bundled DisplacementMaterial shader.")
        }

        let material = DisplacementMaterial(context: context, pipelineURL: shaderURL)
        // Populate the fixed shader parameters before ports are created or hydrated.
        material.setupShader()
        material.set("Displacement Texture Transform", matrix_identity_float4x4)
        material.set("Color Texture Transform", matrix_identity_float4x4)
        material.set("Point Sprite Texture Transform", matrix_identity_float4x4)
        return material
    }

    required public init(context: Context) {
        self._material = Self.makeMaterial(context: context)
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws {
        guard let context = decoder.context?.documentContext as? Context else { fatalError("Invalid Context") }

        self._material = Self.makeMaterial(context: context)
        try super.init(from: decoder)
    }

    /// The image inlets, then the shader's controls, then the inherited
    /// parameters and the outlet. Only shader-authored controls become ports;
    /// texture transforms stay internal. Each port wraps the material's
    /// parameter directly, hydration included.
    override public func declaredPorts() -> [PortDeclaration] {
        let inherited = super.declaredPorts()
        let isMaterialSetting: (PortDeclaration) -> Bool = { $0.control != nil || $0.kind == .Outlet }
        let controls = self._material.parameters.params
            .filter { $0.controlType != .none }
            .compactMap { parameter in PortType.port(for: parameter).map { PortDeclaration(key: $0.name, port: $0) } }

        return inherited.filter { !isMaterialSetting($0) } + controls + inherited.filter(isMaterialSetting)
    }

    override public func evaluate(material: Material, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
        
        if self.inputDisplacementTexture.valueDidChange || self.inputTexture.valueDidChange
        {
            let displacementImage = self.inputDisplacementTexture.value ?? self.inputTexture.value
            self.material.set(displacementImage?.texture, index: VertexTextureIndex.Custom0)
            self.material.set("Displacement Texture Transform",
                              displacementImage?.textureTransform ?? matrix_identity_float4x4)
            shouldOutput = true
        }
        
        if self.inputTexture.valueDidChange
        {
            let image = self.inputTexture.value
            self.material.set(image?.texture, index: FragmentTextureIndex.Custom0)
            self.material.set("Color Texture Transform",
                              image?.textureTransform ?? matrix_identity_float4x4)
            shouldOutput = true
        }
        
        if self.inputPointSpriteTexture.valueDidChange
        {
            let image = self.inputPointSpriteTexture.value
            self.material.set(image?.texture, index: FragmentTextureIndex.Custom1)
            self.material.set("Point Sprite Texture Transform",
                              image?.textureTransform ?? matrix_identity_float4x4)
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
