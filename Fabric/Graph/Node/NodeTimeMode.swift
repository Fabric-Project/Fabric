//
//  NodeTimeMode.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Foundation
extension Node
{
    public enum TimeMode
    {
        // No time dependency.
        // The node does not depend on time at all.
        // (It does not use the time parameter of the execute(context:renderPassDescriptor:commandBuffer:) method.)
        case None
        
        // An idle time dependency.
        // The custom patch does not depend on time but needs the system to execute it periodically.
        // For example if the custom patch connects to a piece of hardware, to ensure that it pulls data from the hardware, you would set the custom patch time dependency to idle time mode. This time mode is typically used with providers
        case Idle
        
        // A time base dependency.
        // The custom patch does depend on time explicitly and has a time base defined by the system. (It uses the time parameter of the execute(context:renderPassDescriptor:commandBuffer:) method.)

        case TimeBase
    }
}
