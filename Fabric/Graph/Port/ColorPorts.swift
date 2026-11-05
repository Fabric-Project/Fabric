//
//  ColorPorts.swift
//  Fabric
//

import Foundation
import simd


public final class ColorNodePort: NodePort<simd_float4>
{
    override public var portType: PortType { .Color }
}

public final class ColorArrayNodePort: NodePort<ContiguousArray<simd_float4>>
{
    override public var portType: PortType { .Array(portType: .Color) }
}
