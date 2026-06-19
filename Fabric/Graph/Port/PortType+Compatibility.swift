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
}
