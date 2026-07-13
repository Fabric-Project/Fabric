//
//  DictionaryMergeNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionaryMergeNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Dictionary Merge" }
    override public class var nodeDescription: String { "Merges two dictionaries. Values from B replace values from A. Choose value type in Settings." }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        for name in ["inputDictionaryA", "inputDictionaryB", "outputDictionary"]
        {
            if let existing: Port = findPort(named: name), existing.portType != dictionaryType { removePort(existing) }
        }

        if findPort(named: "inputDictionaryA") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary A", kind: .Inlet, description: "Base dictionary"), name: "inputDictionaryA")
        }
        if findPort(named: "inputDictionaryB") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary B", kind: .Inlet, description: "Dictionary whose values override A"), name: "inputDictionaryB")
        }
        if findPort(named: "outputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Outlet, description: "Merged dictionary"), name: "outputDictionary")
        }

        reorderPorts(named: ["inputDictionaryA", "inputDictionaryB", "outputDictionary"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputDictionaryA: Port = findPort(named: "inputDictionaryA"),
              let inputDictionaryB: Port = findPort(named: "inputDictionaryB"),
              let outputDictionary: Port = findPort(named: "outputDictionary"),
              inputDictionaryA.valueDidChange || inputDictionaryB.valueDidChange else { return }

        var dictionary = inputDictionaryA.snapshotValue()?.dictionaryValue ?? [:]
        dictionary.merge(inputDictionaryB.snapshotValue()?.dictionaryValue ?? [:]) { _, new in new }
        outputDictionary.sendBoxed(.Dictionary(dictionary))
    }
}
