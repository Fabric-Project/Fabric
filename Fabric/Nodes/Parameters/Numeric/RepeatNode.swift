//
//  RepeatNode.swift
//  Fabric
//

import Metal
import Satin

public final class RepeatNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Repeat" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Repeats one numeric value into an array. Choose the value type in Settings." }
    public override class var supportedPortTypes: [PortType] { singleNumericTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements")))
        ]
    }

    public var inputCount: ParameterPort<Int> { _inputCount }
    private var _inputCount: ParameterPort<Int>!

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputValue = findPort(named: "inputValue")
        self.boundOutputArray = findPort(named: "outputArray")
        self._inputCount = findPort(named: "inputCount")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let valueType = selectedNumericPortType
        let arrayType: PortType = valueType == .NumericVirtual ? .NumericVirtual : .Array(portType: valueType)

        return [
            PortDeclaration(key: "inputValue", portType: valueType, kind: .Inlet, name: "Value", description: "Value to repeat"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "outputArray", portType: arrayType, kind: .Outlet, name: "Array", description: "Repeated values"),
        ]
    }

    private var boundInputValue: Port?
    private var boundOutputArray: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if specializeFromConnectedPort(self.boundInputValue) { return }
        guard let inputValue: Port = self.boundInputValue,
              let outputArray: Port = self.boundOutputArray,
              inputValue.valueDidChange || inputCount.valueDidChange,
              let value = inputValue.snapshotValue(),
              let count = inputCount.value
        else { return }

        outputArray.sendBoxed(.Array(ContiguousArray(repeating: value, count: max(0, count))))
    }
}
