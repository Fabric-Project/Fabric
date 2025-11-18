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

public class Vector3Distance : Node
{
    enum Vector3Distance : String, CaseIterable
    {
        case Eucledian
        case Manhattan
        case Cosine
        
        func distance(vectorA:simd_float3, vectorB:simd_float3) -> Float
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
    
    override public class var name:String { "Vector 3 Distance" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Computes a distance metric between two Vector 3s"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputMetricParam",   ParameterPort(parameter:StringParameter("Distance Metric", Vector3Distance.Eucledian.rawValue, Vector3Distance.allCases.map({ $0.rawValue }), .dropdown))),
            ("inputVectorAParam",   ParameterPort(parameter:Float3Parameter("Vector 3", .zero, .inputfield))),
            ("inputVectorBParam",   ParameterPort(parameter:Float3Parameter("Vector 3", .zero, .inputfield))),
            ("outputDistancePort",   NodePort<Float>(name: "Distance" , kind: .Outlet) ),
        ]
    }

    // Port Proxies
    public var inputMetricParam:ParameterPort<String> { port(named: "inputMetricParam") }
    public var inputVectorAParam:ParameterPort<simd_float3> { port(named: "inputVectorAParam") }
    public var inputVectorBParam:ParameterPort<simd_float3> { port(named: "inputVectorBParam") }
    public var outputDistancePort:NodePort<Float> { port(named: "outputDistancePort") }
    
    private var metric = Vector3Distance.Eucledian
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputMetricParam.valueDidChange,
           let inputMetric = self.inputMetricParam.value
        {
            if let metric:Vector3Distance = .init(rawValue: inputMetric)
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
