//
//  FillArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class FillArrayNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name: String { "\(Value.portType.rawValue) Fill Array" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Replicates a single \(Value.portType.rawValue) value into an array of the given count." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputValue", makeValuePort()),
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements to fill"))),
            ("outputArray", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Array of length Count containing Value in every slot")),
        ]
    }

    /// Factory for the value inlet. Concrete per-type subclasses override to
    /// return a ParameterPort with the appropriate Parameter, enabling
    /// inspector editing. The default falls back to a NodePort for types
    /// without a matching Parameter.
    public class func makeValuePort() -> Port {
        NodePort<Value>(name: "Value", kind: .Inlet, description: "Value to place in every array element")
    }

    // ParameterPort<T> is a subclass of NodePort<T>, so this accessor type is
    // compatible whether the concrete port is a ParameterPort or a NodePort.
    public var inputValue: NodePort<Value> { port(named: "inputValue") }
    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var outputArray: NodePort<ContiguousArray<Value>> { port(named: "outputArray") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputValue.valueDidChange || self.inputCount.valueDidChange else { return }
        guard let value = self.inputValue.value, let rawCount = self.inputCount.value else { return }

        let count = max(0, rawCount)
        let output = ContiguousArray<Value>(repeating: value, count: count)
        self.outputArray.send(output)
    }
}

public final class FillArrayFloatNode : FillArrayNode<Float>
{
    public override class func makeValuePort() -> Port {
        ParameterPort(parameter: FloatParameter("Value", 0.0, .inputfield, "Value to place in every array element"))
    }
}

public final class FillArrayFloat3Node : FillArrayNode<simd_float3>
{
    public override class func makeValuePort() -> Port {
        ParameterPort(parameter: Float3Parameter("Value", .zero, .inputfield, "Value to place in every array element"))
    }
}

public final class FillArrayFloat4Node : FillArrayNode<simd_float4>
{
    public override class func makeValuePort() -> Port {
        ParameterPort(parameter: Float4Parameter("Value", simd_float4(0, 0, 0, 1), .inputfield, "Value to place in every array element (X, Y, Z, W)"))
    }
}
