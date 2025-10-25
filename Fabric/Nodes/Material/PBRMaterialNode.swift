//
//  StandardMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/29/25.
//

import Foundation
import Satin
import simd
import Metal

public class PBRMaterialNode : StandardMaterialNode
{
    override public class var name:String {  "Advanced Physical Material" }
    override public class var nodeDescription: String { "Provides a Advanced Physically Based Rendering Material supporting PBR rendering like Diffuse, Normal, Specular, Metallic, Clear Coat, Sheen, Transmission, IOR Images and Properties."}

    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputBumpTexture", NodePort<EquatableTexture>(name: "Bump Texture", kind: .Inlet)),
            ("inputDisplacementTexture", NodePort<EquatableTexture>(name: "Displacement Texture", kind: .Inlet)),
            ("inputOcclusionTexture", NodePort<EquatableTexture>(name: "Occlusion Texture", kind: .Inlet)),
            ("inputSubsurfaceTexture", NodePort<EquatableTexture>(name: "Subsurface Texture", kind: .Inlet)),
            ("inputClearcoatTexture", NodePort<EquatableTexture>(name: "Clearcoat Texture", kind: .Inlet)),
            ("inputClearcoatRoughTexture", NodePort<EquatableTexture>(name: "Clearcoat Roughness Texture", kind: .Inlet)),
            ("inputClearcoatGlossTexture", NodePort<EquatableTexture>(name: "Clearcoat Gloss Texture", kind: .Inlet)),
            ("inputTransmissionTexture", NodePort<EquatableTexture>(name: "Transmission Texture", kind: .Inlet)),
            ("inputSubsurface", ParameterPort(parameter:FloatParameter("Sub Surface", 0.0, 0.0, 1.0, .slider))),
            ("inputAnisotropic", ParameterPort(parameter:FloatParameter("Anisotropic", 0.0, -1.0, 1.0, .slider))),
            ("inputAnisotropicAngle", ParameterPort(parameter:FloatParameter("Anisotropic Angle", 0.0, -1.0, 1.0, .slider))),
            ("inputSpecularTint", ParameterPort(parameter:FloatParameter("Specular Tint", 0.0, 0.0, 1.0, .slider))),
            ("inputClearcoat", ParameterPort(parameter:FloatParameter("Clearcoat", 0.0, 0.0, 1.0, .slider))),
            ("inputClearcoatRoughness", ParameterPort(parameter:FloatParameter("Clearcoat Roughness", 0.0, 0.0, 1.0, .slider))),
            ("inputSheen", ParameterPort(parameter:FloatParameter("Sheen", 0.0, 0.0, 1.0, .slider))),
            ("inputSheenTint", ParameterPort(parameter:FloatParameter("Sheen Tint", 0.0, 0.0, 1.0, .slider))),
            ("inputTransmission", ParameterPort(parameter:FloatParameter("Transmission", 0.0, 0.0, 1.0, .slider))),
            ("inputThickness", ParameterPort(parameter:FloatParameter("Thickness", 1.0, 0.0, 5.0, .slider))),
            ("inputIOR", ParameterPort(parameter:FloatParameter("Index of Refraction", 1.5, 0.0, 3.0, .slider))),
        ]
    }

    // Port Proxys
    var inputBumpTexture: NodePort<EquatableTexture> { port(named: "inputBumpTexture") }
    var inputDisplacementTexture: NodePort<EquatableTexture> { port(named: "inputDisplacementTexture") }
    var inputOcclusionTexture: NodePort<EquatableTexture> { port(named: "inputOcclusionTexture") }
    var inputSubsurfaceTexture: NodePort<EquatableTexture> { port(named: "inputSubsurfaceTexture") }
    var inputClearcoatTexture: NodePort<EquatableTexture> { port(named: "inputClearcoatTexture") }
    var inputClearcoatRoughTexture: NodePort<EquatableTexture> { port(named: "inputClearcoatRoughTexture") }
    var inputClearcoatGlossTexture: NodePort<EquatableTexture> { port(named: "inputClearcoatGlossTexture") }
    var inputTransmissionTexture: NodePort<EquatableTexture> { port(named: "inputTransmissionTexture") }
    var inputSubsurface: ParameterPort<Float> { port(named: "inputSubsurface") }
    var inputAnisotropic: ParameterPort<Float> { port(named: "inputAnisotropic") }
    var inputAnisotropicAngle: ParameterPort<Float> { port(named: "inputAnisotropicAngle") }
    var inputSpecularTint: ParameterPort<Float> { port(named: "inputSpecularTint") }
    var inputClearcoat: ParameterPort<Float> { port(named: "inputClearcoat") }
    var inputClearcoatRoughness: ParameterPort<Float>  { port(named: "inputClearcoatRoughness") }
    var inputSheen: ParameterPort<Float> { port(named: "inputSheen") }
    var inputSheenTint: ParameterPort<Float> { port(named: "inputSheenTint") }
    var inputTransmission: ParameterPort<Float> { port(named: "inputTransmission") }
    var inputThickness: ParameterPort<Float> { port(named: "inputThickness") }
    var inputIOR: ParameterPort<Float> { port(named: "inputIOR") }
    
    override public var material: PhysicalMaterial {
        return _material
    }
    
    private var _material = PhysicalMaterial()

    override public func evaluate(material: Material, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
                
        if self.inputSubsurface.valueDidChange,
           let inputSubsurface = self.inputSubsurface.value
        {
            self.material.subsurface = inputSubsurface
            shouldOutput = true
        }
        
        if self.inputAnisotropic.valueDidChange,
           let inputAnisotropic = self.inputAnisotropic.value
        {
            self.material.anisotropic = inputAnisotropic
            shouldOutput = true
        }
        
        if self.inputAnisotropicAngle.valueDidChange,
           let inputAnisotropicAngle = self.inputAnisotropicAngle.value
        {
            self.material.anisotropicAngle = inputAnisotropicAngle
            shouldOutput = true
        }
        
        if self.inputSpecularTint.valueDidChange,
           let inputSpecularTint = self.inputSpecularTint.value
        {
            self.material.specularTint = inputSpecularTint
            shouldOutput = true
        }
        
        if self.inputClearcoat.valueDidChange,
           let inputClearcoat = self.inputClearcoat.value
        {
            self.material.clearcoat = inputClearcoat
            shouldOutput = true
        }
        
        if self.inputClearcoatRoughness.valueDidChange,
           let inputClearcoatRoughness = self.inputClearcoatRoughness.value
        {
            self.material.clearcoatRoughness = inputClearcoatRoughness
            shouldOutput = true
        }
        
        if self.inputSheen.valueDidChange,
           let inputSheen = self.inputSheen.value
        {
            self.material.sheen = inputSheen
            shouldOutput = true
        }
        
        if self.inputSheenTint.valueDidChange,
           let inputSheenTint = self.inputSheenTint.value
        {
            self.material.sheenTint = inputSheenTint
            shouldOutput = true
        }
        
        if self.inputTransmission.valueDidChange,
           let inputTransmission = self.inputTransmission.value
        {
            self.material.transmission = inputTransmission
            shouldOutput = true
        }
        
        if self.inputOcclusion.valueDidChange,
           let inputOcclusion = self.inputOcclusion.value
        {
            self.material.occlusion = inputOcclusion
            shouldOutput = true
        }
        
        if self.inputThickness.valueDidChange,
           let inputThickness = self.inputThickness.value
        {
            self.material.thickness = inputThickness
            shouldOutput = true
        }
        
        if self.inputIOR.valueDidChange,
           let inputIOR = self.inputIOR.value
        {
            self.material.ior = inputIOR
            shouldOutput = true
        }
        
        if self.inputBumpTexture.valueDidChange
        {
            self.material.setTexture(self.inputBumpTexture.value?.texture, type: .bump)
            shouldOutput = true
        }
        
        if self.inputDisplacementTexture.valueDidChange
        {
            self.material.setTexture(self.inputDisplacementTexture.value?.texture, type: .displacement)
            shouldOutput = true
        }
        
        if self.inputOcclusionTexture.valueDidChange
        {
            self.material.setTexture(self.inputOcclusionTexture.value?.texture, type: .occlusion)
            shouldOutput = true
        }
        
        if self.inputSubsurfaceTexture.valueDidChange
        {
            self.material.setTexture(self.inputSubsurfaceTexture.value?.texture, type: .subsurface)
            shouldOutput = true
        }
        
        if self.inputClearcoatTexture.valueDidChange
        {
            self.material.setTexture(self.inputClearcoatTexture.value?.texture, type: .clearcoat)
            shouldOutput = true
        }
        
        if self.inputClearcoatRoughTexture.valueDidChange
        {
            self.material.setTexture(self.inputClearcoatRoughTexture.value?.texture, type: .clearcoatRoughness)
            shouldOutput = true
        }
        
        if self.inputClearcoatGlossTexture.valueDidChange
        {
            self.material.setTexture(self.inputClearcoatGlossTexture.value?.texture, type: .clearcoatGloss)
            shouldOutput = true
        }
        
        if self.inputTransmissionTexture.valueDidChange
        {
            self.material.setTexture(self.inputTransmissionTexture.value?.texture, type: .transmission)
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
