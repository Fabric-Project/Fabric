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

class SphereGeometryNode : Node, NodeProtocol
{
    static let name = "Sphere Geometry"
    static var nodeType = Node.NodeType.Geometery

    // Params
    let inputRadius:FloatParameter
    let inputAngularResolutionParam:IntParameter
    let inputVerticalResolutionParam:IntParameter
    override var inputParameters: [any Parameter] { [inputRadius, inputAngularResolutionParam, inputVerticalResolutionParam] }

    // Ports
    let outputGeometry:NodePort<Geometry>
    override var ports:[any NodePortProtocol] { super.ports + [outputGeometry] }

    private let geometry = SphereGeometry(radius: 1.0, angularResolution: 60, verticalResolution: 30)

    required init(context: Context)
    {
        self.inputRadius = FloatParameter("Radius", 1.0, .inputfield)
        self.inputAngularResolutionParam = IntParameter("Angular Resolution", 60, .inputfield)
        self.inputVerticalResolutionParam = IntParameter("Vertical Resolution", 30, .inputfield)

        self.outputGeometry = NodePort<Geometry>(name: BoxGeometryNode.name, kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputRadiusParameter
        case inputAngularResolutionParameter
        case inputVerticalResolutionParameter
        case outputGeometryPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputRadius, forKey: .inputRadiusParameter)
        try container.encode(self.inputAngularResolutionParam, forKey: .inputAngularResolutionParameter)
        try container.encode(self.inputVerticalResolutionParam, forKey: .inputVerticalResolutionParameter)
        try container.encode(self.outputGeometry, forKey: .outputGeometryPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputRadius = try container.decode(FloatParameter.self, forKey: .inputRadiusParameter)
        self.inputAngularResolutionParam = try container.decode(IntParameter.self, forKey: .inputAngularResolutionParameter)
        self.inputVerticalResolutionParam = try container.decode(IntParameter.self, forKey: .inputVerticalResolutionParameter)
        self.outputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .outputGeometryPort)
        
        try super.init(from: decoder)
    }
    
    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        self.geometry.radius = self.inputRadius.value
        self.geometry.angularResolution =  self.inputAngularResolutionParam.value
        self.geometry.verticalResolution =  self.inputVerticalResolutionParam.value

        self.outputGeometry.send(self.geometry)
     }
}
