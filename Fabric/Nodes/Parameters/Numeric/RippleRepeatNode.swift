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

    public let inputCount = ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements"))
    public let inputDelaySecs = ParameterPort(parameter: FloatParameter("Delay (secs)", 1.0, 0.0, 60.0, .inputfield, "Delay window in seconds"))

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputValue = findPort(named: "inputValue")
        self.boundOutputArray = findPort(named: "outputArray")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let valueType = selectedNumericPortType
        let arrayType: PortType = valueType == .NumericVirtual ? .NumericVirtual : .Array(portType: valueType)

        return [
            PortDeclaration(key: "inputValue", portType: valueType, kind: .Inlet, name: "Value", description: "Animated value to stagger"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "inputCount", port: self.inputCount),
            PortDeclaration(key: "inputDelaySecs", port: self.inputDelaySecs),
            PortDeclaration(key: "outputArray", portType: arrayType, kind: .Outlet, name: "Array", description: "Rippled repeated values"),
        ]
    }

    public override func apply(_ settings: any NodeSettings)
    {
        super.apply(settings)
        history.removeAll()
        oldest = nil
        lastTime = nil
    }

    override public func startExecution(renderer: GraphRenderer)
    throws
    {
        history.removeAll()
        oldest = nil
        lastTime = nil
        try super.startExecution(renderer: renderer)
    }

    private var boundInputValue: Port?
    private var boundOutputArray: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if specializeFromConnectedPort(self.boundInputValue) { return }
        guard let inputValue: Port = self.boundInputValue,
              let outputArray: Port = self.boundOutputArray
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
