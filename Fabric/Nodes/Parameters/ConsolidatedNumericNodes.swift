//
//  ConsolidatedNumericNodes.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

private let singleNumericTypes: [PortType] = [.Float, .Int, .Vector2, .Vector3, .Vector4, .Color, .Quaternion, .Transform]
private let interpolatableSingleTypes: [PortType] = [.Float, .Vector2, .Vector3, .Vector4, .Color, .Quaternion, .Transform]
private let interpolatableArrayTypes: [PortType] = interpolatableSingleTypes.map { .Array(portType: $0) }

private func metricParameter(_ description: String) -> ParameterPort<String>
{
    ParameterPort(parameter: StringParameter(
        "Distance Metric",
        NumericDistanceMetric.euclidean.rawValue,
        NumericDistanceMetric.allCases.map(\.rawValue),
        .dropdown,
        description
    ))
}

private func currentMetric(from port: ParameterPort<String>) -> NumericDistanceMetric
{
    guard let value = port.value else { return .euclidean }
    return NumericDistanceMetric(rawValue: value) ?? .euclidean
}

public final class DistanceNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Distance" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Computes a domain-aware distance between two numeric values. Choose the value type in Settings." }
    public override class var supportedPortTypes: [PortType] { singleNumericTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputMetric", metricParameter("Distance calculation method")),
            ("outputDistance", NodePort<Float>(name: "Distance", kind: .Outlet, description: "Calculated distance"))
        ]
    }

    public var inputMetric: ParameterPort<String> { port(named: "inputMetric") }
    public var outputDistance: NodePort<Float> { port(named: "outputDistance") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = selectedNumericPortType

        addOrReplaceDynamicPort(name: "inputA", displayName: "A", portType: portType, kind: .Inlet, description: "First value", editable: true)
        addOrReplaceDynamicPort(name: "inputB", displayName: "B", portType: portType, kind: .Inlet, description: "Second value", editable: true)
        reorderPorts(named: ["inputA", "inputB", "inputMetric", "outputDistance"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputA") || specializeFromConnectedPort(named: "inputB") { return }
        guard let inputA: Port = findPort(named: "inputA"),
              let inputB: Port = findPort(named: "inputB"),
              inputA.valueDidChange || inputB.valueDidChange || inputMetric.valueDidChange,
              let valueA = inputA.snapshotValue(),
              let valueB = inputB.snapshotValue()
        else { return }

        let portType = selectedNumericPortType
        guard portType != .NumericVirtual,
              let distance = NumericValueOperations.distance(valueA, valueB, as: portType, metric: currentMetric(from: inputMetric))
        else { return }

        outputDistance.send(distance)
    }
}

public final class PairwiseDistanceArrayNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Pairwise Distance Array" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Computes one distance per pair of elements from two numeric arrays using zip-shortest." }
    public override class var supportedPortTypes: [PortType] { singleNumericTypes.map { .Array(portType: $0) } }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputMetric", metricParameter("Distance calculation method")),
            ("outputDistances", NodePort<ContiguousArray<Float>>(name: "Distances", kind: .Outlet, description: "Per-element distances"))
        ]
    }

    public var inputMetric: ParameterPort<String> { port(named: "inputMetric") }
    public var outputDistances: NodePort<ContiguousArray<Float>> { port(named: "outputDistances") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = selectedNumericPortType

        addOrReplaceDynamicPort(name: "inputA", displayName: "A", portType: portType, kind: .Inlet, description: "First numeric array")
        addOrReplaceDynamicPort(name: "inputB", displayName: "B", portType: portType, kind: .Inlet, description: "Second numeric array")
        reorderPorts(named: ["inputA", "inputB", "inputMetric", "outputDistances"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputA") || specializeFromConnectedPort(named: "inputB") { return }
        guard let inputA: Port = findPort(named: "inputA"),
              let inputB: Port = findPort(named: "inputB"),
              inputA.valueDidChange || inputB.valueDidChange || inputMetric.valueDidChange,
              case .Array(let elementType) = selectedNumericPortType,
              let valuesA = NumericValueOperations.arrayValues(from: inputA.snapshotValue()),
              let valuesB = NumericValueOperations.arrayValues(from: inputB.snapshotValue())
        else { return }

        let output = NumericValueOperations.distanceArrays(valuesA, valuesB, elementType: elementType, metric: currentMetric(from: inputMetric))
        outputDistances.sendBoxed(.Array(output))
    }
}

public final class TweenNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Tween" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tweens toward a target numeric value over time. Choose the value type in Settings." }
    public override class var supportedPortTypes: [PortType] { interpolatableSingleTypes + interpolatableArrayTypes }

    private var tween = TweenState()
    private var from: PortValue?
    private var to: PortValue?
    private var current: PortValue?

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputDuration", ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))),
            ("outputProgress", NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)"))
        ]
    }

    public var inputDuration: ParameterPort<Float> { port(named: "inputDuration") }
    public var inputEasing: ParameterPort<String> { port(named: "inputEasing") }
    public var outputProgress: NodePort<Float> { port(named: "outputProgress") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = selectedNumericPortType
        addOrReplaceDynamicPort(name: "inputTarget", displayName: "Target", portType: portType, kind: .Inlet, description: "Target value", editable: true)
        addOrReplaceDynamicPort(name: "outputValue", displayName: "Value", portType: portType, kind: .Outlet, description: "Current tweened value")
        reorderPorts(named: ["inputTarget", "inputDuration", "inputEasing", "outputValue", "outputProgress"])
        from = nil; to = nil; current = nil; tween = TweenState()
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputTarget") { return }
        guard let inputTarget: Port = findPort(named: "inputTarget"),
              let outputValue: Port = findPort(named: "outputValue")
        else { return }

        let time = executionInfo.timing.time
        if inputTarget.valueDidChange, let target = inputTarget.snapshotValue()
        {
            if current == nil
            {
                from = target; to = target; current = target
            }
            else if target != to
            {
                from = current; to = target; tween.start(at: time)
            }
        }

        guard let from, let to, let current else { return }
        let portType = selectedNumericPortType

        if let duration = inputDuration.value,
           let easingName = inputEasing.value,
           let result = tween.update(time: time, duration: duration, easingName: easingName)
        {
            let value: PortValue?
            if result.t >= 1.0
            {
                value = to
            }
            else if case .Array(let elementType) = portType,
                    let fromValues = NumericValueOperations.arrayValues(from: from),
                    let toValues = NumericValueOperations.arrayValues(from: to)
            {
                value = .Array(NumericValueOperations.interpolateArrays(fromValues, toValues, t: result.easedT, elementType: elementType))
            }
            else
            {
                value = NumericValueOperations.interpolate(from, to, t: result.easedT, as: portType)
            }

            self.current = value
            outputValue.sendBoxed(value)
            outputProgress.send(result.t)
        }
        else
        {
            outputValue.sendBoxed(current)
            outputProgress.send(tween.tweening ? 0.0 : 1.0)
        }
    }
}

