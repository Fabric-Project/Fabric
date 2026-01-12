//
//  PolyLineSimplifyNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
internal import SwiftSimplify

public class PolyLineSimplifyNode: Node
{
    public override class var name:String {"Simplify Polyline" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Simplify an array of points using the Duglas Peucker algorithm."}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort",  NodePort<ContiguousArray<simd_float2>>(name: "Array", kind: .Inlet)),
            ("inputTolerance", ParameterPort(parameter: FloatParameter("Tolerance", 0, .inputfield)) ),
            ("outputPort", NodePort<ContiguousArray<simd_float2>>(name: "Array", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<ContiguousArray<simd_float2>> { port(named: "inputPort") }
    public var inputTolerance:ParameterPort<Float> { port(named: "inputTolerance") }
    public var outputPort:NodePort<ContiguousArray<simd_float2>> { port(named: "outputPort") }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.inputTolerance.valueDidChange,
           let tolerance = self.inputTolerance.value
        {
            
            if let array = self.inputPort.value
            {
                let simplifiedPoints = SwiftSimplify.simplify(array, tolerance: tolerance)

                self.outputPort.send( simplifiedPoints )
            }
            
//            else
//            {
//                self.outputPort.send( nil )
//            }
        }
    }
}
