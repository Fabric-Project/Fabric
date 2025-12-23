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
        self == other
    }    
}
