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

    public let inputArray = NodePort<ContiguousArray<Value>>(name: "Array", kind: .Inlet, description: "Source array")
    public let inputCount = ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Desired output element count"))
    public let outputArray = NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Resampled array of length Count")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputArray", port: self.inputArray),
            PortDeclaration(key: "inputCount", port: self.inputCount),
            PortDeclaration(key: "outputArray", port: self.outputArray),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard self.inputArray.valueDidChange || self.inputCount.valueDidChange else { return }
        guard let source = self.inputArray.value, !source.isEmpty,
              let count = self.inputCount.value, count > 0
        else {
            self.outputArray.send(ContiguousArray<Value>())
            return
        }

        let output = source.resampled(count: count)
        self.outputArray.send(output)
    }
}
