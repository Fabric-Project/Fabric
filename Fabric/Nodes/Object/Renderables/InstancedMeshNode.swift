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

public class InstancedMeshNode : BaseRenderableNode<InstancedMesh>
{
    override public class var name:String { "Instanced Mesh" }
    override public class var nodeType:Node.NodeType  { Node.NodeType.Object(objectType: .Mesh) }
    override public class var nodeDescription: String { "Provides optimized rendering of multiple copies of this Geometry and Material Mesh"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return [
            ("inputGeometry", NodePort<Geometry>(name: "Geometry", kind: .Inlet)),
            ("inputMaterial", NodePort<Material>(name: "Material", kind: .Inlet)),
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet)),
            ("inputCastsShadow", ParameterPort(parameter:BoolParameter("Enable Shadows", true, .button))),
            ("inputDoubleSided", ParameterPort(parameter:BoolParameter("Double Sided", false, .button))),
            ("inputCullingMode", ParameterPort(parameter:StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown))),
        ] + ports
    }
    // Proxy Ports
    public var inputGeometry:NodePort<Geometry> { port(named: "inputGeometry") }
    public var inputMaterial:NodePort<Material> { port(named: "inputMaterial") }
    public var inputPositions:NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputCastsShadow:ParameterPort<Bool> { port(named: "inputCastsShadow") }
    public var inputDoubleSided:ParameterPort<Bool> { port(named: "inputDoubleSided") }
    public var inputCullingMode:ParameterPort<String> { port(named: "inputCullingMode") }
  
    override public var object:InstancedMesh? {
        
        // This is tricky - we want to output nil if we have no inputGeometry  / inputMaterial from upstream ports
        if let _ = self.inputGeometry.value ,
           let _ = self.inputMaterial.value
        {
            return mesh
        }
        
        return nil
    }
    
    private var mesh: InstancedMesh? = nil
    {
        didSet
        {
            // Relying on side effects - this triggers
            self.graph?.syncNodesToScene(removingObject: oldValue)
        }
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
            let _ = self.evaluate(object: mesh, atTime: context.timing.time)
            
            if self.inputPositions.valueDidChange,
                let positions = self.inputPositions.value
            {
                mesh.drawCount = positions.count
                
                positions.enumerated().forEach { index, position in
                    
                    let positionMatrix = translationMatrix3f(position)
                    mesh.setMatrixAt(index: index, matrix: positionMatrix)
                }
            }
            
            if self.inputCastsShadow.valueDidChange,
               let inputCastsShadow = self.inputCastsShadow.value
            {
                mesh.castShadow = inputCastsShadow
                mesh.receiveShadow = inputCastsShadow
            }
            
            if self.inputCullingMode.valueDidChange
            {
                mesh.cullMode = self.cullMode()
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
