//
//  BaseMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal

class BaseMaterialNode : Node
{
    override var ports: [any AnyPort] { [ inputReceivesLighting,
                                          inputCastsShadow,
                                          inputWriteDepth, ] }

    let inputReceivesLighting = NodePort<Bool>(name: "Recieves Lighting", kind: .Inlet)
    let inputCastsShadow = NodePort<Bool>(name: "Cast Shadow", kind: .Inlet)
    let inputWriteDepth = NodePort<Bool>(name: "Write Depth", kind: .Inlet)
        
    func evaluate(material:Material, atTime:TimeInterval)
    {
        if let v = self.inputReceivesLighting.value
        {
            material.lighting = v
        }
        
        if let v = self.inputCastsShadow.value
        {
            material.castShadow = v
        }
        
        if let v = self.inputWriteDepth.value
        {
            material.depthWriteEnabled = v
        }
    }
    
   
}
