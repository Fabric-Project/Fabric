//
//  ArrayParameterNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import simd
import Metal

/// Patching utility node for Array ports. Passes through an array without modification.
/// Does not have editable inputs.
public class ArrayParameterNode<Value: PortValueRepresentable>: Node
{
    override public class var name: String { "\(Value.portType.rawValue) Array" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for \(Value.portType.rawValue) Array. Does not have editable inputs." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputArray", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Inlet, description: "Input array")),
            ("outputArray", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Output array")),
        ]
    }

    // Port Proxy
    public var inputArray: NodePort<ContiguousArray<Value>> { port(named: "inputArray") }
    public var outputArray: NodePort<ContiguousArray<Value>> { port(named: "outputArray") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.outputArray.send(self.inputArray.value)
    }
}
