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

public class FloatArrayToVector2ArrayNode: Node
{
    public override class var name:String {"Float Array to Vector 2 Array" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts an array of Floats into an array of Vector 2s based off of the index of value"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort",  NodePort<ContiguousArray<Float>>(name: "Array", kind: .Inlet, description: "Input array of float values")),
            ("outputPort", NodePort<ContiguousArray<simd_float2>>(name: "Vector 2 Array", kind: .Outlet, description: "Array of 2D vectors with normalized index as X and value as Y")),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<ContiguousArray<Float>> { port(named: "inputPort") }
    public var outputPort:NodePort<ContiguousArray<simd_float2>> { port(named: "outputPort") }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange
        {
            if let array = self.inputPort.value
            {
                let count = array.count
                let vectorArray = array.enumerated( ).map { (index:Int, value:Float) -> simd_float2 in
                        return simd_float2(Float(index)/Float(count), value )
                }
                
                self.outputPort.send( ContiguousArray(vectorArray) )
            }
            
//            else
//            {
//                self.outputPort.send( nil )
//            }
        }
    }
}
