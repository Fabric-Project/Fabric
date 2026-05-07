//
//  PortType+Compatibility.swift
//  Fabric
//
//  Created by Anton Marini on 12/22/25.
//

import Foundation

extension PortType
{
    // This is so terrible, needs to sync with below
    func canConnect(to other:PortType) -> Bool
    {
        switch self
        {
        case .Bool, .Int, .Float, .String, .Virtual:
            switch other
            {
            case .Bool, .Int, .Float, .String, .Virtual:
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
