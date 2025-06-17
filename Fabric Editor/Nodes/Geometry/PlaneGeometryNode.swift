//
//  PlaneGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Satin
import Foundation
import simd
import Metal

class PlaneGeometryNode : Node, NodeProtocol
{
    static let name = "Plane Geometry"
    static var nodeType = Node.NodeType.Geometery

    // Params
    let inputWidthParam:FloatParameter
    let inputHeightParam:FloatParameter
    let inputResolutionParam:Int2Parameter
    override var inputParameters: [any Parameter] { [inputWidthParam, inputHeightParam, inputResolutionParam] }

    // Ports
    let outputGeometry:NodePort<Geometry>
    override var ports:[any NodePortProtocol] { super.ports + [outputGeometry] }

    private let geometry = PlaneGeometry(width: 1, height: 1)

    required init(context: Context)
    {
        self.inputWidthParam = FloatParameter("Width", 1.0, .inputfield)
        self.inputHeightParam = FloatParameter("Height", 1.0, .inputfield)
        self.inputResolutionParam = Int2Parameter("Resolution", simd_int2(repeating: 1), .inputfield)

        self.outputGeometry = NodePort<Geometry>(name: BoxGeometryNode.name, kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputWidthParameter
        case inputHeightParameter
        case inputResolutionParameter
        case outputGeometryPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputWidthParam, forKey: .inputWidthParameter)
        try container.encode(self.inputHeightParam, forKey: .inputHeightParameter)
        try container.encode(self.inputResolutionParam, forKey: .inputResolutionParameter)
        try container.encode(self.outputGeometry, forKey: .outputGeometryPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputWidthParam = try container.decode(FloatParameter.self, forKey: .inputWidthParameter)
        self.inputHeightParam = try container.decode(FloatParameter.self, forKey: .inputHeightParameter)
        self.inputResolutionParam = try container.decode(Int2Parameter.self, forKey: .inputResolutionParameter)
        self.outputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .outputGeometryPort)
        
        try super.init(from: decoder)
    }
    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        self.geometry.width = self.inputWidthParam.value
        self.geometry.height = self.inputHeightParam.value        
        self.geometry.resolution = self.inputResolutionParam.value
        
        self.outputGeometry.send(self.geometry)
     }
}
