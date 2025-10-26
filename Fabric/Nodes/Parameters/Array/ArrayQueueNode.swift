//
//  ArrayQueueNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/19/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ArrayQueueNode<Value : FabricPort & Equatable & FabricDescription> : Node
{
    public override class var name:String { "\(Value.fabricDescription) Queue" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Inserts \(Value.fabricDescription) items into an beginning on an Array."}

    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort", NodePort<Value>(name: "Value", kind: .Inlet)),
            ("inputSizeParam", ParameterPort(parameter: IntParameter("Size", 0, .inputfield))),
            ("outputPort", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<Value> { port(named: "inputPort") }
    public var inputSizeParam:ParameterPort<Int> { port(named: "inputSizeParam") }
    public var outputPort:NodePort<ContiguousArray<Value>> { port(named: "outputPort") }
    
    private var queue:ContiguousArray<Value> = []
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        
        if self.inputSizeParam.valueDidChange,
           let size = self.inputSizeParam.value
        {
            self.queue = ContiguousArray( self.queue.prefix( size ) )
        }
        
        if self.inputPort.valueDidChange,
           let value = self.inputPort.value,
           let size = self.inputSizeParam.value
        {
            self.queue.insert(value, at: 0)
            
            self.queue = ContiguousArray( self.queue.prefix( size ) )

            self.outputPort.send( self.queue )
        }
    }
}
