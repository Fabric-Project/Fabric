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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputMetricParam",   ParameterPort(parameter:StringParameter("Distance Metric", Vector2Distance.Eucledian.rawValue, Vector2Distance.allCases.map({ $0.rawValue }), .dropdown, "Distance calculation method"))),
            ("inputVectorAParam",   ParameterPort(parameter:Float2Parameter("Vector 2", .zero, .inputfield, "First vector for distance calculation"))),
            ("inputVectorBParam",   ParameterPort(parameter:Float2Parameter("Vector 2", .zero, .inputfield, "Second vector for distance calculation"))),
            ("outputDistancePort",   NodePort<Float>(name: "Distance" , kind: .Outlet, description: "Calculated distance between the two vectors") ),
        ]
    }

    // Port Proxies
    public var inputMetricParam:ParameterPort<String> { port(named: "inputMetricParam") }
    public var inputVectorAParam:ParameterPort<simd_float2> { port(named: "inputVectorAParam") }
    public var inputVectorBParam:ParameterPort<simd_float2> { port(named: "inputVectorBParam") }
    public var outputDistancePort:NodePort<Float> { port(named: "outputDistancePort") }
    
    private var metric = Vector2Distance.Eucledian
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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
