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

public class Vector2ArrayToVector3ArrayNode: Node
{
    public override class var name:String {"Vector 2 Array to Vector 3 Array" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts an array of Vector 2s into an array of Vector 3s"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort",  NodePort<ContiguousArray<simd_float2>>(name: "Vector 2 Array", kind: .Inlet, description: "Input array of 2D vectors")),
            ("outputPort", NodePort<ContiguousArray<simd_float3>>(name: "Vector 3 Array", kind: .Outlet, description: "Array of 3D vectors with Z set to 0")),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<ContiguousArray<simd_float2>> { port(named: "inputPort") }
    public var outputPort:NodePort<ContiguousArray<simd_float3>> { port(named: "outputPort") }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange
        {
            if let array = self.inputPort.value
            {
                let count = array.count
                let vectorArray = array.enumerated( ).map { (index:Int, value:simd_float2) -> simd_float3 in
                    return simd_float3(value.x, value.y, 0)
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
