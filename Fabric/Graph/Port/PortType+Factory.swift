//
//  PortType+Factory.swift
//  Fabric
//
//  Created by Anton Marini on 12/22/25.
//

import Foundation

extension PortType
{
    public static func portForType(_ type:PortType, isParameterPort:Bool, decoder:Decoder) throws -> Port?
    {
        switch type
        {
        case .Bool: return try isParameterPort ? ParameterPort<Bool>.init(from: decoder) : NodePort<Bool>.init(from: decoder)
        case .Float: return try isParameterPort ? ParameterPort<Float>.init(from: decoder) : NodePort<Float>.init(from: decoder)
        case .Int: return try isParameterPort ? ParameterPort<Int>.init(from: decoder) : NodePort<Int>.init(from: decoder)
        case .String: return try isParameterPort ? ParameterPort<String>.init(from: decoder) : NodePort<String>.init(from: decoder)
        case .Vector2: return try isParameterPort ?  ParameterPort<simd_float2>.init(from: decoder) : NodePort<simd_float2>.init(from: decoder)
        case .Vector3: return try isParameterPort ?  ParameterPort<simd_float3>.init(from: decoder) : NodePort<simd_float3>.init(from: decoder)
        case .Vector4: return try isParameterPort ?  ParameterPort<simd_float4>.init(from: decoder) : NodePort<simd_float4>.init(from: decoder)
        case .Color: return try isParameterPort ?  ParameterPort<simd_float4>.init(from: decoder) : NodePort<simd_float4>.init(from: decoder)
            
        case .Quaternion : return try NodePort<simd_float4>.init(from: decoder)
        case .Transform : return try NodePort<simd_float4x4>.init(from: decoder)
        case .Geometry: return try NodePort<Satin.Geometry>.init(from: decoder)
        case .Material: return try NodePort<Satin.Material>.init(from: decoder)
        case .Shader: return try NodePort<Satin.Shader>.init(from: decoder)
        case .Image: return try NodePort<FabricImage>.init(from: decoder)
        case .Virtual: return try NodePort<AnyLoggable>.init(from: decoder)
        // TODO: Array
        case .Array(portType: let arrayType):
            switch arrayType
            {
            case .Bool: return try isParameterPort ? ParameterPort<ContiguousArray<Bool>>.init(from: decoder) : NodePort<ContiguousArray<Bool>>.init(from: decoder)
            case .Float: return try isParameterPort ? ParameterPort<ContiguousArray<Float>>.init(from: decoder) : NodePort<ContiguousArray<Float>>.init(from: decoder)
            case .Int: return try isParameterPort ? ParameterPort<ContiguousArray<Int>>.init(from: decoder) : NodePort<ContiguousArray<Int>>.init(from: decoder)
            case .String: return try isParameterPort ? ParameterPort<ContiguousArray<String>>.init(from: decoder) : NodePort<ContiguousArray<String>>.init(from: decoder)
            case .Vector2: return try isParameterPort ?  ParameterPort<ContiguousArray<simd_float2>>.init(from: decoder) : NodePort<ContiguousArray<simd_float2>>.init(from: decoder)
            case .Vector3: return try isParameterPort ?  ParameterPort<ContiguousArray<simd_float3>>.init(from: decoder) : NodePort<ContiguousArray<simd_float3>>.init(from: decoder)
            case .Vector4: return try isParameterPort ?  ParameterPort<ContiguousArray<simd_float4>>.init(from: decoder) : NodePort<ContiguousArray<simd_float4>>.init(from: decoder)
            case .Color: return try isParameterPort ?  ParameterPort<ContiguousArray<simd_float4>>.init(from: decoder) : NodePort<ContiguousArray<simd_float4>>.init(from: decoder)
                
            case .Quaternion: return try NodePort<ContiguousArray<simd_float4>>.init(from: decoder)
            case .Transform: return try NodePort<ContiguousArray<simd_float4x4>>.init(from: decoder)
            case .Geometry: return try NodePort<ContiguousArray<Satin.Geometry>>.init(from: decoder)
            case .Material: return try NodePort<ContiguousArray<Satin.Material>>.init(from: decoder)
            case .Shader: return try NodePort<ContiguousArray<Satin.Shader>>.init(from: decoder)
            case .Image: return try NodePort<ContiguousArray<FabricImage>>.init(from: decoder)

            case .Virtual: return try NodePort<ContiguousArray<AnyLoggable>>.init(from: decoder)

            // we dont yet support nested arrays///
            case .Array(portType: _):
                return nil
            }
        }
        
        
    }
    
    public static func portForType(from parameter:(any Parameter)) -> Port?
    {
    //        print(self.name, "parameterToPort", parameter.label)
                    
            switch parameter.type
            {
                
            case .generic:
               
                if let genericParam = parameter as? GenericParameter<Int>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
                if let genericParam = parameter as? GenericParameter<Float>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
                if let genericParam = parameter as? GenericParameter<simd_float3>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
                if let genericParam = parameter as? GenericParameter<simd_float4>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
                if let genericParam = parameter as? GenericParameter<simd_quatf>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .string:
                
                if let genericParam = parameter as? StringParameter
                {
                    return ParameterPort(parameter: genericParam)
                }

            case .bool:

                if let genericParam = parameter as? BoolParameter
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .int:
                
                if let genericParam = parameter as? IntParameter
                {
                    return ParameterPort(parameter: genericParam)
                }

                else if let genericParam = parameter as? GenericParameter<Int>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .float:
                
                if let genericParam = parameter as? FloatParameter
                {
                    return ParameterPort(parameter: genericParam)
                }

                else if let genericParam = parameter as? GenericParameter<Float>
                {
                    return ParameterPort(parameter: genericParam)
                }

            case .float2:
                if let genericParam = parameter as? Float2Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .float3:
                if let genericParam = parameter as? Float3Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .float4:
                if let genericParam = parameter as? Float4Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }
                
                else if let genericParam = parameter as? GenericParameter<simd_float4>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .float4x4:
                if let genericParam = parameter as? Float4x4Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }

            default:
                return nil

            }
            
            return nil
        
    }

}