public final class EasingNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Easing" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Interpolates between two numeric values using a manually driven easing progress." }
    public override class var supportedPortTypes: [PortType] { interpolatableSingleTypes + interpolatableArrayTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputProgress", ParameterPort(parameter: FloatParameter("Progress", 0.0, 0.0, 1.0, .inputfield, "Manual interpolation progress"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve")))
        ]
    }

    public var inputProgress: ParameterPort<Float> { port(named: "inputProgress") }
    public var inputEasing: ParameterPort<String> { port(named: "inputEasing") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = selectedNumericPortType
        addOrReplaceDynamicPort(name: "inputFrom", displayName: "From", portType: portType, kind: .Inlet, description: "Start value", editable: true)
        addOrReplaceDynamicPort(name: "inputTo", displayName: "To", portType: portType, kind: .Inlet, description: "End value", editable: true)
        addOrReplaceDynamicPort(name: "outputValue", displayName: "Value", portType: portType, kind: .Outlet, description: "Interpolated value")
        reorderPorts(named: ["inputFrom", "inputTo", "inputProgress", "inputEasing", "outputValue"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputFrom") || specializeFromConnectedPort(named: "inputTo") { return }
        guard let inputFrom: Port = findPort(named: "inputFrom"),
              let inputTo: Port = findPort(named: "inputTo"),
              let outputValue: Port = findPort(named: "outputValue"),
              inputFrom.valueDidChange || inputTo.valueDidChange || inputProgress.valueDidChange || inputEasing.valueDidChange,
              let from = inputFrom.snapshotValue(),
              let to = inputTo.snapshotValue(),
              let progress = inputProgress.value,
              let easingName = inputEasing.value,
              let easing = TweenEasing.map[easingName]
        else { return }

        let easedT = Float(easing.function(Double(min(max(progress, 0), 1))))
        let portType = selectedNumericPortType
        let value: PortValue?

        if case .Array(let elementType) = portType,
           let fromValues = NumericValueOperations.arrayValues(from: from),
           let toValues = NumericValueOperations.arrayValues(from: to)
        {
            value = .Array(NumericValueOperations.interpolateArrays(fromValues, toValues, t: easedT, elementType: elementType))
        }
        else
        {
            value = NumericValueOperations.interpolate(from, to, t: easedT, as: portType)
        }

        outputValue.sendBoxed(value)
    }
}

public final class RepeatNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Repeat" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Repeats one numeric value into an array. Choose the value type in Settings." }
    public override class var supportedPortTypes: [PortType] { singleNumericTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements")))
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let valueType = selectedNumericPortType
        let arrayType: PortType = valueType == .NumericVirtual ? .NumericVirtual : .Array(portType: valueType)
        addOrReplaceDynamicPort(name: "inputValue", displayName: "Value", portType: valueType, kind: .Inlet, description: "Value to repeat", editable: true)
        addOrReplaceDynamicPort(name: "outputArray", displayName: "Array", portType: arrayType, kind: .Outlet, description: "Repeated values")
        reorderPorts(named: ["inputValue", "inputCount", "outputArray"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputValue") { return }
        guard let inputValue: Port = findPort(named: "inputValue"),
              let outputArray: Port = findPort(named: "outputArray"),
              inputValue.valueDidChange || inputCount.valueDidChange,
              let value = inputValue.snapshotValue(),
              let count = inputCount.value
        else { return }

        outputArray.sendBoxed(.Array(ContiguousArray(repeating: value, count: max(0, count))))
    }
}

public final class RippleRepeatNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Ripple Repeat" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Repeats a value into an array by sampling past values across a delay window." }
    public override class var supportedPortTypes: [PortType] { singleNumericTypes }
    public override var isDirty: Bool { get { true } set { } }

    private struct Record { var time: TimeInterval; var value: PortValue }
    private var history: [Record] = []
    private var oldest: Record?
    private var lastTime: TimeInterval?

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements"))),
            ("inputDelaySecs", ParameterPort(parameter: FloatParameter("Delay (secs)", 1.0, 0.0, 60.0, .inputfield, "Delay window in seconds")))
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputDelaySecs: ParameterPort<Float> { port(named: "inputDelaySecs") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let valueType = selectedNumericPortType
        let arrayType: PortType = valueType == .NumericVirtual ? .NumericVirtual : .Array(portType: valueType)
        addOrReplaceDynamicPort(name: "inputValue", displayName: "Value", portType: valueType, kind: .Inlet, description: "Animated value to stagger", editable: true)
        addOrReplaceDynamicPort(name: "outputArray", displayName: "Array", portType: arrayType, kind: .Outlet, description: "Rippled repeated values")
        reorderPorts(named: ["inputValue", "inputCount", "inputDelaySecs", "outputArray"])
        history.removeAll()
        oldest = nil
        lastTime = nil
    }

    override public func startExecution(renderer: GraphRenderer)
    {
        history.removeAll()
        oldest = nil
        lastTime = nil
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputValue") { return }
        guard let inputValue: Port = findPort(named: "inputValue"),
              let outputArray: Port = findPort(named: "outputArray")
        else { return }

        let now = executionInfo.timing.time
        if let lastTime, now < lastTime
        {
            history.removeAll()
            oldest = nil
        }
        lastTime = now

        let delay = TimeInterval(max(0, inputDelaySecs.value ?? 0))
        let count = max(0, inputCount.value ?? 0)
        guard count > 0 else {
            outputArray.sendBoxed(.Array([]))
            return
        }

        let latest = inputValue.snapshotValue() ?? history.last?.value ?? oldest?.value
        guard let latest else { return }

        if oldest == nil && history.isEmpty
        {
            oldest = Record(time: now - delay, value: latest)
        }

        if inputValue.valueDidChange, let value = inputValue.snapshotValue()
        {
            history.append(Record(time: now, value: value))
        }

        let cutoff = now - delay
        while let first = history.first, first.time < cutoff
        {
            oldest = first
            history.removeFirst()
        }

        var output = ContiguousArray<PortValue>()
        output.reserveCapacity(count)
        let perElementDelay = delay / TimeInterval(count)
        var sampleTime = cutoff + perElementDelay / 2
        var held = oldest?.value ?? latest
        var historyIndex = 0

        for _ in 0..<count
        {
            while historyIndex < history.count && history[historyIndex].time <= sampleTime
            {
                held = history[historyIndex].value
                historyIndex += 1
            }
            output.append(held)
            sampleTime += perElementDelay
        }

        outputArray.sendBoxed(.Array(output))
    }
}

public final class ArrayRangeInterpolateNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Array Range Interpolate" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Generates an array interpolated from From to To using the selected easing function." }
    public override class var supportedPortTypes: [PortType] { interpolatableSingleTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements to generate"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing function applied to the interpolation")))
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputEasing: ParameterPort<String> { port(named: "inputEasing") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let valueType = selectedNumericPortType
        let arrayType: PortType = valueType == .NumericVirtual ? .NumericVirtual : .Array(portType: valueType)
        addOrReplaceDynamicPort(name: "inputFrom", displayName: "From", portType: valueType, kind: .Inlet, description: "Start value", editable: true)
        addOrReplaceDynamicPort(name: "inputTo", displayName: "To", portType: valueType, kind: .Inlet, description: "End value", editable: true)
        addOrReplaceDynamicPort(name: "outputArray", displayName: "Array", portType: arrayType, kind: .Outlet, description: "Generated interpolated values")
        reorderPorts(named: ["inputFrom", "inputTo", "inputCount", "inputEasing", "outputArray"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputFrom") || specializeFromConnectedPort(named: "inputTo") { return }
        guard let inputFrom: Port = findPort(named: "inputFrom"),
              let inputTo: Port = findPort(named: "inputTo"),
              let outputArray: Port = findPort(named: "outputArray"),
              inputFrom.valueDidChange || inputTo.valueDidChange || inputCount.valueDidChange || inputEasing.valueDidChange,
              let from = inputFrom.snapshotValue(),
              let to = inputTo.snapshotValue(),
              let count = inputCount.value,
              let easingName = inputEasing.value,
              let easing = TweenEasing.map[easingName]
        else { return }

        guard count > 0 else {
            outputArray.sendBoxed(.Array([]))
            return
        }

        guard count > 1 else {
            outputArray.sendBoxed(.Array([from]))
            return
        }

        let portType = selectedNumericPortType
        let divisor = Float(count - 1)
        var output = ContiguousArray<PortValue>()
        output.reserveCapacity(count)

        for index in 0..<count
        {
            let t = Float(index) / divisor
            let easedT = Float(easing.function(Double(t)))
            if let value = NumericValueOperations.interpolate(from, to, t: easedT, as: portType)
            {
                output.append(value)
            }
        }

        outputArray.sendBoxed(.Array(output))
    }
}

public final class ArrayResampleTypeAgnosticNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Array Resample" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Resamples a numeric array to a new count using type-appropriate interpolation." }
    public override class var supportedPortTypes: [PortType] { interpolatableArrayTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Desired output element count")))
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = selectedNumericPortType
        addOrReplaceDynamicPort(name: "inputArray", displayName: "Array", portType: portType, kind: .Inlet, description: "Source array")
        addOrReplaceDynamicPort(name: "outputArray", displayName: "Array", portType: portType, kind: .Outlet, description: "Resampled array")
        reorderPorts(named: ["inputArray", "inputCount", "outputArray"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputArray") { return }
        guard let inputArray: Port = findPort(named: "inputArray"),
              let outputArray: Port = findPort(named: "outputArray"),
              inputArray.valueDidChange || inputCount.valueDidChange,
              case .Array(let elementType) = selectedNumericPortType,
              let source = NumericValueOperations.arrayValues(from: inputArray.snapshotValue()),
              let count = inputCount.value
        else { return }

        outputArray.sendBoxed(.Array(NumericValueOperations.resampleArray(source, count: count, elementType: elementType)))
    }
}
