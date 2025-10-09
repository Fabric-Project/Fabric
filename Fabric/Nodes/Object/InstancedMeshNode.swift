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

public class InstancedMeshNode : BaseObjectNode, NodeProtocol
{
    public class var name:String { "Instanced Mesh" }
    public class var nodeType:Node.NodeType  { Node.NodeType.Object(objectType: .Mesh) }

    // Params
    public let inputCastsShadow:BoolParameter
    public let inputDoubleSided:BoolParameter
    public let inputCullingMode:StringParameter
    
    public override var inputParameters: [any Parameter] { [
        self.inputCastsShadow,
        self.inputDoubleSided,
        self.inputCullingMode
    ] + super.inputParameters}

    // Ports
    public let inputPositions:NodePort<ContiguousArray<simd_float3>>
    public let inputGeometry:NodePort<Geometry>
    public let inputMaterial:NodePort<Material>
    public let outputMesh:NodePort<Object>
    
    public override var ports: [any NodePortProtocol] {   [inputGeometry,
                                                           inputMaterial,
                                                           inputPositions,
                                                           outputMesh] + super.ports}
    
    private var mesh: InstancedMesh? = nil

    public required init(context: Context)
    {
        self.inputCastsShadow = BoolParameter("Enable Shadows", true, .button)
        self.inputDoubleSided = BoolParameter("Double Sided", false, .button)
        self.inputCullingMode = StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown)
        
        self.inputPositions = NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet)
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
        case inputPositionsPort
        case inputGeometryPort
        case inputMaterialPort
        case outputMeshPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputCastsShadow, forKey: .inputCastsShadowParameter)
        try container.encode(self.inputDoubleSided, forKey: .inputDoubleSidedParemeter)
        try container.encode(self.inputCullingMode, forKey: .inputCullModeParameter)
        try container.encode(self.inputGeometry, forKey: .inputGeometryPort)
        try container.encode(self.inputMaterial, forKey: .inputMaterialPort)
        try container.encode(self.inputPositions, forKey: .inputPositionsPort)
        try container.encode(self.outputMesh, forKey: .outputMeshPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputCastsShadow = try container.decode(BoolParameter.self, forKey: .inputCastsShadowParameter)
        self.inputDoubleSided = try container.decode(BoolParameter.self, forKey: .inputDoubleSidedParemeter)
        self.inputCullingMode = try container.decode(StringParameter.self, forKey: .inputCullModeParameter)
        
        self.inputCullingMode.options = ["Back", "Front", "None"]
        
        self.inputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .inputGeometryPort)
        self.inputMaterial = try container.decode(NodePort<Material>.self, forKey: .inputMaterialPort)
        self.inputPositions = try container.decode(NodePort<ContiguousArray<simd_float3>>.self, forKey: .inputPositionsPort)
        self.outputMesh = try container.decode(NodePort<Object>.self, forKey: .outputMeshPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if (self.inputGeometry.valueDidChange
            || self.inputMaterial.valueDidChange),
           let geometery = self.inputGeometry.value,
           let material = self.inputMaterial.value
        {
            if let mesh = mesh
            {
                mesh.geometry = geometery
                mesh.material = material
            }
            else
            {
                self.mesh = InstancedMesh(geometry: geometery, material: material, count: self.inputPositions.value?.count ?? 1)
            }
        }
            
        if let mesh = mesh
        {
            self.evaluate(object: mesh, atTime: context.timing.time)
            
            if self.inputPositions.valueDidChange, let positions = self.inputPositions.value
            {
                mesh.drawCount = positions.count
                
                positions.enumerated().forEach { index, position in
                    
                    let positionMatrix = translationMatrix3f(position)
                    mesh.setMatrixAt(index: index, matrix: positionMatrix)
                }
            }
            
            if self.inputCastsShadow.valueDidChange
            {
                mesh.castShadow = self.inputCastsShadow.value
                mesh.receiveShadow = self.inputCastsShadow.value
            }
            
            if self.inputCullingMode.valueDidChange
            {
                mesh.cullMode = self.cullMode()
            }
            
            self.outputMesh.send(mesh)
        }
        else
        {
            self.outputMesh.send(nil)
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
