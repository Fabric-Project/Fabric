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

    public var inputSample: ParameterPort<Bool> { port(named: "inputSample") }
    public var inputReset: ParameterPort<Bool>  { port(named: "inputReset") }

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
        guard let portType = PortType(rawValue: strategy) else { return super.declaredPorts() }

        return [
            PortDeclaration(registryKey: "inputValue",  portType: portType, kind: .Inlet,  name: "Value", description: "Value to sample and hold"),
            PortDeclaration(registryKey: "outputValue", portType: portType, kind: .Outlet, name: "Value", description: "The last sampled value"),
        ] + super.declaredPorts()
    }

    public override func didApplyStrategy()
    {
        super.didApplyStrategy()
        heldValue = nil
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputValue:  Port = findPort(named: "inputValue"),
              let outputValue: Port = findPort(named: "outputValue") else { return }

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
