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

public class CapsuleGeometryNode : Node, NodeProtocol
{
    public static let name = "Capsule Geometry"
    public static var nodeType = Node.NodeType.Geometery

    // Params
    public let inputRadius:FloatParameter
    public let inputHeight:FloatParameter
    public let inputAngularResolutionParam:IntParameter
    public let inputVerticalResolutionParam:IntParameter
    public override var inputParameters: [any Parameter] { [inputRadius, inputHeight, inputAngularResolutionParam, inputVerticalResolutionParam] + super.inputParameters}

    // Ports
    public let outputGeometry:NodePort<Geometry>
    public override var ports:[any NodePortProtocol] {  [outputGeometry] + super.ports}

    private let geometry = CapsuleGeometry(radius: 1.0, height: 2.0, angularResolution: 30, radialResolution: 30, verticalResolution: 30)
    
    public required init(context: Context)
    {
        self.inputRadius = FloatParameter("Radius", 1.0, .inputfield)
        self.inputHeight = FloatParameter("Height", 2.0, .inputfield)
        self.inputAngularResolutionParam = IntParameter("Angular Resolution", 30, .inputfield)
        self.inputVerticalResolutionParam = IntParameter("Vertical Resolution", 30, .inputfield)

        self.outputGeometry = NodePort<Geometry>(name: Self.name, kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputRadiusParameter
        case inputHeightParameter
        case inputAngularResolutionParameter
        case inputVerticalResolutionParameter
        case outputGeometryPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputRadius, forKey: .inputRadiusParameter)
        try container.encode(self.inputHeight, forKey: .inputHeightParameter)
        try container.encode(self.inputAngularResolutionParam, forKey: .inputAngularResolutionParameter)
        try container.encode(self.inputVerticalResolutionParam, forKey: .inputVerticalResolutionParameter)
        try container.encode(self.outputGeometry, forKey: .outputGeometryPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputRadius = try container.decode(FloatParameter.self, forKey: .inputRadiusParameter)
        self.inputHeight = try container.decode(FloatParameter.self, forKey: .inputHeightParameter)
        self.inputAngularResolutionParam = try container.decode(IntParameter.self, forKey: .inputAngularResolutionParameter)
        self.inputVerticalResolutionParam = try container.decode(IntParameter.self, forKey: .inputVerticalResolutionParameter)
        self.outputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .outputGeometryPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        var shouldOutputGeometry = false

        if self.inputRadius.valueDidChange
        {
            self.geometry.radius = self.inputRadius.value
            shouldOutputGeometry = true
        }
        
        if self.inputHeight.valueDidChange
        {
            self.geometry.height = self.inputHeight.value
            shouldOutputGeometry = true
        }
        
        if self.inputAngularResolutionParam.valueDidChange
        {
            self.geometry.angularResolution = self.inputAngularResolutionParam.value
            shouldOutputGeometry = true
        }
        
        if self.inputVerticalResolutionParam.valueDidChange
        {
            self.geometry.verticalResolution = self.inputVerticalResolutionParam.value
            shouldOutputGeometry = true
        }
        
        if shouldOutputGeometry
        {
            self.outputGeometry.send(self.geometry)
        }
     }
}
