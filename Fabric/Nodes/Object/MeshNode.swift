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
    static let name = "Mesh"
    static var nodeType = Node.NodeType.Mesh

    // Params
    let inputCastsShadow = BoolParameter("Shadow", false, .button)
//    let inputReceiveShadow = BoolParameter("Receive Shadow", false, .button)
    
    override var inputParameters: [any Parameter] { super.inputParameters + [
                                                                              self.inputCastsShadow,
//                                                                              self.inputReceiveShadow,
                                                                             ] }
        
//    func evaluate(material:Material, atTime:TimeInterval)
//    {
//        material.lighting = self.inputReceivesLighting.value
//                
//        material.castShadow = self.inputCastsShadow.value
//        material.receiveShadow = self.inputReceiveShadow.value
//
//        material.depthWriteEnabled = self.inputWriteDepth.value
//    }
    
    // Ports
    let inputGeometry = NodePort<Geometry>(name: "Geometry", kind: .Inlet)
    let inputMaterial = NodePort<Material>(name: "Material", kind: .Inlet)

    let outputMesh = NodePort<Object>(name: MeshNode.name, kind: .Outlet)
    
    private var mesh: Mesh? = nil
    
    override var ports: [any NodePortProtocol] { super.ports +  [inputGeometry,
                                         inputMaterial,
                                         outputMesh] }
    
    
    override func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        if let geometery = self.inputGeometry.value,
           let material = self.inputMaterial.value
        {
            if let mesh = mesh
            {
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

                self.outputMesh.send(mesh)
            }
        }
     }
}
