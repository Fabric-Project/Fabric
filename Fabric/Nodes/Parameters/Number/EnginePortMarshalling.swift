//
//  EnginePortMarshalling.swift
//  Fabric
//
//  Adapter between the standalone MathExpressionEngine's value model
//  (`ValueType` / `EngineValue`) and Fabric's port model (`PortType` /
//  `PortValue` / `NodePort`). Kept deliberately free of any Node/graph state so
//  the conversions can be unit-tested without a Metal device.
//
//  `Mat4` is column-major and laid out to match `simd_float4x4`; `Quat` is
//  (x, y, z, w) matching `simd_quatf`; on Apple `simd_float3 == SIMD3<Float>`.
//  So the boundary is a near-trivial reinterpret via the engine's public
//  `columns` / `components` accessors and the matching host constructors.
//

import Foundation
import simd
import Satin
import MathExpressionEngine

enum EnginePortMarshalling
{
    // MARK: - Types

    /// The Fabric port type that carries values of the given engine type.
    static func portType(for valueType: ValueType) -> PortType
    {
        switch valueType
        {
        case .float:            return .Float
        case .vec2:             return .Vector2
        case .vec3:             return .Vector3
        case .vec4:             return .Vector4
        case .transform:        return .Transform
        case .quat:             return .Quaternion
        case .array(let elem):  return .Array(portType: portType(for: elem))
        }
    }

    // MARK: - EngineValue -> PortValue (outputs)

    /// Box an engine value into Fabric's universal `PortValue`. Total.
    static func portValue(for value: EngineValue) -> PortValue
    {
        switch value
        {
        case .float(let f):      return .Float(f)
        case .vec2(let v):       return .Vector2(v)
        case .vec3(let v):       return .Vector3(v)                       // simd_float3 == SIMD3<Float>
        case .vec4(let v):       return .Vector4(v)
        case .transform(let m):  return .Transform(m)                     // Mat4 == simd_float4x4
        case .quat(let q):       return .Quaternion(q)                    // Quat == simd_quatf
        case .array(let els):    return .Array(ContiguousArray(els.map { portValue(for: $0) }))
        }
    }

    // MARK: - PortValue -> EngineValue (inputs)

    /// Unbox a Fabric `PortValue` into the engine value the given input port
    /// declares. Numeric widening (Bool/Int -> float) mirrors Fabric's own
    /// port-conversion rules. Returns nil if the boxed value can't satisfy the
    /// declared type (treated by callers as "input not yet available").
    static func engineValue(from portValue: PortValue, as type: ValueType) -> EngineValue?
    {
        switch (type, portValue)
        {
        case (.float, .Float(let f)):   return .float(f)
        case (.float, .Int(let i)):     return .float(Float(i))
        case (.float, .Bool(let b)):    return .float(b ? 1 : 0)

        case (.vec2, .Vector2(let v)):  return .vec2(v)
        case (.vec3, .Vector3(let v)):  return .vec3(v)
        case (.vec4, .Vector4(let v)):  return .vec4(v)

        case (.transform, .Transform(let m)): return .transform(m)
        case (.quat, .Quaternion(let q)):     return .quat(q)

        case (.array(let elem), .Array(let boxed)):
            var out: [EngineValue] = []
            out.reserveCapacity(boxed.count)
            for element in boxed
            {
                guard let v = engineValue(from: element, as: elem) else { return nil }
                out.append(v)
            }
            return .array(out)

        default:
            return nil
        }
    }

    // MARK: - Finiteness

