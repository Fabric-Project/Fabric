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

public class NumberEaseNode : Node
{
    override public class var name:String { "Number Ease" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None } // TODO: Should this change?
    override public class var nodeDescription: String { "Run an easing on an input Number between 0 and 1 and return the resulting Eased Number"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield))),
            ("inputParam", ParameterPort(parameter: StringParameter("Easing", "Linear", Easing.allCases.map( {$0.title()} ), .dropdown )) ),
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var inputParam:ParameterPort<String> { port(named: "inputParam") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
    
    private let easingMap = Dictionary(uniqueKeysWithValues: zip(Easing.allCases.map( {$0.title()}), Easing.allCases)  )

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputNumber.valueDidChange,
           let param = self.inputParam.value,
           let easeFunc = easingMap[param],
           let loopedTime = self.inputNumber.value//.truncatingRemainder(dividingBy: duration) // TODO: ?? should we loop by 1.0?
        {
            self.outputNumber.send( Float( easeFunc.function( Double(loopedTime) ) ) )
        }
     }
}
