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
    public var inputTexture:NodePort<FabricImage> { port(named: "inputTexture") }
    public var inputDisplacementTexture:NodePort<FabricImage> { port(named: "inputDisplacementTexture") }
    public var inputPointSpriteTexture:NodePort<FabricImage> { port(named: "inputPointSpriteTexture") }
    public var inputAmount:ParameterPort<Float> { port(named: "Amount") }
    public var inputLumaVsRGBAmount:ParameterPort<Float> { port(named: "Luma Vs RGB") }
    public var inputMinPointSize:ParameterPort<Float> { port(named: "Min Point Size") }
    public var inputMaxPointSize:ParameterPort<Float> { port(named: "Max Point Size") }
    public var inputBrightness:ParameterPort<Float> { port(named: "Brightness") }
    
    
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
        self.addMaterialParameterPorts()
    }

    public required init(from decoder: any Decoder) throws {
        guard let context = decoder.context?.documentContext as? Context else { fatalError("Invalid Context") }

        self._material = Self.makeMaterial(context: context)
        try super.init(from: decoder)
        self.addMaterialParameterPorts()
    }

    private func addMaterialParameterPorts() {
        // Only shader-authored controls become ports; texture transforms stay internal.
        // The port wraps the material's parameter directly, including during hydration.
        let inheritedPorts = self.ports.filter { $0.parameter != nil || $0.kind == .Outlet }
        for parameter in self.material.parameters.params where parameter.controlType != .none {
            if let port = PortType.portForType(from: parameter) {
                self.addDynamicPort(port)
            }
        }
        self.reorderPorts(self.ports.filter { port in
            !inheritedPorts.contains(where: { $0.id == port.id })
        } + inheritedPorts)
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
