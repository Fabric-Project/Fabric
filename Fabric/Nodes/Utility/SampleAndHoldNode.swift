//
//  SampleAndHoldNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import Metal
import simd

public class SampleAndHoldNode: TypeAgnosticNode
{
    public override class var name: String { "Sample and Hold" }
    public override class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Samples any value type when enabled and holds it until reset. Choose the value type in Settings." }

    public var inputSample: ParameterPort<Bool> { _inputSample }
    private var _inputSample: ParameterPort<Bool>!
    public var inputReset: ParameterPort<Bool> { _inputReset }
    private var _inputReset: ParameterPort<Bool>!

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputValue = findPort(named: "inputValue")
        self.boundOutputValue = findPort(named: "outputValue")
        self._inputSample = findPort(named: "inputSample")
        self._inputReset = findPort(named: "inputReset")
    }

    private var heldValue: PortValue?

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputSample", ParameterPort(parameter: BoolParameter("Sample", true,  .button, "When enabled, samples and holds the input value"))),
            ("inputReset",  ParameterPort(parameter: BoolParameter("Reset",  false, .button, "Reset the held value to nil"))),
        ]
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let portType = strategy as? PortType else { return super.declaredPorts() }

        return [
            PortDeclaration(key: "inputValue",  portType: portType, kind: .Inlet,  name: "Value", description: "Value to sample and hold"),
            PortDeclaration(key: "outputValue", portType: portType, kind: .Outlet, name: "Value", description: "The last sampled value"),
        ] + super.declaredPorts()
    }

    public override func apply(_ settings: any NodeSettings)
    {
        super.apply(settings)
        heldValue = nil
    }

    private var boundInputValue: Port?
    private var boundOutputValue: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputValue:  Port = self.boundInputValue,
              let outputValue: Port = self.boundOutputValue else { return }

        if inputValue.valueDidChange,
           let sampling = inputSample.value, sampling
        {
            heldValue = inputValue.snapshotValue()
            outputValue.sendBoxed(heldValue)
        }

        if inputReset.valueDidChange,
           let reset = inputReset.value, reset
        {
            heldValue = nil
            outputValue.sendBoxed(nil)
        }
    }
}
