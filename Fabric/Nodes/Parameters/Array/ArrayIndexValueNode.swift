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

public class ArrayIndexValueNode<Value : FabricPort & Equatable & FabricDescription> : Node
{
    public override class var name:String {"\(Value.fabricDescription) Value at Array Index" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provides the value of \(Value.fabricDescription) at an input index number"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort",  NodePort<ContiguousArray<Value>>(name: "Array", kind: .Inlet)),
            ("inputIndexParam", ParameterPort(parameter: FloatParameter("Index", 0, .inputfield)) ),
            ("outputPort", NodePort<Value>(name: "Value", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<ContiguousArray<Value>> { port(named: "inputPort") }
    public var inputIndexParam:ParameterPort<Int> { port(named: "inputIndexParam") }
    public var outputPort:NodePort<Value> { port(named: "outputPort") }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.inputIndexParam.valueDidChange,
           let index = self.inputIndexParam.value
        {
            let index = max( 0, index )
            
            if let array = self.inputPort.value
            {
                let val = array[index]
                self.outputPort.send( val )
            }
            
            else
            {
                self.outputPort.send( nil )
            }
        }
    }
}
