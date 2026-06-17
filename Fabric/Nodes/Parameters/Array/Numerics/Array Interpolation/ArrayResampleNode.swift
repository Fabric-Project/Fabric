//
//  ArrayResampleNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ArrayResampleNode<Value: PortValueRepresentable & Lerpable>: Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array Resample" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Changes a \(Value.portType.rawValue) array's element count via index-domain linear interpolation. Handles both decimation (reducing count) and upsampling (increasing count) with the same code path." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputArray", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Inlet, description: "Source array")),
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Desired output element count"))),
            ("outputArray", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Resampled array of length Count")),
        ]
    }

    public var inputArray: NodePort<ContiguousArray<Value>> { port(named: "inputArray") }
    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var outputArray: NodePort<ContiguousArray<Value>> { port(named: "outputArray") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputArray.valueDidChange || self.inputCount.valueDidChange else { return }
        guard let source = self.inputArray.value, !source.isEmpty,
              let count = self.inputCount.value, count > 0
        else {
            self.outputArray.send(ContiguousArray<Value>())
            return
        }

        if count == 1 {
            self.outputArray.send(ContiguousArray<Value>([source[0]]))
            return
        }

        var output = ContiguousArray<Value>()
        output.reserveCapacity(count)

        let lastIndex = Float(source.count - 1)
        for i in 0..<count {
            let t = Float(i) / Float(count - 1)
            let sourcePosition = t * lastIndex
            let i0 = Int(sourcePosition)
            let i1 = min(i0 + 1, source.count - 1)
            output.append(Value.lerp(source[i0], source[i1], sourcePosition - Float(i0)))
        }

        self.outputArray.send(output)
    }
}
