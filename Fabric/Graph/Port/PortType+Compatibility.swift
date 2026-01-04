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

        default:
            return self == other
        }
    }
}
