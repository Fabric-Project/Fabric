//
//  BoxGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/25/25.
//
import Satin
import Foundation
import simd
import Metal

public class IcoSphereGeometryNode : Node, NodeProtocol
{
    public static let name = "IcoSphere Geometry"
    public static var nodeType = Node.NodeType.Geometery

    // Params
    public let inputRadius:FloatParameter
    public let inputResolutionParam:IntParameter
    override public var inputParameters: [any Parameter] { [inputRadius, inputResolutionParam] + super.inputParameters}

    // Ports
    let outputGeometry:NodePort<Geometry>
    public override var ports:[any NodePortProtocol] {  [outputGeometry] + super.ports}

    private let geometry = IcoSphereGeometry(radius: 1.0, resolution: 1)

    required public init(context: Context)
    {
        self.inputRadius = FloatParameter("Radius", 1.0, .inputfield)
        self.inputResolutionParam = IntParameter("Resolution", 1, .inputfield)

        self.outputGeometry = NodePort<Geometry>(name: BoxGeometryNode.name, kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputRadiusParameter
        case inputResolutionParameter
        case outputGeometryPort
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputRadius, forKey: .inputRadiusParameter)
        try container.encode(self.inputResolutionParam, forKey: .inputResolutionParameter)
        try container.encode(self.outputGeometry, forKey: .outputGeometryPort)
        
        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputRadius = try container.decode(FloatParameter.self, forKey: .inputRadiusParameter)
        self.inputResolutionParam = try container.decode(IntParameter.self, forKey: .inputResolutionParameter)
        self.outputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .outputGeometryPort)
        
        try super.init(from: decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        var shouldOutputGeometry = false
        
        if self.inputRadius.valueDidChange
        {
            self.geometry.radius = self.inputRadius.value
            shouldOutputGeometry = true
        }
                
        if  self.inputResolutionParam.valueDidChange
        {
            self.geometry.resolution =  self.inputResolutionParam.value
            shouldOutputGeometry = true
        }
        
        if shouldOutputGeometry
        {
            self.outputGeometry.send(self.geometry)
        }
     }
}
