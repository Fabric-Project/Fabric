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

/// Base implementation for geometry providers, including the standard Primitive
/// input, Geometry output, and publication lifecycle.
///
/// External plug-ins can subclass this type, provide ``geometry``, and override
/// ``execute(renderer:executionInfo:renderPassDescriptor:commandBuffer:)`` when
/// they need specialized geometry work.
open class BaseGeometryNode : Node
{
    override open class var name:String { "Geometry" }
    override open class var nodeType:Node.NodeType { .Geometery }
    override open class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override open class var nodeTimeMode: Node.TimeMode { .None }
    override open class var nodeDescription: String { "Provides \(Self.name)"}

    public let inputPrimitiveType: NodePort<String>
    public let outputGeometry = NodePort<Geometry>(name: "Geometry", kind: .Outlet, description: "The generated geometry mesh")

    override open func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputPrimitiveType", port: self.inputPrimitiveType),
            PortDeclaration(key: "outputGeometry", port: self.outputGeometry),
        ]
    }

    /// The Primitive inlet's starting value. A node that builds points
    /// overrides it.
    open class var defaultPrimitiveType: String { "Triangle" }

    public required init(context: Context)
    {
        self.inputPrimitiveType = Self.makePrimitiveTypePort()
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        self.inputPrimitiveType = Self.makePrimitiveTypePort()
        try super.init(from: decoder)
    }

    private static func makePrimitiveTypePort() -> NodePort<String>
    {
        ParameterPort(parameter:StringParameter("Primitive", defaultPrimitiveType, ["Point", "Line", "Line Strip", "Triangle", "Triangle Strip"], .dropdown, "Rendering primitive type for the geometry mesh"))
    }

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
        
        // We use this for disconnect / reconnect logic...
        // Maybe this needs to go into a super call? :X 
        if self.isDirty
        {
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    override open func execute(renderer:GraphRenderer, executionInfo:GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        let shouldOutput = self.evaluate(geometry: self.geometry, atTime: executionInfo.timing.time)

        if shouldOutput
        {
            // We force here, because
            // 1 - SatinGeometry implements equality with reference === semantics
            // 2 - our params may have changed (ie shouldOutput is true)
            //   - but our instance is the same (!)
            // 3 - We need to ensure other clients which need to get valueDidChange will in fact update
            
            self.outputGeometry.send(self.geometry, force:true)
        }
    }
    
    /// Resolves the standard Primitive input to its Metal primitive type.
    public func primitiveType() -> MTLPrimitiveType
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
