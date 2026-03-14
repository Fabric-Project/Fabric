//
//  PortType+DynamicPorts.swift
//  Fabric
//
//  Created by Codex on 3/13/26.
//

import Foundation
import Satin
import simd

extension PortType
{
    static func dynamicPort(for type: PortType,
                            name: String,
                            kind: PortKind,
                            description: String = "") -> Port
    {
        let shouldCreateParameterPort = kind == .Inlet

        switch type
        {
        case .Bool:
            if shouldCreateParameterPort {
                return ParameterPort(parameter: BoolParameter(name, false, .toggle, description))
            }
            return NodePort<Bool>(name: name, kind: kind, description: description)

        case .Int:
            if shouldCreateParameterPort {
                return ParameterPort(parameter: IntParameter(name, 0, .inputfield, description))
            }
            return NodePort<Int>(name: name, kind: kind, description: description)

        case .Float:
            if shouldCreateParameterPort {
                return ParameterPort(parameter: FloatParameter(name, 0.0, .inputfield, description))
            }
            return NodePort<Float>(name: name, kind: kind, description: description)

        case .String:
            if shouldCreateParameterPort {
                let parameter = StringParameter(name, "", [], .inputfield)
                parameter.description = description
                return ParameterPort(parameter: parameter)
            }
            return NodePort<String>(name: name, kind: kind, description: description)

        case .Vector2:
            if shouldCreateParameterPort {
                return ParameterPort(parameter: Float2Parameter(name, .zero, .inputfield, description))
            }
            return NodePort<simd_float2>(name: name, kind: kind, description: description)

        case .Vector3:
            if shouldCreateParameterPort {
                return ParameterPort(parameter: Float3Parameter(name, .zero, .inputfield, description))
            }
            return NodePort<simd_float3>(name: name, kind: kind, description: description)

        case .Vector4:
            if shouldCreateParameterPort {
                return ParameterPort(parameter: Float4Parameter(name, .zero, .inputfield, description))
            }
            return NodePort<simd_float4>(name: name, kind: kind, description: description)

        case .Color:
            if shouldCreateParameterPort {
                return ParameterPort(parameter: Float4Parameter(name, simd_float4(1, 1, 1, 1), .colorpicker, description))
            }
            return NodePort<simd_float4>(name: name, kind: kind, description: description)

        case .Quaternion:
            return NodePort<simd_float4>(name: name, kind: kind, description: description)

        case .Transform:
            return NodePort<simd_float4x4>(name: name, kind: kind, description: description)

        case .Geometry:
            return NodePort<SatinGeometry>(name: name, kind: kind, description: description)

        case .Material:
            return NodePort<Material>(name: name, kind: kind, description: description)

        case .Shader:
            return NodePort<Shader>(name: name, kind: kind, description: description)

        case .Image:
            return NodePort<FabricImage>(name: name, kind: kind, description: description)

        case .Virtual:
            return NodePort<PortValue>(name: name, kind: kind, description: description)

        case .Array(portType: let elementType):
            switch elementType
            {
            case .Bool:
                return NodePort<ContiguousArray<Bool>>(name: name, kind: kind, description: description)
            case .Int:
                return NodePort<ContiguousArray<Int>>(name: name, kind: kind, description: description)
            case .Float:
                return NodePort<ContiguousArray<Float>>(name: name, kind: kind, description: description)
            case .String:
                return NodePort<ContiguousArray<String>>(name: name, kind: kind, description: description)
            case .Vector2:
                return NodePort<ContiguousArray<simd_float2>>(name: name, kind: kind, description: description)
            case .Vector3:
                return NodePort<ContiguousArray<simd_float3>>(name: name, kind: kind, description: description)
            case .Vector4:
                return NodePort<ContiguousArray<simd_float4>>(name: name, kind: kind, description: description)
            case .Color:
                return NodePort<ContiguousArray<simd_float4>>(name: name, kind: kind, description: description)
            case .Quaternion:
                return NodePort<ContiguousArray<simd_float4>>(name: name, kind: kind, description: description)
            case .Transform:
                return NodePort<ContiguousArray<simd_float4x4>>(name: name, kind: kind, description: description)
            case .Geometry:
                return NodePort<ContiguousArray<SatinGeometry>>(name: name, kind: kind, description: description)
            case .Material:
                return NodePort<ContiguousArray<Material>>(name: name, kind: kind, description: description)
            case .Shader:
                return NodePort<ContiguousArray<Shader>>(name: name, kind: kind, description: description)
            case .Image:
                return NodePort<ContiguousArray<FabricImage>>(name: name, kind: kind, description: description)
            case .Virtual:
                return NodePort<ContiguousArray<PortValue>>(name: name, kind: kind, description: description)
            case .Array:
                return NodePort<PortValue>(name: name, kind: kind, description: description)
            }
        }
    }

