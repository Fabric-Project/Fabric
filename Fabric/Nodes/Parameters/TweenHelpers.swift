//
//  TweenHelpers.swift
//  Fabric
//
//  Shared easing lookup and tween timing state used by tween nodes.
//

import Foundation
import Satin

/// Shared easing lookup used by tween and ease nodes
public enum TweenEasing
{
    public static let titles = Easing.allCases.map { $0.title() }
    public static let map = Dictionary(uniqueKeysWithValues: zip(titles, Easing.allCases))
}

/// Tracks tween timing state: start time, progress, and whether a tween is active.
/// Used by NumberTweenNode, ColorTweenNode, and OrientationTweenNode.
struct TweenState
{
    var startTime:TimeInterval = 0.0
    var tweening:Bool = false
    var initialized:Bool = false

    /// Compute normalized progress and eased t for the current frame.
    /// Returns nil if not currently tweening.
    mutating func update(time:TimeInterval, duration:Float, easingName:String) -> (t:Float, easedT:Float)?
    {
        guard tweening,
              let easeFunc = TweenEasing.map[easingName]
        else { return nil }

        let elapsed = time - startTime
        let d = max(Double(duration), 0.001)
        let t = min(elapsed / d, 1.0)
        let easedT = Float(easeFunc.function(t))

        if t >= 1.0
        {
            tweening = false
        }

        return (Float(t), easedT)
    }

    /// Begin a new tween from the current time.
    mutating func start(at time:TimeInterval)
    {
        startTime = time
        tweening = true
    }
}
