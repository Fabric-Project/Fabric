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
    
    /// Absolute Difference between consecutive execute calls made GraphRenderer
    public let deltaTime:TimeInterval

    /// If execution is being displayed to a screen, this is the time when is expect content to appear on screen. Naive implementations may have `time` == `displayTime` while more advanced implementations may have displayTime lead time by a fraction of the frame rate.
    public let displayTime:TimeInterval?
    
    /// System absolute time when graph execution as requested
    public let systemTime:TimeInterval
    
    /// The frame number being requested
    public let frameNumber:Int
    
    public init(time: TimeInterval, deltaTime: TimeInterval, displayTime: TimeInterval?, systemTime: TimeInterval, frameNumber: Int) {
        self.time = time
        self.deltaTime = deltaTime
        self.displayTime = displayTime
        self.systemTime = systemTime
        self.frameNumber = frameNumber
    }
}

public struct GraphEventInfo : Hashable
{
#if os(macOS)
    public var event: NSEvent?
    public init(event: NSEvent?)
    {
        self.event = event
    }
#elseif os(iOS)
    public var event: UIEvent?
    public init(event: UIEvent?)
    {
        self.event = event
    }
#endif
    
    
}

/// If the graph contains iterator information (ie, we expect part of the graph to be evaluated multiple times) this struct is populated
public struct GraphIterationInfo : Hashable
{
    /// the iterator node responsible for this info, should there be more than one
//    public let iteratorNodeID:UUID
    
    /// Total number of iterations expected
    public let totalIterationCount:Int
    /// For the current evaluation, the current iteration index
    public let currentIteration:Int
    
    public var normalizedCurrentIteration:Float { max(0, Float(self.currentIteration ) / Float(self.totalIterationCount - 1) ) }
}

/// Graph Execution Information that includes metal, timing, node, and custom user info
public class GraphExecutionContext : Hashable
{
    public static func == (lhs: GraphExecutionContext, rhs: GraphExecutionContext) -> Bool
    {
        return lhs.hashValue == rhs.hashValue
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.graphRenderer?.id)
        hasher.combine(self.timing)
        hasher.combine(self.iterationInfo)
        hasher.combine(self.eventInfo)
    }
    
    public weak var graphRenderer: GraphRenderer?

    /// GraphRenderTiming information specific to the current execution
    public let timing:GraphExecutionTiming

    /// Should part of graph require multuple evaluations for a single execution request, the nodes will have `GraphIterationInfo` available to them
    public var iterationInfo: GraphIterationInfo? = nil

    /// Any events pertinent for the current execution
    public let eventInfo:GraphEventInfo?
    
    public var userInfo: [String: (any Hashable)] = [:]

    public init(graphRenderer: GraphRenderer,
                timing: GraphExecutionTiming,
                iterationInfo: GraphIterationInfo? = nil,
                eventInfo:GraphEventInfo? = nil,
                userInfo: [String : any Hashable] = [:])
    {
        self.graphRenderer = graphRenderer
        self.timing = timing
        self.iterationInfo = iterationInfo
        self.userInfo = userInfo
        self.eventInfo = eventInfo
    }
    
    public subscript(key: String) -> Any?
    {
        userInfo[key]
    }
    
    
    
}
