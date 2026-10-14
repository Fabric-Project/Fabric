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

        addOrReplaceDynamicPortPreservingIdentity(name: "inputDictionaryA", displayName: "Dictionary A", portType: dictionaryType, kind: .Inlet,  description: "Base dictionary")
        addOrReplaceDynamicPortPreservingIdentity(name: "inputDictionaryB", displayName: "Dictionary B", portType: dictionaryType, kind: .Inlet,  description: "Dictionary whose values override A")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputDictionary", displayName: "Dictionary",   portType: dictionaryType, kind: .Outlet, description: "Merged dictionary")

        reorderPorts(named: ["inputDictionaryA", "inputDictionaryB", "outputDictionary"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
