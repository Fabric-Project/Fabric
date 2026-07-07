//
//  RippleRepeatNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin

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
