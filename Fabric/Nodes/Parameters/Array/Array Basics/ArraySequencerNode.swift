//
//  ArraySequencerNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin

public final class ArraySequencerNode: TypeAgnosticNode
{
    public override class var name: String { "Array Sequencer" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Selects successive array values over a cycle duration. Uses graph time unless an external Time value is connected. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    struct SequencePosition: Equatable
    {
        let index: Int?
        let progress: Float
    }

    struct SequenceClock
    {
        private(set) var originTime: TimeInterval?

        mutating func elapsedTime(
            sourceTime: TimeInterval,
            shouldReset: Bool,
            startsAtSourceTime: Bool
        ) -> TimeInterval
        {
            if originTime == nil
            {
                originTime = startsAtSourceTime ? sourceTime : 0
            }

            if shouldReset
            {
                originTime = sourceTime
            }

            return max(0, sourceTime - (originTime ?? sourceTime))
        }
    }

    private var sequenceClock = SequenceClock()
    private var wasUsingExternalTime: Bool?

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCycleDuration", ParameterPort(parameter: FloatParameter("Cycle Duration", 4.0, 0.001, 3600.0, .inputfield, "Seconds required to traverse the entire array"))),
            ("inputTime", NodePort<Float>(name: "Time", kind: .Inlet, description: "Optional external time in seconds; when unconnected, the node uses graph execution time")),
            ("inputLoop", ParameterPort(parameter: BoolParameter("Loop", true, .toggle, "Restart at the first value after each cycle"))),
            ("inputReset", ParameterPort(parameter: BoolParameter("Reset", false, .button, "Restart the sequence at the first value"))),
            ("outputIndex", NodePort<Int>(name: "Index", kind: .Outlet, description: "Current array index, or -1 when the array is empty")),
            ("outputProgress", NodePort<Float>(name: "Progress", kind: .Outlet, description: "Normalized progress through the current cycle")),
        ]
    }

    public var inputCycleDuration: ParameterPort<Float> { port(named: "inputCycleDuration") }
    public var inputTime: NodePort<Float> { port(named: "inputTime") }
    public var inputLoop: ParameterPort<Bool> { port(named: "inputLoop") }
    public var inputReset: ParameterPort<Bool> { port(named: "inputReset") }
    public var outputIndex: NodePort<Int> { port(named: "outputIndex") }
    public var outputProgress: NodePort<Float> { port(named: "outputProgress") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = PortType(rawValue: strategy) else { return }

        addOrReplaceDynamicPortPreservingIdentity(
            name: "inputArray",
            displayName: "Array",
            portType: .Array(portType: elementType),
            kind: .Inlet,
            description: "Array of values to sequence"
        )
        addOrReplaceDynamicPortPreservingIdentity(
            name: "outputValue",
            displayName: "Value",
            portType: elementType,
            kind: .Outlet,
            description: "Value at the current sequence index"
        )

        sequenceClock = SequenceClock()
        wasUsingExternalTime = nil

        let portOrder = [
            "inputArray",
            "inputCycleDuration",
            "inputTime",
            "inputLoop",
            "inputReset",
            "outputValue",
            "outputIndex",
            "outputProgress",
        ]
        let reorderedPorts: [Port] = portOrder.compactMap
        {
            portName in
            let port: Port? = findPort(named: portName)
            return port
        }
        if reorderedPorts.count == ports.count
        {
            reorderPorts(reorderedPorts)
        }
    }

    override public func startExecution(renderer: GraphRenderer)
    {
        sequenceClock = SequenceClock()
        wasUsingExternalTime = nil
    }

    override public func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    )
    {
        guard let inputArray: Port = findPort(named: "inputArray"),
              let outputValue: Port = findPort(named: "outputValue")
        else
        {
            return
        }

        let usesExternalTime = inputTime.connections.isEmpty == false
        if wasUsingExternalTime != usesExternalTime
        {
            sequenceClock = SequenceClock()
            wasUsingExternalTime = usesExternalTime
        }

        let sourceTime = usesExternalTime
            ? TimeInterval(inputTime.value ?? 0)
            : executionInfo.timing.time
        let shouldReset = inputReset.valueDidChange && inputReset.value == true
        let elapsedTime = sequenceClock.elapsedTime(
            sourceTime: sourceTime,
            shouldReset: shouldReset,
            startsAtSourceTime: usesExternalTime == false
        )

        guard let boxedArray = inputArray.snapshotValue(),
              case .Array(let elements) = boxedArray,
              elements.isEmpty == false
        else
        {
            outputValue.sendBoxed(nil)
            outputIndex.send(-1)
            outputProgress.send(0)
            return
        }

        let position = Self.sequencePosition(
            elapsedTime: elapsedTime,
            cycleDuration: TimeInterval(inputCycleDuration.value ?? 0),
            elementCount: elements.count,
            loops: inputLoop.value ?? true
        )

        guard let index = position.index,
              let value = elements.safeGet(index: index)
        else
        {
            outputValue.sendBoxed(nil)
            outputIndex.send(-1)
            outputProgress.send(position.progress)
            return
        }

        outputValue.sendBoxed(value)
        outputIndex.send(index)
        outputProgress.send(position.progress)
    }

    static func sequencePosition(
        elapsedTime: TimeInterval,
        cycleDuration: TimeInterval,
        elementCount: Int,
        loops: Bool
    ) -> SequencePosition
    {
        guard elementCount > 0 else
        {
            return SequencePosition(index: nil, progress: 0)
        }

        guard cycleDuration.isFinite,
              cycleDuration > 0,
              elapsedTime.isFinite
        else
        {
            return SequencePosition(index: 0, progress: 0)
        }

        let nonnegativeElapsedTime = max(0, elapsedTime)
        let normalizedProgress: Double
        if loops
        {
            let cycleTime = nonnegativeElapsedTime.truncatingRemainder(
                dividingBy: cycleDuration
            )
            normalizedProgress = cycleTime / cycleDuration
        }
        else
        {
            normalizedProgress = min(nonnegativeElapsedTime / cycleDuration, 1)
        }

        let index: Int
        if normalizedProgress >= 1
        {
            index = elementCount - 1
        }
        else
        {
            index = min(
                Int(normalizedProgress * Double(elementCount)),
                elementCount - 1
            )
        }

        return SequencePosition(index: index, progress: Float(normalizedProgress))
    }
}
