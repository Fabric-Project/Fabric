//
//  NumericValueOperations.swift
//  Fabric
//

import Foundation
import simd

public enum NumericDistanceMetric: String, CaseIterable
{
    case euclidean = "Euclidean"
    case manhattan = "Manhattan"
    case cosine = "Cosine"
}

enum NumericValueOperations
{
    static func interpolate(_ a: PortValue, _ b: PortValue, t: Float, as portType: PortType) -> PortValue?
    {
        let clampedT = min(max(t, 0), 1)

        switch portType
        {
        case .Int:
            guard case .Int(let av) = a, case .Int(let bv) = b else { return nil }
            return .Int(Int(round(Float(av) + (Float(bv) - Float(av)) * clampedT)))
        case .Float:
            guard case .Float(let av) = a, case .Float(let bv) = b else { return nil }
            return .Float(simd_mix(av, bv, clampedT))
        case .Vector2:
            guard case .Vector2(let av) = a, case .Vector2(let bv) = b else { return nil }
            return .Vector2(simd_mix(av, bv, simd_float2(repeating: clampedT)))
        case .Vector3:
            guard case .Vector3(let av) = a, case .Vector3(let bv) = b else { return nil }
            return .Vector3(simd_mix(av, bv, simd_float3(repeating: clampedT)))
        case .Vector4:
            guard case .Vector4(let av) = a, case .Vector4(let bv) = b else { return nil }
            return .Vector4(simd_mix(av, bv, simd_float4(repeating: clampedT)))
        case .Color:
            guard case .Vector4(let av) = a, case .Vector4(let bv) = b else { return nil }
            return .Vector4(interpolateColor(av, bv, t: clampedT))
        case .Quaternion:
            guard case .Quaternion(let av) = a, case .Quaternion(let bv) = b else { return nil }
            return .Quaternion(simd_slerp(av.normalized, bv.normalized, clampedT))
        case .Transform:
            guard case .Transform(let av) = a, case .Transform(let bv) = b else { return nil }
            return .Transform(simd_float4x4(
                simd_mix(av.columns.0, bv.columns.0, simd_float4(repeating: clampedT)),
                simd_mix(av.columns.1, bv.columns.1, simd_float4(repeating: clampedT)),
                simd_mix(av.columns.2, bv.columns.2, simd_float4(repeating: clampedT)),
                simd_mix(av.columns.3, bv.columns.3, simd_float4(repeating: clampedT))
            ))
        default:
            return nil
        }
    }

    static func distance(_ a: PortValue, _ b: PortValue, as portType: PortType, metric: NumericDistanceMetric) -> Float?
    {
        switch portType
        {
        case .Int:
            guard case .Int(let av) = a, case .Int(let bv) = b else { return nil }
            return abs(Float(av - bv))
        case .Float:
            guard case .Float(let av) = a, case .Float(let bv) = b else { return nil }
            return abs(av - bv)
        case .Vector2:
            guard case .Vector2(let av) = a, case .Vector2(let bv) = b else { return nil }
            return vectorDistance(av, bv, metric: metric)
        case .Vector3:
            guard case .Vector3(let av) = a, case .Vector3(let bv) = b else { return nil }
            return vectorDistance(av, bv, metric: metric)
        case .Vector4, .Color:
            guard case .Vector4(let av) = a, case .Vector4(let bv) = b else { return nil }
            if portType == .Color
            {
                let rgbDistance = vectorDistance(simd_float3(av.x, av.y, av.z), simd_float3(bv.x, bv.y, bv.z), metric: metric) ?? 0
                return rgbDistance + abs(av.w - bv.w)
            }
            return vectorDistance(av, bv, metric: metric)
        case .Quaternion:
            guard case .Quaternion(let av) = a, case .Quaternion(let bv) = b else { return nil }
            let dot = abs(simd_dot(av.normalized.vector, bv.normalized.vector))
            return 2 * acos(min(max(dot, 0), 1))
        case .Transform:
            guard case .Transform(let av) = a, case .Transform(let bv) = b else { return nil }
            let delta = av - bv
            let squared = simd_dot(delta.columns.0, delta.columns.0)
                + simd_dot(delta.columns.1, delta.columns.1)
                + simd_dot(delta.columns.2, delta.columns.2)
                + simd_dot(delta.columns.3, delta.columns.3)
            return sqrt(squared)
        default:
            return nil
        }
    }

    static func arrayValues(from boxed: PortValue?) -> ContiguousArray<PortValue>?
    {
        guard let boxed, case .Array(let values) = boxed else { return nil }
        return values
    }

