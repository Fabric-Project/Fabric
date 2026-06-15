//
//  RippleFillArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class RippleFillArrayNode<Value : PortValueRepresentable> : Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array From Rippled Value" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Fills an array by sampling the input \(Value.portType.rawValue) at N evenly spaced past instants across a delay window, so changes ripple through the array over time." }

    // Must tick every frame to advance time and evict stale history,
    // even when no port value changed.
    public override var isDirty: Bool { get { true } set { } }

    private struct Record { var time: TimeInterval; var value: Value }
    private var history: [Record] = []
    private var oldest: Record? = nil
    private var lastTime: TimeInterval? = nil

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputValue", makeInspectorValuePort(Value.self, name: "Value", description: "Animated value to stagger across the array")),
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements in the output array"))),
            ("inputDelaySecs", ParameterPort(parameter: FloatParameter("Delay (secs)", 1.0, 0.0, 60.0, .inputfield, "Window over which changes ripple from element 0 (oldest) to element N-1 (newest)"))),
            ("outputArray", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Array of staggered past values")),
        ]
    }

    // ParameterPort<T> is a subclass of NodePort<T>, so this accessor type is
    // compatible whether the concrete port is a ParameterPort or a NodePort.
    public var inputValue: NodePort<Value> { port(named: "inputValue") }
    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputDelaySecs: ParameterPort<Float> { port(named: "inputDelaySecs") }
    public var outputArray: NodePort<ContiguousArray<Value>> { port(named: "outputArray") }

    override public func startExecution(renderer: GraphRenderer) {
        self.history.removeAll()
        self.oldest = nil
        self.lastTime = nil
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let now = executionInfo.timing.time

        // History and resampling assume monotonically increasing time. If time
        // jumps backward (timeline scrub/loop), discard stale history so the
        // buffer doesn't become unsorted and freeze the output.
        if let last = lastTime, now < last {
            history.removeAll()
            oldest = nil
        }
        lastTime = now

        let delay = TimeInterval(max(0.0, self.inputDelaySecs.value ?? 0.0))
        let count = max(0, self.inputCount.value ?? 0)
        guard count > 0 else { return }

        let latest: Value? = self.inputValue.value ?? history.last?.value ?? oldest?.value
        guard let latest else { return }

        if oldest == nil && history.isEmpty {
            oldest = Record(time: now - delay, value: latest)
        }

        if self.inputValue.valueDidChange, let v = self.inputValue.value {
            history.append(Record(time: now, value: v))
        }

        let cutoff = now - delay
        while let first = history.first, first.time < cutoff {
            oldest = first
            history.removeFirst()
        }

        var output = ContiguousArray<Value>()
        output.reserveCapacity(count)

        let perSurface = delay / TimeInterval(count)
        var sampleTime = cutoff + perSurface / 2.0

        var held: Value = oldest?.value ?? latest
        var i = 0
        for _ in 0..<count {
            while i < history.count && history[i].time <= sampleTime {
                held = history[i].value
                i += 1
            }
            output.append(held)
            sampleTime += perSurface
        }

        self.outputArray.send(output)
    }
}
