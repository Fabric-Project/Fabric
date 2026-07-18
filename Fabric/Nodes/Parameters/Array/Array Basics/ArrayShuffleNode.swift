//
//  ArrayShuffleNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayShuffleNode: TypeAgnosticNode
{
    public override class var name: String { "Array Shuffle" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Randomizes element order when Shuffle is true; passes through unchanged when false. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    private static let dynamicPortNames: Set<String> = ["inputPort", "outputPort"]

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputShuffle", NodePort<Bool>(name: "Shuffle", kind: .Inlet, description: "When true, randomizes element order; when false, passes through unchanged")),
        ]
    }

    public var inputShuffle: NodePort<Bool> { port(named: "inputShuffle") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = PortType(rawValue: strategy) else { return }

        let arrayType: PortType = .Array(portType: elementType)

        addOrReplaceDynamicPortPreservingIdentity(name: "inputPort", displayName: "Array", portType: arrayType, kind: .Inlet, description: "Input array")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputPort", displayName: "Array", portType: arrayType, kind: .Outlet, description: "Shuffled or original array")

        let portOrder = ["inputPort", "inputShuffle", "outputPort"]
        let reordered: [Port] = portOrder.compactMap { name in let p: Port? = findPort(named: name); return p }
        if reordered.count == self.ports.count { reorderPorts(reordered) }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputPort:  Port = findPort(named: "inputPort"),
              let outputPort: Port = findPort(named: "outputPort") else { return }

        guard inputPort.valueDidChange || inputShuffle.valueDidChange else { return }

        guard let boxed = inputPort.snapshotValue(),
              case .Array(let elements) = boxed else { return }

        if inputShuffle.value == true
        {
            var shuffled = elements
            shuffled.shuffle()
            outputPort.sendBoxed(.Array(shuffled))
        }
        else
        {
            outputPort.sendBoxed(.Array(elements))
        }
    }
}
