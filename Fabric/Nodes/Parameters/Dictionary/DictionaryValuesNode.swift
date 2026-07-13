//
//  DictionaryValuesNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionaryValuesNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Dictionary Values" }
    override public class var nodeDescription: String { "Outputs dictionary values sorted by key. Choose value type in Settings." }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        if let existing: Port = findPort(named: "inputDictionary"), existing.portType != dictionaryType { removePort(existing) }
        if let existing: Port = findPort(named: "outputValues"), existing.portType != valuesArrayType { removePort(existing) }

        if findPort(named: "inputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Inlet, description: "Dictionary to inspect"), name: "inputDictionary")
        }
        if findPort(named: "outputValues") == nil
        {
            addDynamicPort(valuesArrayType.makeFreshPort(name: "Values", kind: .Outlet, description: "Values sorted by key"), name: "outputValues")
        }

        reorderPorts(named: ["inputDictionary", "outputValues"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let outputValues: Port = findPort(named: "outputValues"),
              inputDictionary.valueDidChange else { return }

        let dictionary = inputDictionary.snapshotValue()?.dictionaryValue ?? [:]
        let values = sortedDictionaryKeys(dictionary).compactMap { dictionary[$0] }
        outputValues.sendBoxed(.Array(ContiguousArray(values)))
    }
}
