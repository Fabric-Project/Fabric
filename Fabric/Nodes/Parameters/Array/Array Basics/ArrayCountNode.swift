//
//  ArrayCountNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayCountNode: TypeAgnosticNode
{
    public override class var name: String { "Array Count" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Returns the number of elements in an array. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("outputPort", NodePort<Int>(name: "Count", kind: .Outlet, description: "Number of elements in the array")),
        ]
    }

    public var outputPort: NodePort<Int> { port(named: "outputPort") }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = PortType(rawValue: strategy) else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(registryKey: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array to count elements"),
        ] + super.declaredPorts()
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPort: Port = findPort(named: "inputPort") else { return }
        guard inputPort.valueDidChange else { return }
        guard let boxed = inputPort.snapshotValue(),
              case .Array(let elements) = boxed else { return }
        outputPort.send(elements.count)
    }
}