    func send(boxedValue: PortValue?, on port: Port, force: Bool = false)
    {
        switch self
        {
        case .Bool:
            (port as? NodePort<Bool>)?.send(boxedValue.flatMap { Swift.Bool.fromPortValue($0) }, force: force)
        case .Int:
            (port as? NodePort<Int>)?.send(boxedValue.flatMap { Swift.Int.fromPortValue($0) }, force: force)
        case .Float:
            (port as? NodePort<Float>)?.send(boxedValue.flatMap { Swift.Float.fromPortValue($0) }, force: force)
        case .String:
            (port as? NodePort<String>)?.send(boxedValue.flatMap { Swift.String.fromPortValue($0) }, force: force)
        case .Vector2:
            (port as? NodePort<simd_float2>)?.send(boxedValue.flatMap(simd_float2.fromPortValue), force: force)
        case .Vector3:
            (port as? NodePort<simd_float3>)?.send(boxedValue.flatMap(simd_float3.fromPortValue), force: force)
        case .Vector4, .Color:
            (port as? NodePort<simd_float4>)?.send(boxedValue.flatMap(simd_float4.fromPortValue), force: force)
        case .Quaternion:
            (port as? NodePort<simd_float4>)?.send(self.quaternionVector(from: boxedValue), force: force)
        case .Transform:
            (port as? NodePort<simd_float4x4>)?.send(boxedValue.flatMap(simd_float4x4.fromPortValue), force: force)
        case .Geometry:
            (port as? NodePort<SatinGeometry>)?.send(boxedValue.flatMap(SatinGeometry.fromPortValue), force: force)
        case .Material:
            (port as? NodePort<Satin.Material>)?.send(boxedValue.flatMap(Satin.Material.fromPortValue), force: force)
        case .Shader:
            (port as? NodePort<Satin.Shader>)?.send(boxedValue.flatMap(Satin.Shader.fromPortValue), force: force)
        case .Image:
            (port as? NodePort<FabricImage>)?.send(boxedValue.flatMap(FabricImage.fromPortValue), force: force)
        case .Virtual:
            (port as? NodePort<PortValue>)?.send(boxedValue.flatMap(PortValue.fromPortValue), force: force)
        case .Array(portType: let elementType):
            elementType.send(arrayBoxedValue: boxedValue, on: port, force: force)
        }
    }

    private func send(arrayBoxedValue boxedValue: PortValue?, on port: Port, force: Bool)
    {
        switch self
        {
        case .Bool:
            (port as? NodePort<ContiguousArray<Bool>>)?.send(boxedValue.flatMap(ContiguousArray<Bool>.fromPortValue), force: force)
        case .Int:
            (port as? NodePort<ContiguousArray<Int>>)?.send(boxedValue.flatMap(ContiguousArray<Int>.fromPortValue), force: force)
        case .Float:
            (port as? NodePort<ContiguousArray<Float>>)?.send(boxedValue.flatMap(ContiguousArray<Float>.fromPortValue), force: force)
        case .String:
            (port as? NodePort<ContiguousArray<String>>)?.send(boxedValue.flatMap(ContiguousArray<String>.fromPortValue), force: force)
        case .Vector2:
            (port as? NodePort<ContiguousArray<simd_float2>>)?.send(boxedValue.flatMap(ContiguousArray<simd_float2>.fromPortValue), force: force)
        case .Vector3:
            (port as? NodePort<ContiguousArray<simd_float3>>)?.send(boxedValue.flatMap(ContiguousArray<simd_float3>.fromPortValue), force: force)
        case .Vector4, .Color:
            (port as? NodePort<ContiguousArray<simd_float4>>)?.send(boxedValue.flatMap(ContiguousArray<simd_float4>.fromPortValue), force: force)
        case .Quaternion:
            (port as? NodePort<ContiguousArray<simd_float4>>)?.send(self.quaternionVectorArray(from: boxedValue), force: force)
        case .Transform:
            (port as? NodePort<ContiguousArray<simd_float4x4>>)?.send(boxedValue.flatMap(ContiguousArray<simd_float4x4>.fromPortValue), force: force)
        case .Geometry:
            (port as? NodePort<ContiguousArray<SatinGeometry>>)?.send(boxedValue.flatMap(ContiguousArray<SatinGeometry>.fromPortValue), force: force)
        case .Material:
            (port as? NodePort<ContiguousArray<Satin.Material>>)?.send(boxedValue.flatMap(ContiguousArray<Satin.Material>.fromPortValue), force: force)
        case .Shader:
            (port as? NodePort<ContiguousArray<Satin.Shader>>)?.send(boxedValue.flatMap(ContiguousArray<Satin.Shader>.fromPortValue), force: force)
        case .Image:
            (port as? NodePort<ContiguousArray<FabricImage>>)?.send(boxedValue.flatMap(ContiguousArray<FabricImage>.fromPortValue), force: force)
        case .Virtual:
            (port as? NodePort<ContiguousArray<PortValue>>)?.send(boxedValue.flatMap(ContiguousArray<PortValue>.fromPortValue), force: force)
        case .Array:
            (port as? NodePort<PortValue>)?.send(boxedValue, force: force)
        }
    }

    private func quaternionVector(from boxedValue: PortValue?) -> simd_float4?
    {
        guard let boxedValue else { return nil }

        switch boxedValue
        {
        case .Vector4(let value):
            return value
        case .Quaternion(let value):
            return value.vector
        default:
            return nil
        }
    }

    private func quaternionVectorArray(from boxedValue: PortValue?) -> ContiguousArray<simd_float4>?
    {
        guard let boxedValue else { return nil }

        switch boxedValue
        {
        case .Array(let values):
            var converted = ContiguousArray<simd_float4>()
            converted.reserveCapacity(values.count)

            for value in values {
                guard let vector = self.quaternionVector(from: value) else { return nil }
                converted.append(vector)
            }

            return converted

        default:
            return nil
        }
    }
}
