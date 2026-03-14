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

// MARK: - Number Tween

public class NumberTweenNode : Node
{
    override public class var name:String { "Number Tween" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tween toward a target value over a duration using an easing curve" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputTarget", ParameterPort(parameter: FloatParameter("Target", 0.0, .inputfield, "The value to tween toward"))),
            ("inputDuration", ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", Easing.allCases.map( {$0.title()} ), .dropdown, "Easing curve"))),
            ("outputNumber", NodePort<Float>(name: NumberNode.name, kind: .Outlet, description: "Current tweened value")),
            ("outputProgress", NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")),
        ]
    }

    // Port Proxies
    public var inputTarget:ParameterPort<Float> { port(named: "inputTarget") }
    public var inputDuration:ParameterPort<Float> { port(named: "inputDuration") }
    public var inputEasing:ParameterPort<String> { port(named: "inputEasing") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
    public var outputProgress:NodePort<Float> { port(named: "outputProgress") }

    private let easingMap = Dictionary(uniqueKeysWithValues: zip(Easing.allCases.map( {$0.title()} ), Easing.allCases))

    // Tween state
    private var fromValue:Float = 0.0
    private var toValue:Float = 0.0
    private var tweenStartTime:TimeInterval = 0.0
    private var tweening:Bool = false
    private var currentOutput:Float = 0.0
    private var initialized:Bool = false

    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let time = context.timing.time

        // Detect target change → snap-retarget
        if self.inputTarget.valueDidChange,
           let newTarget = self.inputTarget.value
        {
            if !initialized
            {
                // First value received — jump to it immediately, no tween
                currentOutput = newTarget
                toValue = newTarget
                initialized = true
            }
            else if newTarget != toValue
            {
                fromValue = currentOutput
                toValue = newTarget
                tweenStartTime = time
                tweening = true
            }
        }

        // Drive the tween
        if tweening,
           let duration = self.inputDuration.value,
           let easingName = self.inputEasing.value,
           let easeFunc = easingMap[easingName]
        {
            let elapsed = time - tweenStartTime
            let d = max(Double(duration), 0.001)
            let t = min(elapsed / d, 1.0)
            let easedT = Float(easeFunc.function(t))

            currentOutput = fromValue + (toValue - fromValue) * easedT

            if t >= 1.0
            {
                currentOutput = toValue
                tweening = false
            }

            self.outputNumber.send(currentOutput)
            self.outputProgress.send(Float(t))
        }
        else if initialized
        {
            // Not tweening — hold current value
            self.outputNumber.send(currentOutput)
            self.outputProgress.send(tweening ? 0.0 : 1.0)
        }
    }
}
