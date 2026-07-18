//
//  ComposeDictionaryNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class ComposeDictionaryNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Compose Dictionary" }
    override public class var nodeDescription: String { "Builds a dictionary from string keys and values. Choose value type in Settings." }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        let requiredTypes: [(String, PortType)] = [
            ("inputKeys", .Array(portType: .String)),
            ("inputValues", valuesArrayType),
            ("outputDictionary", dictionaryType),
        ]

        for (name, type) in requiredTypes
        {
            if let existing: Port = findPort(named: name), existing.portType != type { removePort(existing) }
        }

        if findPort(named: "inputKeys") == nil
        {
            addDynamicPort(PortType.Array(portType: .String).makeFreshPort(name: "Keys", kind: .Inlet, description: "String keys"), name: "inputKeys")
        }
        if findPort(named: "inputValues") == nil
        {
            addDynamicPort(valuesArrayType.makeFreshPort(name: "Values", kind: .Inlet, description: "Values matching the keys"), name: "inputValues")
        }
        if findPort(named: "outputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Outlet, description: "Dictionary built from keys and values"), name: "outputDictionary")
        }

        reorderPorts(named: ["inputKeys", "inputValues", "outputDictionary"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputKeys: Port = findPort(named: "inputKeys"),
              let inputValues: Port = findPort(named: "inputValues"),
              let outputDictionary: Port = findPort(named: "outputDictionary") else { return }

        guard inputKeys.valueDidChange || inputValues.valueDidChange else { return }

        guard let keys = inputKeys.snapshotValue()?.arrayValue,
              let values = inputValues.snapshotValue()?.arrayValue else
        {
            outputDictionary.sendBoxed(.Dictionary([:]))
            return
        }

        var dictionary: Dictionary<String, PortValue> = [:]
        dictionary.reserveCapacity(min(keys.count, values.count))

        for index in 0..<min(keys.count, values.count)
        {
            guard case .String(let key) = keys[index] else { continue }
            dictionary[key] = values[index]
        }

        outputDictionary.sendBoxed(.Dictionary(dictionary))
    }
}
