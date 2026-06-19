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

public class SampleAndHoldNode: StrategyNode
{
    public override class var name: String { "Sample and Hold" }
    public override class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Samples any value type when enabled and holds it until reset. Choose the value type in Settings." }

    // The set of names that rebuildPorts manages. Used to evict stale ports on strategy change.
    private static let allDynamicPortNames: Set<String> = ["inputValue", "outputValue"]

    public override class var strategies: [String] {
        [PortType.Virtual.rawValue] + PortType.allCases.filter { $0 != .Virtual }.map(\.rawValue)
    }
    public override class var defaultStrategy: String { PortType.Virtual.rawValue }
    public override class var separatorAfterFirstStrategy: Bool { true }

    // Fixed parameter ports (always present, not rebuilt on strategy change)
    public var inputSample: ParameterPort<Bool> { port(named: "inputSample") }
    public var inputReset: ParameterPort<Bool>  { port(named: "inputReset") }

    // The last sampled value, boxed so it survives port type changes.
    private var heldValue: PortValue?

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputSample", ParameterPort(parameter: BoolParameter("Sample", true,  .button, "When enabled, samples and holds the input value"))),
            ("inputReset",  ParameterPort(parameter: BoolParameter("Reset",  false, .button, "Reset the held value to nil"))),
        ]
    }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        guard let portType = PortType(rawValue: strategy) else { return }

        for name in Self.allDynamicPortNames
        {
            if let p: Port = findPort(named: name) { removePort(p) }
        }

        let inputPort  = portType.makeFreshPort(name: "Value", kind: .Inlet,  description: "Value to sample and hold")
        let outputPort = portType.makeFreshPort(name: "Value", kind: .Outlet, description: "The last sampled value")

        addDynamicPort(inputPort,  name: "inputValue")
        addDynamicPort(outputPort, name: "outputValue")

        heldValue = nil

        displayName = portType == .Virtual ? nil : "Sample and Hold \(portType.rawValue)"

        // Enforce stable port order: Value in, Value out, Sample, Reset
        let portOrder = ["inputValue", "outputValue", "inputSample", "inputReset"]
        let reordered: [Port] = portOrder.compactMap { name in let p: Port? = findPort(named: name); return p }
        if reordered.count == self.ports.count { reorderPorts(reordered) }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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
