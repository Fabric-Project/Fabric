//
//  GraphRenderUserInfo.swift
//  Fabric
//
//  Created by Anton Marini on 6/21/25.
//

import Foundation
import Satin

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// GraphRenderTiming is constructed for every render call
public struct GraphExecutionTiming : Hashable
{
    /// Relative time based on when rendering started
    public let time:TimeInterval
    
    /// Absolute Difference between consecutive excecute calls made GraphRenderer
    public let deltaTime:TimeInterval

    /// If execution  is being displayed to a screen, this is the time when is expect content to appear on screen. Niave implementations may have `time` == `displayTime` while more advanced implementations may have displayTime lead time by a fraction of the frame rate.
    public let displayTime:TimeInterval?
    
    /// System absolute time when graph execution  as reequested
    public let systemTime:TimeInterval
    
    /// The frame number being requested
    public let frameNumber:Int
}

public struct GraphEventInfo : Hashable
{
#if os(macOS)
    public var events: [NSEvent]?
    public var mousePosition:CGPoint?

#elseif os(iOS)
    public var events: [UIEvent]?
#endif
    
}

/// If the graph contains iterator information (ie, we expect part of the graph to be evaluated multiple times) this struct is populated
public struct GraphIterationInfo : Hashable
{
    /// the iterator node responsible for this info, should there be more than one
    public let iteratorNodeID:UUID
    
    /// Total number of iterations expected
    public let totalIterationCount:Int
    /// For the current evaluation, the current iteration index
    public let currentIteration:Int
    
    public var normalizedCurrentIteration:Float { Float(self.currentIteration) / Float(self.totalIterationCount) }
}

/// Graph Execution Information that includes metal, timing, node, and custom user info
public struct GraphExecutionContext : Hashable
{
    public static func == (lhs: GraphExecutionContext, rhs: GraphExecutionContext) -> Bool
    {
        return lhs.hashValue == rhs.hashValue
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.context)
        hasher.combine(self.timing)
        hasher.combine(self.iterationInfo)
        hasher.combine(self.eventInfo)
    }
    
    /// The Satin metal rendering context
    public let context:Context

    /// GraphRenderTiming information specific to the current execution
    public let timing:GraphExecutionTiming

    /// Should part of graph require multuple evaluations for a single exectuion request, the nodes will have `GraphIterationInfo` available to them
    public var iterationInfo: GraphIterationInfo?

    /// Any events pertinent for the current execution
    public let eventInfo:GraphEventInfo?
    
    public var userInfo: [String: (any Hashable)] = [:]

    public subscript(key: String) -> Any?
    {
        userInfo[key]
    }
    
    
    
}
