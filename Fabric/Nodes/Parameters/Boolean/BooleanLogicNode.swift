//
//  BooleanLogicNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/26/25.
//
import Foundation
import Satin
import simd
import Metal

public class BooleanLogicNode : Node
{
    override public static var name:String { "Boolean Logic Comparisons" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Boolean) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Compare two Boolean values"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputBool1", ParameterPort(parameter: BoolParameter("Bool A", false, .button))),
            ("inputBool2", ParameterPort(parameter: BoolParameter("Bool B", false, .button))),
            ("inputParam", ParameterPort(parameter: StringParameter("Operator", "Equals", LogicOperator.allCases.map(\.rawValue))) ),
            ("outputBool", NodePort<Bool>(name: "Result" , kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputBool1:ParameterPort<Bool> { port(named: "inputBool1") }
    public var inputBool2:ParameterPort<Bool> { port(named: "inputBool2") }
    public var inputParam:ParameterPort<String> { port(named: "inputParam") }
    public var outputBool:NodePort<Bool> { port(named: "outputBool") }
    
    private var op = LogicOperator.Equals
    
    override public func startExecution(context: GraphExecutionContext) {
        super.startExecution(context: context)
        
        if let stringParam = self.inputParam.parameter as? StringParameter
        {
            stringParam.options = BinaryMathOperator.allCases.map(\.rawValue)
        }
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputParam.valueDidChange,
           let param = self.inputParam.value,
           let mathOp = LogicOperator(rawValue: param)
        {
            self.op = mathOp
        }
        
        if self.inputParam.valueDidChange
            || self.inputBool1.valueDidChange
            || self.inputBool2.valueDidChange,
           let bool1 = self.inputBool1.value,
           let bool2 = self.inputBool2.value
        {
            self.outputBool.send(self.op.perform(lhs: bool1,
                                                 rhs: bool2) )
            
        }
        
    }
}
