//
//  GraphRenderUserInfo.swift
//  Fabric
//
//  Created by Anton Marini on 6/21/25.
//

import Foundation
import AppKit

public struct GraphEvaluationContext : Hashable
{
    public static func == (lhs: GraphEvaluationContext, rhs: GraphEvaluationContext) -> Bool {

        return  lhs.iterationIndex == rhs.iterationIndex &&
                lhs.normalizedIndex == rhs.normalizedIndex &&
                lhs.frameNumber == rhs.frameNumber &&
                lhs.time == rhs.time &&
                lhs.events == rhs.events
            // User Info isnt comparable
        //        lhs.userInfo == rhs.userInfo
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(iterationIndex ?? 0)
        hasher.combine(normalizedIndex ?? 0)
        hasher.combine(frameNumber ?? 0)
        hasher.combine(time ?? 0)
    }
    
    public var iterationIndex: Int?
    public var normalizedIndex: Float?
    public var frameNumber: Int?
    public var time: TimeInterval?
    public var events: [NSEvent]?
    public var userInfo: [String: (any Hashable)] = [:]

    public subscript(key: String) -> Any?
    {
        userInfo[key]
    }
}
