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

    override open class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPrimitiveType", ParameterPort(parameter:StringParameter("Primitive", "Triangle", ["Point", "Line", "Line Strip", "Triangle", "Triangle Strip"], .dropdown, "Rendering primitive type for the geometry mesh")) ),
            ("outputGeometry",  NodePort<Geometry>(name: "Geometry", kind: .Outlet, description: "The generated geometry mesh")),
        ]
    }
    
    public var inputPrimitiveType: NodePort<String> { _inputPrimitiveType }
    private var _inputPrimitiveType: NodePort<String>!
    public var outputGeometry: NodePort<Geometry> { _outputGeometry }
    private var _outputGeometry: NodePort<Geometry>!

    override open func bindPorts()
    {
        super.bindPorts()
        self._inputPrimitiveType = findPort(named: "inputPrimitiveType")
        self._outputGeometry = findPort(named: "outputGeometry")
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
