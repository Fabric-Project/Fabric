//
//  NodeExecutionMode.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Foundation

extension Node
{
    public enum ExecutionMode
    {
        // A provider execution mode.
        // The node executes on demand—that is, whenever data is requested of it, but at most once per frame.
        case Provider
        
        // A processor execution mode.
        // The node executes whenever its inputs change or if the time change (assuming it’s time-dependent).

        case Processor
        
        // A consumer execution mode.
        // The node always executes assuming the value of its Enable input port is true. (The Enable port is automatically added by the system.)

        case Consumer
    }
}
