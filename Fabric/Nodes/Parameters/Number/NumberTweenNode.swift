//
//  FloatTween.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//


import Foundation
import Satin
import simd
import Metal

class NumberEaseNode : Node, NodeProtocol
{
    
    static let name = "Number Ease"
    static var nodeType = Node.NodeType.Parameter

    // Ports
    let outputNumber = NodePort<Float>(name: NumberEaseNode.name , kind: .Outlet)
    override var ports: [any AnyPort] { super.ports + [ outputNumber] }

    // Params
    let inputTimeParam = FloatParameter("Time", 0.0, 0.0, 1.0, .slider)// GenericParameter<Float>("Time", 0.0, .inputfield)
    let inputEasingParam = StringParameter("Easing", "Linear", Easing.allCases.map( {$0.title()} ), .dropdown )
    
    private let easingMap = Dictionary(uniqueKeysWithValues: zip(Easing.allCases.map( {$0.title()}), Easing.allCases)  )
    
    
    override var inputParameters:[any Parameter]  { [inputTimeParam, inputEasingParam] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        
        let loopedTime = self.inputTimeParam.value//.truncatingRemainder(dividingBy: duration)

        if let easeFunc = easingMap[self.inputEasingParam.value]
        {
            
            self.outputNumber.send( Float( easeFunc.function( Double(loopedTime) ) ) )

        }
        else
        {
            self.outputNumber.send( loopedTime )
        }
        
       
     }
}
