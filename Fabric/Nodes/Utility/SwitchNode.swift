//
//  SwitchNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class SwitchNode: Node {
    override public class var name: String { "Switch" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Select one of several inputs to pass through. Only the selected branch is evaluated." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputIndex", ParameterPort(parameter: IntParameter("Index", 0, 0, 3, .inputfield, "Which input to select (0–3)"))),
            ("input0", NodePort<PortValue>(name: "Input 0", kind: .Inlet, description: "Value when index is 0")),
            ("input1", NodePort<PortValue>(name: "Input 1", kind: .Inlet, description: "Value when index is 1")),
            ("input2", NodePort<PortValue>(name: "Input 2", kind: .Inlet, description: "Value when index is 2")),
            ("input3", NodePort<PortValue>(name: "Input 3", kind: .Inlet, description: "Value when index is 3")),
            ("output", NodePort<PortValue>(name: "Output", kind: .Outlet, description: "The selected input value")),
        ]
    }

    // Port proxies
    public var inputIndex: ParameterPort<Int> { port(named: "inputIndex") }
    public var input0: NodePort<PortValue> { port(named: "input0") }
    public var input1: NodePort<PortValue> { port(named: "input1") }
    public var input2: NodePort<PortValue> { port(named: "input2") }
    public var input3: NodePort<PortValue> { port(named: "input3") }
    public var output: NodePort<PortValue> { port(named: "output") }

    private var selectedInputPort: NodePort<PortValue> {
        let index = inputIndex.value ?? 0
        switch index {
        case 0:  return input0
        case 1:  return input1
        case 2:  return input2
        case 3:  return input3
        default: return input0
        }
    }

    /// Only pull the upstream node connected to the selected input port.
    /// The index port's upstream is always pulled so the selector stays live.
    open override func activeInputNodes() -> [Node] {
        var nodes: [Node] = []

        // Always pull the index input's upstream
        for connection in inputIndex.connections {
            if let node = connection.node { nodes.append(node) }
        }

        // Pull only the selected value input's upstream
        for connection in selectedInputPort.connections {
            if let node = connection.node, !nodes.contains(node) { nodes.append(node) }
        }

        return nodes
    }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        output.send(selectedInputPort.value, force: true)
    }
}