    static func interpolateArrays(_ a: ContiguousArray<PortValue>,
                                  _ b: ContiguousArray<PortValue>,
                                  t: Float,
                                  elementType: PortType) -> ContiguousArray<PortValue>
    {
        let count = min(a.count, b.count)
        var output = ContiguousArray<PortValue>()
        output.reserveCapacity(count)
        for index in 0..<count
        {
            if let value = interpolate(a[index], b[index], t: t, as: elementType)
            {
                output.append(value)
            }
        }
        return output
    }

    static func distanceArrays(_ a: ContiguousArray<PortValue>,
                               _ b: ContiguousArray<PortValue>,
                               elementType: PortType,
                               metric: NumericDistanceMetric) -> ContiguousArray<PortValue>
    {
        let count = min(a.count, b.count)
        var output = ContiguousArray<PortValue>()
        output.reserveCapacity(count)
        for index in 0..<count
        {
            if let value = distance(a[index], b[index], as: elementType, metric: metric)
            {
                output.append(.Float(value))
            }
        }
        return output
    }

    static func resampleArray(_ source: ContiguousArray<PortValue>,
                              count: Int,
                              elementType: PortType) -> ContiguousArray<PortValue>
    {
        guard count > 0, !source.isEmpty else { return [] }
        guard count > 1 else { return [source[0]] }

        let lastIndex = Float(source.count - 1)
        let divisor = Float(count - 1)
        var output = ContiguousArray<PortValue>()
        output.reserveCapacity(count)

        for index in 0..<count
        {
            let sourcePosition = (Float(index) / divisor) * lastIndex
            let lowerIndex = Int(sourcePosition)
            let upperIndex = min(lowerIndex + 1, source.count - 1)
            let t = sourcePosition - Float(lowerIndex)
            if let value = interpolate(source[lowerIndex], source[upperIndex], t: t, as: elementType)
            {
                output.append(value)
            }
        }

        return output
    }

    private static func vectorDistance<V>(_ a: V, _ b: V, metric: NumericDistanceMetric) -> Float? where V: SIMD, V.Scalar == Float
    {
        switch metric
        {
        case .euclidean:
            return sqrt((a - b).indices.reduce(Float(0)) { partialResult, index in
                let delta = a[index] - b[index]
                return partialResult + delta * delta
            })
        case .manhattan:
            return (a - b).indices.reduce(Float(0)) { partialResult, index in
                partialResult + abs(a[index] - b[index])
            }
        case .cosine:
            var dot = Float(0)
            var lengthASquared = Float(0)
            var lengthBSquared = Float(0)
            for index in a.indices
            {
                dot += a[index] * b[index]
                lengthASquared += a[index] * a[index]
                lengthBSquared += b[index] * b[index]
            }
            let lengthProduct = sqrt(lengthASquared) * sqrt(lengthBSquared)
            guard lengthProduct > 0 else { return 0 }
            return 1 - (dot / lengthProduct)
        }
    }

    private static func interpolateColor(_ a: simd_float4, _ b: simd_float4, t: Float) -> simd_float4
    {
        let fromLab = linearSRGBToOklab(simd_float3(a.x, a.y, a.z))
        let toLab = linearSRGBToOklab(simd_float3(b.x, b.y, b.z))
        let lab = simd_mix(fromLab, toLab, simd_float3(repeating: t))
        let rgb = oklabToLinearSRGB(lab)
        return simd_float4(rgb.x, rgb.y, rgb.z, simd_mix(a.w, b.w, t))
    }

    private static func linearSRGBToOklab(_ color: simd_float3) -> simd_float3
    {
        let l = 0.4122214708 * color.x + 0.5363325363 * color.y + 0.0514459929 * color.z
        let m = 0.2119034982 * color.x + 0.6806995451 * color.y + 0.1073969566 * color.z
        let s = 0.0883024619 * color.x + 0.2220049073 * color.y + 0.6896926158 * color.z

        let lRoot = cbrtf(l)
        let mRoot = cbrtf(m)
        let sRoot = cbrtf(s)

        return simd_float3(
            0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
            1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
            0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot
        )
    }

    private static func oklabToLinearSRGB(_ lab: simd_float3) -> simd_float3
    {
        let lRoot = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let mRoot = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let sRoot = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z

        let l = lRoot * lRoot * lRoot
        let m = mRoot * mRoot * mRoot
        let s = sRoot * sRoot * sRoot

        return simd_float3(
             4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }
}
