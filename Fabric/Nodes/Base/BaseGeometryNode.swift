//
//  BaseGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/3/25.
//

import Foundation
import Satin
import simd
import Metal

public class BaseGeometryNode : Node
{
    override public class var name:String { "Geometry" }
    override public class var nodeType:Node.NodeType { .Geometery }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provides \(Self.name)"}

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPrimitiveType", ParameterPort(parameter:StringParameter("Geometry Primitive", "Triangle", ["Point", "Line", "Line Strip", "Triangle", "Triangle Strip"], .dropdown)) ),
            ("outputGeometry",  NodePort<Geometry>(name: "Geometry", kind: .Outlet)),
        ]
    }
    
    public var inputPrimitiveType: NodePort<String>   { port(named: "inputPrimitiveType") }
    public var outputGeometry: NodePort<Geometry>   { port(named: "outputGeometry") }

    open var geometry: Geometry {
        fatalError("Subclasses must override geometry")
    }
        
    public func evaluate(geometry:Geometry, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = false
        
        if self.inputPrimitiveType.valueDidChange
        {
            geometry.primitiveType = self.primitiveType()
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    public override func execute(context: GraphExecutionContext, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer)
    {
        let shouldOutput = self.evaluate(geometry: self.geometry, atTime: context.timing.time)
        
        if shouldOutput
        {
            self.outputGeometry.send(self.geometry)
        }
    }
    
    private func primitiveType() -> MTLPrimitiveType
    {
        switch self.inputPrimitiveType.value
        {
        case "Point":
            return .point
            
        case "Line":
            return .line

        case "Line Strip":
            return .lineStrip
            
        case "Triangle":
            return .triangle
            
        case "Triangle Strip":
            return .triangleStrip

        default: return .triangle
        }
    }
}
