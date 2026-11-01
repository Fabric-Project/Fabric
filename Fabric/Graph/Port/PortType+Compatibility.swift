//
//  PortType+Compatibility.swift
//  Fabric
//
//  Created by Anton Marini on 12/22/25.
//

import Foundation

extension PortType
{
    func canConnect(to other: PortType) -> Bool
    {
        if self.isGenericArrayVirtual || other.isGenericArrayVirtual
        {
            return self.isArrayType && other.isArrayType
        }

        // Pure Virtual ports box arbitrary scalar and object values, Numeric
        // Virtual included. Keep this symmetric because canvas hit-testing may
        // ask compatibility from either the inlet or outlet side, and keep it
        // ahead of the Numeric Virtual rule below, which would otherwise refuse
        // a pure virtual wire.
        if self == .Virtual || other == .Virtual
        {
            return true
        }

        // Both sides have to be numeric: the Numeric Virtual side satisfies
        // this by definition, so the test is really about the other one.
        if self == .NumericVirtual || other == .NumericVirtual
        {
            return self.isNumericVirtualCompatible && other.isNumericVirtualCompatible
        }

        switch self
        {
        case .Array(portType: .Virtual):
            guard case .Array = other else { return false }
            return true

        case .Bool, .Int, .Float, .String:
            switch other
            {
            case .Bool, .Int, .Float, .String:
                return true
            default:
                return false
            }

        // Color and Vector4 share the same Swift type (simd_float4)
        case .Color, .Vector4:
            return other == .Color || other == .Vector4

        default:
            switch other
            {
            case .Array(portType: .Virtual):
                guard case .Array = self else { return false }
                return true
            default:
                return self.colorAsVector4 == other.colorAsVector4
            }
        }
    }

    // Color and Vector4 share the same Swift type (simd_float4), so collections
    // of them share theirs too. Other scalar conversions don't carry over:
    // nothing converts a collection of Bool to a collection of Float.
    private var colorAsVector4: PortType
    {
        switch self
        {
        case .Color:
            return .Vector4
        case .Array(portType: let elementType):
            return .Array(portType: elementType.colorAsVector4)
        case .Dictionary(valueType: let valueType):
            return .Dictionary(valueType: valueType.colorAsVector4)
        default:
            return self
        }
    }

    var isGenericArrayVirtual: Bool
    {
        if case .Array(portType: .Virtual) = self { return true }
        return false
    }

    var isArrayType: Bool
    {
        if case .Array = self { return true }
        return false
    }

    var isNumericVirtualCompatible: Bool
    {
        switch self
        {
        case .Int, .Float, .Vector2, .Vector3, .Vector4, .Color, .Quaternion, .Transform:
            return true
        case .Array(portType: let elementType):
            return elementType.isNumericVirtualCompatible
        case .NumericVirtual:
            return true
        default:
            return false
        }
    }
}
