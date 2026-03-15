//
//  FloatTween.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//


import Foundation
import Satin
import simd
import Metal

public class NumberEaseNode : Node
{
    override public class var name:String { "Number Ease" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None } // TODO: Should this change?
    override public class var nodeDescription: String { "Run an easing on an input Number between 0 and 1 and return the resulting Eased Number"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield, "Normalized input value (0-1) to apply easing to"))),
            ("inputParam", ParameterPort(parameter: StringParameter("Easing", "Linear", Easing.allCases.map( {$0.title()} ), .dropdown, "Easing function to apply to the input")) ),
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet, description: "The eased output value")),
        ]
    }

    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var inputParam:ParameterPort<String> { port(named: "inputParam") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }

    private let easingMap = Dictionary(uniqueKeysWithValues: zip(Easing.allCases.map( {$0.title()}), Easing.allCases)  )

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputNumber.valueDidChange,
           let param = self.inputParam.value,
           let easeFunc = easingMap[param],
           let loopedTime = self.inputNumber.value//.truncatingRemainder(dividingBy: duration) // TODO: ?? should we loop by 1.0?
        {
            self.outputNumber.send( Float( easeFunc.function( Double(loopedTime) ) ) )
        }
     }
}

// MARK: - Tween Helpers

/// Shared easing lookup used by tween nodes
let tweenEasingMap = Dictionary(uniqueKeysWithValues: zip(Easing.allCases.map( {$0.title()} ), Easing.allCases))

/// Tracks tween timing state: start time, progress, and whether a tween is active.
/// Used by NumberTweenNode and ColorTweenNode.
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
              let easeFunc = tweenEasingMap[easingName]
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
