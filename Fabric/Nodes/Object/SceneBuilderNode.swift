//
//  SceneBuilder.swift
//  Fabric
//
//  Created by Anton Marini on 4/28/25.
//

import Foundation
import Satin
import simd
import Metal

class SceneBuilderNode : Node, NodeProtocol
{
    static let name = "Scene Builder"
    static var nodeType = Node.NodeType.Object

    // Ports
    let inputObject1 = NodePort<Object>(name: "Input 1", kind: .Inlet)
    let inputObject2 = NodePort<Object>(name: "Input 2", kind: .Inlet)
    let inputObject3 = NodePort<Object>(name: "Input 3", kind: .Inlet)
    let inputObject4 = NodePort<Object>(name: "Input 4", kind: .Inlet)
    let inputObject5 = NodePort<Object>(name: "Input 5", kind: .Inlet)

    let outputScene = NodePort<Object>(name: SceneBuilderNode.name, kind: .Outlet)
    
    private var object = Object()
    
    override var ports: [any AnyPort] { super.ports +  [
        inputObject1,
        inputObject2,
        inputObject3,
        inputObject4,
        inputObject5,
        outputScene] }
    
    
    override func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        var scene:[Object] = []
        
        if let v = inputObject1.value { scene.append(v) }
        if let v = inputObject2.value { scene.append(v) }
        if let v = inputObject3.value { scene.append(v) }
        if let v = inputObject4.value { scene.append(v) }
        if let v = inputObject5.value { scene.append(v) }
        
        self.object.children = scene
        outputScene.send(self.object)
    }
}
