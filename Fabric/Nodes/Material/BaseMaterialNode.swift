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
//    let inputCastsShadow = BoolParameter("Cast Shadow", false, .button)
//    let inputReceiveShadow = BoolParameter("Receive Shadow", false, .button)
    let inputWriteDepth = BoolParameter("Write Depth", false, .button)
    
    override var inputParameters: [any Parameter] { super.inputParameters + [ self.inputReceivesLighting,
//                                                                              self.inputCastsShadow,
//                                                                              self.inputReceiveShadow, 
                                                                              self.inputWriteDepth, ] }
        
    func evaluate(material:Material, atTime:TimeInterval)
    {
        material.lighting = self.inputReceivesLighting.value
                
//        material.castShadow = self.inputCastsShadow.value
//        material.receiveShadow = self.inputReceiveShadow.value

        material.depthWriteEnabled = self.inputWriteDepth.value
    }
    
   
}
