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

        if self == .NumericVirtual || other == .NumericVirtual
        {
            return self.isNumericVirtualCompatible || other.isNumericVirtualCompatible
        }

        // Any connection involving a Virtual port is permitted.
        // The send path boxes typed→Virtual; Virtual→typed produces no value but is not blocked at connect time.
        if self == .Virtual || other == .Virtual { return true }

        switch self
        {
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
            return self == other
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
