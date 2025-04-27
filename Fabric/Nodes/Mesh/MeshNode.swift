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

class MeshNode : Node
{
    // Ports
    let inputGeometry = NodePort<Geometry>(name: "geometry", kind: .Inlet)
    let inputMaterial = NodePort<Material>(name: "Material", kind: .Inlet)
    let inputOrientation = NodePort<simd_quatf>(name: "Orientation", kind: .Inlet)

    let outputMesh = NodePort<Object>(name: "Mesh", kind: .Outlet)
    
    private var mesh: Mesh? = nil
    
    override var ports: [any AnyPort] { [inputGeometry,
                                         inputMaterial,
                                         inputOrientation,
                                         outputMesh] }
    
    
    required init(context:Context)
    {
        super.init(context: context, type: .Mesh, name:"Mesh")
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
                mesh.geometry = geometery
                mesh.material = material
                
                self.outputMesh.send(mesh)
            }
            else
            {
                self.mesh = Mesh(geometry: geometery, material: material)
                
            }
            
            if let mesh = mesh
            {
                let angle = cosf( Float( (atTime * 0.01).remainder(dividingBy: 1) ) * Float.pi * 4 )
                mesh.orientation = simd_quatf(angle:angle, axis:simd_make_float3(0.2, 1, -0.3))

                self.outputMesh.send(mesh)
            }

        }
     }
}
