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

/// The graph executes at Satin's frame time: one per frame, shared by every execution in it.
public typealias GraphExecutionTiming = FrameTime

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
public class GraphExecutionInfo : Hashable
{
    public static func == (lhs: GraphExecutionInfo, rhs: GraphExecutionInfo) -> Bool
    {
        return lhs.hashValue == rhs.hashValue
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.timing)
        hasher.combine(self.iterationInfo)
        hasher.combine(self.eventInfo)
    }

    /// GraphRenderTiming information specific to the current execution
    public let timing:GraphExecutionTiming

    /// Should part of graph require multuple evaluations for a single execution request, the nodes will have `GraphIterationInfo` available to them
    public var iterationInfo: GraphIterationInfo? = nil

    /// Any events pertinent for the current execution
    public let eventInfo:GraphEventInfo?
    
    public var userInfo: [String: (any Hashable)] = [:]

    public init(timing: GraphExecutionTiming,
                iterationInfo: GraphIterationInfo? = nil,
                eventInfo:GraphEventInfo? = nil,
                userInfo: [String : any Hashable] = [:])
    {
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
