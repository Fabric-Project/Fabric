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

/// Drives a single-value tween toward a target using `TweenState` plus a
/// supplied interpolation function, so the tween nodes share one state machine.
/// `Value` is the emitted type; the interpolation closure may decode/encode
/// internally (e.g. quaternion slerp on a packed float4).
final class TweenDriver<Value: Equatable>
{
    private var tween = TweenState()
    private var from: Value?
    private var to: Value?
    private var current: Value?
    private let interpolate: (Value, Value, Float) -> Value

    init(interpolate: @escaping (Value, Value, Float) -> Value)
    {
        self.interpolate = interpolate
    }

    /// First call snaps to `target`; a later, distinct target tweens from the
    /// current value.
    func setTarget(_ target: Value, at time: TimeInterval)
    {
        guard current != nil else {
            from = target; to = target; current = target
            return
        }
        if let to, to != target {
            from = current
            self.to = target
            tween.start(at: time)
        }
    }

    /// The value and progress to emit this frame, or nil before the first target.
    func update(time: TimeInterval, duration: Float?, easingName: String?) -> (value: Value, progress: Float)?
    {
        guard let from, let to, let current else { return nil }

        if let duration, let easingName,
           let result = tween.update(time: time, duration: duration, easingName: easingName)
        {
            let value = result.t >= 1.0 ? to : interpolate(from, to, result.easedT)
            self.current = value
            return (value, result.t)
        }
        return (current, tween.tweening ? 0.0 : 1.0)
    }
}

/// Array equivalent of `TweenDriver`: per-element endpoints sharing one clock.
/// Emits once per settle (not every idle frame); emits an empty array before
/// the first target. When the target count grows, new elements start at target.
final class TweenArrayDriver<Value: Equatable>
{
    private var tween = TweenState()
    private var from: [Value] = []
    private var to: [Value] = []
    private var current: [Value] = []
    private var initialized = false
    private var pendingEmit = true
    private let interpolate: (Value, Value, Float) -> Value

    init(interpolate: @escaping (Value, Value, Float) -> Value)
    {
        self.interpolate = interpolate
    }

    func setTargets(_ targets: [Value], at time: TimeInterval)
    {
        if !initialized {
            from = targets; to = targets; current = targets
            initialized = true
            pendingEmit = true
        } else if targets != to {
            // Tween each element from its current value; elements beyond the
            // previous count start already at their target.
            var newFrom = [Value]()
            newFrom.reserveCapacity(targets.count)
            for i in 0..<targets.count {
                newFrom.append(i < current.count ? current[i] : targets[i])
            }
            from = newFrom; to = targets; current = newFrom
            tween.start(at: time)
            pendingEmit = true
        }
    }

    func update(time: TimeInterval, duration: Float?, easingName: String?) -> (values: ContiguousArray<Value>, progress: Float)?
    {
        if let duration, let easingName,
           let result = tween.update(time: time, duration: duration, easingName: easingName)
        {
            var output = ContiguousArray<Value>()
            output.reserveCapacity(to.count)
            for i in 0..<to.count {
                let value = result.t >= 1.0 ? to[i] : interpolate(from[i], to[i], result.easedT)
                current[i] = value
                output.append(value)
            }
            pendingEmit = false
            return (output, result.t)
        }
        if pendingEmit {
            pendingEmit = false
            return initialized
                ? (ContiguousArray(current), tween.tweening ? 0.0 : 1.0)
                : (ContiguousArray<Value>(), 1.0)
        }
        return nil
    }
}
