//
//  DirectionalLightNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//


import Foundation
import Satin
import simd
import Metal

class DirectionalLightNode : Node, NodeProtocol
{
    static let name = "Directional Light"
    static var nodeType = Node.NodeType.Light

    // Ports
    let inputPosition = NodePort<simd_float3>(name: "Position", kind: .Inlet)
    let inputOrientation = NodePort<simd_quatf>(name: "Orientation", kind: .Inlet)

    let outputLight = NodePort<Object>(name: MeshNode.name, kind: .Outlet)
    
    private var light: DirectionalLight = DirectionalLight(color: simd_float3(repeating: 1) )
    
    override var ports: [any AnyPort] { super.ports +  [
                                         inputPosition,
                                         inputOrientation,
                                                        outputLight] }
    
    
//    required init(context:Context)
//    {
//        super.init(context: context)
    //    }
    
    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        
        if let v = self.inputPosition.value
        {
            light.position = v
        }
        
        self.outputLight.send(light)
        
    }
}