    /// Whether every scalar component of the value is finite (recursively for
    /// arrays). Non-finite outputs are dropped rather than sent, matching the
    /// scalar Math Expression node's `output.isFinite` guard.
    static func isFinite(_ value: EngineValue) -> Bool
    {
        switch value
        {
        case .float(let f):      return f.isFinite
        case .vec2(let v):       return v.x.isFinite && v.y.isFinite
        case .vec3(let v):       return v.x.isFinite && v.y.isFinite && v.z.isFinite
        case .vec4(let v):       return v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite
        case .transform(let m):
            let c = m.columns
            return [c.0, c.1, c.2, c.3].allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite }
        case .quat(let q):
            let v = q.components
            return v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite
        case .array(let els):    return els.allSatisfy { isFinite($0) }
        }
    }

    // MARK: - Port factory

    /// Build an input (inlet) port for a declared engine input. `float` inputs
    /// are editable `ParameterPort`s (so an unconnected input still supplies a
    /// value, exactly like the old node); richer types are plain ports that
    /// stay nil until wired.
    static func makeInputPort(name: String, type: ValueType) -> Port
    {
        if case .float = type
        {
            return ParameterPort(parameter: FloatParameter(name, 0.0, .inputfield))
        }
        return makePort(name: name, type: type, kind: .Inlet)
    }

    /// Build an output (outlet) port for a declared engine output.
    static func makeOutputPort(name: String, type: ValueType) -> Port
    {
        makePort(name: name, type: type, kind: .Outlet)
    }

    private static func makePort(name: String, type: ValueType, kind: PortKind) -> Port
    {
        switch type
        {
        case .float:     return NodePort<Float>(name: name, kind: kind)
        case .vec2:      return NodePort<simd_float2>(name: name, kind: kind)
        case .vec3:      return NodePort<simd_float3>(name: name, kind: kind)
        case .vec4:      return NodePort<simd_float4>(name: name, kind: kind)
        case .transform: return NodePort<simd_float4x4>(name: name, kind: kind)
        case .quat:      return NodePort<simd_quatf>(name: name, kind: kind)
        case .array(let elem): return makeArrayPort(name: name, elementType: elem, kind: kind)
        }
    }

    private static func makeArrayPort(name: String, elementType: ValueType, kind: PortKind) -> Port
    {
        switch elementType
        {
        case .float:     return NodePort<ContiguousArray<Float>>(name: name, kind: kind)
        case .vec2:      return NodePort<ContiguousArray<simd_float2>>(name: name, kind: kind)
        case .vec3:      return NodePort<ContiguousArray<simd_float3>>(name: name, kind: kind)
        case .vec4:      return NodePort<ContiguousArray<simd_float4>>(name: name, kind: kind)
        case .transform: return NodePort<ContiguousArray<simd_float4x4>>(name: name, kind: kind)
        case .quat:      return NodePort<ContiguousArray<simd_quatf>>(name: name, kind: kind)
        // Nested arrays aren't representable as a Fabric port; fall back to a
        // flat float array so the port still exists (evaluation guards it).
        case .array:     return NodePort<ContiguousArray<Float>>(name: name, kind: kind)
        }
    }

    // MARK: - Reading inputs / sending outputs

    /// Read an input port's current value as the engine value its declared type
    /// expects, or nil when the upstream hasn't propagated a value yet.
    /// Dispatches by declared type to the correctly-typed `NodePort` (a
    /// `ParameterPort<Float>` satisfies `NodePort<Float>`).
    static func readEngineValue(from port: Port, as type: ValueType) -> EngineValue?
    {
        switch type
        {
        case .float:     return (port as? NodePort<Float>)?.value.map(EngineValue.float)
        case .vec2:      return (port as? NodePort<simd_float2>)?.value.map(EngineValue.vec2)
        case .vec3:      return (port as? NodePort<simd_float3>)?.value.map(EngineValue.vec3)
        case .vec4:      return (port as? NodePort<simd_float4>)?.value.map(EngineValue.vec4)
        case .transform: return (port as? NodePort<simd_float4x4>)?.value.map(EngineValue.transform)
        case .quat:      return (port as? NodePort<simd_quatf>)?.value.map(EngineValue.quat)
        case .array(let elem): return readArray(from: port, elementType: elem)
        }
    }

    private static func readArray(from port: Port, elementType: ValueType) -> EngineValue?
    {
        switch elementType
        {
        case .float:     return (port as? NodePort<ContiguousArray<Float>>)?.value.map { .array($0.map(EngineValue.float)) }
        case .vec2:      return (port as? NodePort<ContiguousArray<simd_float2>>)?.value.map { .array($0.map(EngineValue.vec2)) }
        case .vec3:      return (port as? NodePort<ContiguousArray<simd_float3>>)?.value.map { .array($0.map(EngineValue.vec3)) }
        case .vec4:      return (port as? NodePort<ContiguousArray<simd_float4>>)?.value.map { .array($0.map(EngineValue.vec4)) }
        case .transform: return (port as? NodePort<ContiguousArray<simd_float4x4>>)?.value.map { .array($0.map(EngineValue.transform)) }
        case .quat:      return (port as? NodePort<ContiguousArray<simd_quatf>>)?.value.map { .array($0.map(EngineValue.quat)) }
        case .array:     return nil // nested arrays unsupported
        }
    }

    /// Send an engine value out of the given outlet port, dispatching to the
    /// correctly-typed `NodePort.send`. Assumes the value is already known
    /// finite (callers scrub first). No-op if the port's type doesn't match.
    static func send(_ value: EngineValue, to port: Port)
    {
        switch value
        {
        case .float(let f):      (port as? NodePort<Float>)?.send(f)
        case .vec2(let v):       (port as? NodePort<simd_float2>)?.send(v)
        case .vec3(let v):       (port as? NodePort<simd_float3>)?.send(v)
        case .vec4(let v):       (port as? NodePort<simd_float4>)?.send(v)
        case .transform(let m):  (port as? NodePort<simd_float4x4>)?.send(m)
        case .quat(let q):       (port as? NodePort<simd_quatf>)?.send(q)
        case .array(let els):    sendArray(els, to: port)
        }
    }

    private static func sendArray(_ els: [EngineValue], to port: Port)
    {
        // Element type comes from the array's first element; an empty engine
        // array can't occur (the language forbids `[]`), so `first` is safe for
        // non-empty and we simply no-op on empty.
        guard let elementType = els.first?.type else { return }
        switch elementType
        {
        case .float:
            (port as? NodePort<ContiguousArray<Float>>)?.send(ContiguousArray(els.map(\.scalar)))
        case .vec2:
            (port as? NodePort<ContiguousArray<simd_float2>>)?.send(ContiguousArray(els.compactMap { if case .vec2(let v) = $0 { v } else { nil } }))
        case .vec3:
            (port as? NodePort<ContiguousArray<simd_float3>>)?.send(ContiguousArray(els.compactMap { if case .vec3(let v) = $0 { v } else { nil } }))
        case .vec4:
            (port as? NodePort<ContiguousArray<simd_float4>>)?.send(ContiguousArray(els.compactMap { if case .vec4(let v) = $0 { v } else { nil } }))
        case .transform:
            (port as? NodePort<ContiguousArray<simd_float4x4>>)?.send(ContiguousArray(els.compactMap { if case .transform(let m) = $0 { m } else { nil } }))
        case .quat:
            (port as? NodePort<ContiguousArray<simd_quatf>>)?.send(ContiguousArray(els.compactMap { if case .quat(let q) = $0 { q } else { nil } }))
        case .array:
            return // nested arrays unsupported
        }
    }
}
