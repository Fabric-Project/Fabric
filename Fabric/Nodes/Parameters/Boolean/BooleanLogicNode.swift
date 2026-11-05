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
    public let inputBool1 = ParameterPort(parameter: BoolParameter("Bool A", false, .button, "First boolean value to compare"))
    public let inputBool2 = ParameterPort(parameter: BoolParameter("Bool B", false, .button, "Second boolean value to compare"))
    public let inputParam = ParameterPort(parameter: StringParameter("Operator", "Equals", LogicOperator.allCases.map(\.rawValue), .dropdown, "Logic operation to perform on the two values"))
    public let outputBool = NodePort<Bool>(name: "Result" , kind: .Outlet, description: "Result of the boolean logic operation")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputBool1", port: self.inputBool1),
            PortDeclaration(key: "inputBool2", port: self.inputBool2),
            PortDeclaration(key: "inputParam", port: self.inputParam),
            PortDeclaration(key: "outputBool", port: self.outputBool),
        ]
    }

    private var op = LogicOperator.Equals
    
    override public func startExecution(renderer:GraphRenderer) throws
    {
        if let stringParam = self.inputParam.parameter as? StringParameter
        {
            stringParam.options = BinaryMathOperator.allCases.map(\.rawValue)
        }
        try super.startExecution(renderer: renderer)
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
