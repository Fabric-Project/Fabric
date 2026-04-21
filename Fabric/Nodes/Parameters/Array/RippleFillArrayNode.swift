//
//  RippleFillArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class RippleFillArrayNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name: String { "\(Value.portType.rawValue) Ripple Fill Array" }
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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputValue", makeValuePort()),
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements in the output array"))),
            ("inputDelaySecs", ParameterPort(parameter: FloatParameter("Delay (secs)", 1.0, 0.0, 60.0, .inputfield, "Window over which changes ripple from element 0 (oldest) to element N-1 (newest)"))),
            ("outputArray", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Array of staggered past values")),
        ]
    }

    /// Factory for the value inlet. Concrete per-type subclasses override to
    /// return a ParameterPort with the appropriate Parameter, enabling
    /// inspector editing. The default falls back to a NodePort for types
    /// without a matching Parameter.
    public class func makeValuePort() -> Port {
        NodePort<Value>(name: "Value", kind: .Inlet, description: "Animated value to stagger across the array")
    }

    // ParameterPort<T> is a subclass of NodePort<T>, so this accessor type is
    // compatible whether the concrete port is a ParameterPort or a NodePort.
    public var inputValue: NodePort<Value> { port(named: "inputValue") }
    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputDelaySecs: ParameterPort<Float> { port(named: "inputDelaySecs") }
    public var outputArray: NodePort<ContiguousArray<Value>> { port(named: "outputArray") }

    override public func startExecution(context: GraphExecutionContext) {
        self.history.removeAll()
        self.oldest = nil
    }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let now = context.timing.time
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

public final class RippleFillArrayFloatNode : RippleFillArrayNode<Float>
{
    public override class func makeValuePort() -> Port {
        ParameterPort(parameter: FloatParameter("Value", 0.0, .inputfield, "Animated value to stagger across the array"))
    }
}

public final class RippleFillArrayFloat3Node : RippleFillArrayNode<simd_float3>
{
    public override class func makeValuePort() -> Port {
        ParameterPort(parameter: Float3Parameter("Value", .zero, .inputfield, "Animated value to stagger across the array"))
    }
}

public final class RippleFillArrayFloat4Node : RippleFillArrayNode<simd_float4>
{
    public override class func makeValuePort() -> Port {
        ParameterPort(parameter: Float4Parameter("Value", simd_float4(0, 0, 0, 1), .inputfield, "Animated value to stagger across the array (X, Y, Z, W)"))
    }
}
