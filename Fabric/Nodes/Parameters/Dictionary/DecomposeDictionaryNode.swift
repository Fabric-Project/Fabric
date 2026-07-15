//
//  DecomposeDictionaryNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DecomposeDictionaryNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Decompose Dictionary" }
    override public class var nodeDescription: String { "Outputs dictionary keys and values sorted by key. Choose value type in Settings." }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        let requiredTypes: [(String, PortType)] = [
            ("inputDictionary", dictionaryType),
            ("outputKeys", .Array(portType: .String)),
            ("outputValues", valuesArrayType),
        ]

        for (name, type) in requiredTypes
        {
            if let existing: Port = findPort(named: name), existing.portType != type { removePort(existing) }
        }

        if findPort(named: "inputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Inlet, description: "Dictionary to decompose"), name: "inputDictionary")
        }
        if findPort(named: "outputKeys") == nil
        {
            addDynamicPort(PortType.Array(portType: .String).makeFreshPort(name: "Keys", kind: .Outlet, description: "Dictionary keys sorted by key"), name: "outputKeys")
        }
        if findPort(named: "outputValues") == nil
        {
            addDynamicPort(valuesArrayType.makeFreshPort(name: "Values", kind: .Outlet, description: "Values sorted by key"), name: "outputValues")
        }

        reorderPorts(named: ["inputDictionary", "outputKeys", "outputValues"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let outputKeys: Port = findPort(named: "outputKeys"),
              let outputValues: Port = findPort(named: "outputValues"),
              inputDictionary.valueDidChange else { return }

        let dictionary = inputDictionary.snapshotValue()?.dictionaryValue ?? [:]
        let sortedKeys = sortedDictionaryKeys(dictionary)
        let keys = sortedKeys.map { PortValue.String($0) }
        let values = sortedKeys.compactMap { dictionary[$0] }

        outputKeys.sendBoxed(.Array(ContiguousArray(keys)))
        outputValues.sendBoxed(.Array(ContiguousArray(values)))
    }
}
