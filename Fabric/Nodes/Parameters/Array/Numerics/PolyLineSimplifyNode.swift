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
    public let inputPort = NodePort<ContiguousArray<simd_float2>>(name: "Array", kind: .Inlet, description: "Input polyline as array of 2D points")
    public let inputTolerance = ParameterPort(parameter: FloatParameter("Tolerance", 0, .inputfield, "Simplification tolerance for the Douglas-Peucker algorithm"))
    public let outputPort = NodePort<ContiguousArray<simd_float2>>(name: "Array", kind: .Outlet, description: "Simplified polyline with reduced point count")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputPort", port: self.inputPort),
            PortDeclaration(key: "inputTolerance", port: self.inputTolerance),
            PortDeclaration(key: "outputPort", port: self.outputPort),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
