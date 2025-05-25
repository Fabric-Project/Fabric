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

class IcoSphereGeometryNode : Node, NodeProtocol
{
    static let name = "IcoSphere Geometry"
    static var nodeType = Node.NodeType.Geometery

    // Params
    let inputRadius:FloatParameter
    let inputResolutionParam:IntParameter
    override var inputParameters: [any Parameter] { [inputRadius, inputResolutionParam] }

    // Ports
    let outputGeometry:NodePort<Geometry>
    override var ports:[any NodePortProtocol] { super.ports + [outputGeometry] }

    private let geometry = IcoSphereGeometry(radius: 1.0, resolution: 1)

    required init(context: Context)
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
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputRadius, forKey: .inputRadiusParameter)
        try container.encode(self.inputResolutionParam, forKey: .inputResolutionParameter)
        try container.encode(self.outputGeometry, forKey: .outputGeometryPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputRadius = try container.decode(FloatParameter.self, forKey: .inputRadiusParameter)
        self.inputResolutionParam = try container.decode(IntParameter.self, forKey: .inputResolutionParameter)
        self.outputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .outputGeometryPort)
        
        try super.init(from: decoder)
    }
    
    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        self.geometry.radius = self.inputRadius.value
                
        self.geometry.resolution =  self.inputResolutionParam.value
                
        self.outputGeometry.send(self.geometry)
     }
}
