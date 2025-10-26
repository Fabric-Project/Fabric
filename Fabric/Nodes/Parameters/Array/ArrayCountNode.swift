//
//  ArrayCountNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//


import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ArrayCountNode<Value : FabricPort & Equatable & FabricDescription> : Node
{
    public override class var name:String { "\(Value.fabricDescription) Array Count" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Number of elements in an \(Value.fabricDescription) Array"}

    // TODO: add character set menu to choose component separation strategy
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Inlet)),
            ("outputPort", NodePort<Float>(name: "Count", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<ContiguousArray<Value>> { port(named: "inputPort") }
    public var outputPort:NodePort<Int> { port(named: "outputPort") }
 
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange
        {
            if let array = self.inputPort.value
            {
                self.outputPort.send( array.count )
            }
            
            else
            {
                self.outputPort.send( nil )
            }
        }
    }
}
