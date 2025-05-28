//
//  MeshNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import simd
import Metal

class MeshNode : BaseObjectNode, NodeProtocol
{
    class var name:String { "Mesh" }
    class var nodeType:Node.NodeType  { .Mesh }

    // Params
    let inputCastsShadow:BoolParameter
    let inputDoubleSided:BoolParameter
    let inputCullingMode:StringParameter
    
    override var inputParameters: [any Parameter] { super.inputParameters + [
        self.inputCastsShadow,
        self.inputDoubleSided,
        self.inputCullingMode
    ] }

    // Ports
    let inputGeometry:NodePort<Geometry>
    let inputMaterial:NodePort<Material>
    let outputMesh:NodePort<Object>
    
    override var ports: [any NodePortProtocol] { super.ports +  [inputGeometry,
                                         inputMaterial,
                                         outputMesh] }
    
    private var mesh: Mesh? = nil

    required init(context: Context)
    {
        self.inputCastsShadow = BoolParameter("Enable Shadows", true, .button)
        self.inputDoubleSided = BoolParameter("Double Sided", false, .button)
        self.inputCullingMode = StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown)
        
        self.inputGeometry = NodePort<Geometry>(name: "Geometry", kind: .Inlet)
        self.inputMaterial = NodePort<Material>(name: "Material", kind: .Inlet)
        self.outputMesh = NodePort<Object>(name: MeshNode.name, kind: .Outlet)
        
        super.init(context: context)
    }
    
        
    enum CodingKeys : String, CodingKey
    {
        case inputCastsShadowParameter
        case inputDoubleSidedParemeter
        case inputCullModeParameter
        case inputGeometryPort
        case inputMaterialPort
        case outputMeshPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputCastsShadow, forKey: .inputCastsShadowParameter)
        try container.encode(self.inputDoubleSided, forKey: .inputDoubleSidedParemeter)
        try container.encode(self.inputCullingMode, forKey: .inputCullModeParameter)
        try container.encode(self.inputGeometry, forKey: .inputGeometryPort)
        try container.encode(self.inputMaterial, forKey: .inputMaterialPort)
        try container.encode(self.outputMesh, forKey: .outputMeshPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputCastsShadow = try container.decode(BoolParameter.self, forKey: .inputCastsShadowParameter)
        self.inputDoubleSided = try container.decode(BoolParameter.self, forKey: .inputDoubleSidedParemeter)
        self.inputCullingMode = try container.decode(StringParameter.self, forKey: .inputCullModeParameter)
        
        self.inputCullingMode.options = ["Back", "Front", "None"]
        
        self.inputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .inputGeometryPort)
        self.inputMaterial = try container.decode(NodePort<Material>.self, forKey: .inputMaterialPort)
        self.outputMesh = try container.decode(NodePort<Object>.self, forKey: .outputMeshPort)
        
        try super.init(from: decoder)
    }
    override func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        if let geometery = self.inputGeometry.value,
           let material = self.inputMaterial.value
        {
            if let mesh = mesh
            {
//                mesh.cullMode = .none
                mesh.geometry = geometery
                mesh.material = material
                
                self.outputMesh.send(mesh)
            }
            else
            {
                self.mesh = Mesh(geometry: geometery, material: material)
//                self.mesh?.receiveShadow = true
//                self.mesh?.castShadow = true
            }
            
            if let mesh = mesh
            {
                self.evaluate(object: mesh, atTime: atTime)
                
                mesh.castShadow = self.inputCastsShadow.value
                mesh.receiveShadow = self.inputCastsShadow.value
                mesh.cullMode = self.cullMode()
                
                self.outputMesh.send(mesh)
            }
        }
     }
    
    private func cullMode() -> MTLCullMode
    {
        switch self.inputCullingMode.value
        {
        case "Front":
            return .front
        case "Back":
            return .back
            
        default: return .none
        }
    }
}
