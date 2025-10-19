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

    public let outputGeometry:NodePort<Geometry>
    public override var ports: [Port] { [ self.outputGeometry] + super.ports}
    

    public let inputPrimitiveType:StringParameter

    public override var inputParameters: [any Parameter] {
        [self.inputPrimitiveType,
    ] + super.inputParameters}

    open var geometry: Geometry {
        fatalError("Subclasses must override geometry")
    }

    public required init(context: Context) {
        
        self.inputPrimitiveType = StringParameter("Geometry Primitive", "Triangle", ["Point", "Line", "Line Strip", "Triangle", "Triangle Strip"], .dropdown)

        self.outputGeometry = NodePort<Geometry>(name: "Geometry", kind: .Outlet)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputPrimitiveTypeParam
        case outputGeometryPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputPrimitiveType, forKey: .inputPrimitiveTypeParam)
        try container.encode(self.outputGeometry, forKey: .outputGeometryPort)
        
        try super.encode(to: encoder)
    }
    
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.inputPrimitiveType = try container.decode(StringParameter.self, forKey: .inputPrimitiveTypeParam)

        self.outputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .outputGeometryPort)

        try super.init(from: decoder)
        
        // TODO: We need to fix StringParam serialization
        self.inputPrimitiveType.options = ["Point", "Line", "Line Strip", "Triangle", "Triangle Strip"]
    }
    
    public func evaluate(geometry:Geometry, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = false
        
        if self.inputPrimitiveType.valueDidChange
        {
            geometry.primitiveType = self.primitiveType()
            shouldOutput = true
        }
        
        if self.isDirty
        {
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
