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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputShuffle", ParameterPort(parameter: BoolParameter("Shuffle", false, .toggle, "When true, randomizes element order; when false, passes through unchanged"))),
        ]
    }

    public var inputShuffle: ParameterPort<Bool> { port(named: "inputShuffle") }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = PortType(rawValue: strategy) else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(registryKey: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array"),
        ] + super.declaredPorts() + [
            PortDeclaration(registryKey: "outputPort", portType: arrayType, kind: .Outlet, name: "Array", description: "Shuffled or original array"),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
