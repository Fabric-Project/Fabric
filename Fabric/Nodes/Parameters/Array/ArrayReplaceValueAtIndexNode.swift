//
//  ArrayIndexValueNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ArrayReplaceValueAtIndexNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name:String {"Replace \(Value.portType.rawValue) Value at Array Index" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Replaces the value of \(Value.portType.rawValue) at an input index with a new Value"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort",  NodePort<ContiguousArray<Value>>(name: "Array", kind: .Inlet, description: "Input array to modify")),
            ("inputIndexParam", ParameterPort(parameter: IntParameter("Index", 0, .inputfield, "Array index where the value will be replaced")) ),
            ("inputValue",  NodePort<Value>(name: "Value", kind: .Inlet, description: "New value to insert at the specified index")),
            ("outputPort", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Array with the value replaced at the specified index")),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<ContiguousArray<Value>> { port(named: "inputPort") }
    public var inputIndexParam:ParameterPort<Int> { port(named: "inputIndexParam") }
    public var inputValue:NodePort<Value> { port(named: "inputValue") }
    public var outputPort:NodePort<ContiguousArray<Value>> { port(named: "outputPort") }

    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPort.valueDidChange
            || self.inputIndexParam.valueDidChange
            || self.inputValue.valueDidChange
        else { return }

        guard var array = self.inputPort.value,
              let index = self.inputIndexParam.value,
              let value = self.inputValue.value
        else { return }

        // Only replace when the index is in range. Otherwise pass the array
        // through unchanged — the input array can shrink below a previously
        // valid index, and the previous `remove(at:)`/`insert(at:)` path
        // crashed when it did.
        if index >= 0 && index < array.count {
            array[index] = value
        }

        self.outputPort.send(array)
    }
}
