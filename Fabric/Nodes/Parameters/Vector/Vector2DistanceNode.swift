//
//  Vector4ToFloatNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import simd
import Metal
import Accelerate

public class Vector2Distance : Node
{
    enum Vector2Distance : String, CaseIterable
    {
        case Eucledian
        case Manhattan
        case Cosine
        
        func distance(vectorA:simd_float2, vectorB:simd_float2) -> Float
        {
            switch self
            {
            case .Eucledian:
                return simd_distance_squared(vectorA, vectorB)
            case .Manhattan:
                return simd_distance(vectorA, vectorB)
            case .Cosine:
                let dotAB = simd_dot(vectorA, vectorB)
                let magA  = simd_length(vectorA)
                let magB  = simd_length(vectorB)
                
                // Cosine similarity = dot / (|a| * |b|)
                // Cosine distance   = 1 - similarity
                return 1.0 - (dotAB / (magA * magB + 1e-12)) // epsilon avoids NaN from zero vectors
            }
        }
    }
    
    override public class var name:String { "Vector 2 Distance" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Computes a distance metric between two Vector 2s"}

    // Ports
    public let inputMetricParam = ParameterPort(parameter:StringParameter("Distance Metric", Vector2Distance.Eucledian.rawValue, Vector2Distance.allCases.map({ $0.rawValue }), .dropdown, "Distance calculation method"))
    public let inputVectorAParam = ParameterPort(parameter:Float2Parameter("Vector 2", .zero, .inputfield, "First vector for distance calculation"))
    public let inputVectorBParam = ParameterPort(parameter:Float2Parameter("Vector 2", .zero, .inputfield, "Second vector for distance calculation"))
    public let outputDistancePort = NodePort<Float>(name: "Distance" , kind: .Outlet, description: "Calculated distance between the two vectors")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputMetricParam", port: self.inputMetricParam),
            PortDeclaration(key: "inputVectorAParam", port: self.inputVectorAParam),
            PortDeclaration(key: "inputVectorBParam", port: self.inputVectorBParam),
            PortDeclaration(key: "outputDistancePort", port: self.outputDistancePort),
        ]
    }

    // Port Proxies

    private var metric = Vector2Distance.Eucledian
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputMetricParam.valueDidChange,
           let inputMetric = self.inputMetricParam.value
        {
            if let metric:Vector2Distance = .init(rawValue: inputMetric)
            {
                self.metric = metric
            }
        }
        
        if self.inputVectorAParam.valueDidChange || self.inputVectorBParam.valueDidChange,
           let inputAVector = self.inputVectorAParam.value,
           let inputBVector = self.inputVectorBParam.value
        {
            let distance = self.metric.distance(vectorA: inputAVector, vectorB: inputBVector)
            
            self.outputDistancePort.send( distance )
        }
    }
}
