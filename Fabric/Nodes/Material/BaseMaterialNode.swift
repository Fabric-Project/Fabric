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

    // Params
    let inputReceivesLighting = BoolParameter("Receives Lighting", true, .button)
    let inputWriteDepth = BoolParameter("Write Depth", true, .button)
    
    override var inputParameters: [any Parameter] { super.inputParameters + [ self.inputReceivesLighting,
                                                                              self.inputWriteDepth, ] }
        
    func evaluate(material:Material, atTime:TimeInterval)
    {
        material.lighting = self.inputReceivesLighting.value
        material.depthWriteEnabled = self.inputWriteDepth.value
    }
    
   
}
