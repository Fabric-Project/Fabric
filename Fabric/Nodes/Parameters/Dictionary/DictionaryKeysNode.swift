//
//  DictionaryKeysNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionaryKeysNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Dictionary Keys" }
    override public class var nodeDescription: String { "Outputs the dictionary keys as a string array. Choose value type in Settings." }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        if let existing: Port = findPort(named: "inputDictionary"), existing.portType != dictionaryType { removePort(existing) }
        if findPort(named: "inputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Inlet, description: "Dictionary to inspect"), name: "inputDictionary")
        }
        if findPort(named: "outputKeys") == nil
        {
            addDynamicPort(PortType.Array(portType: .String).makeFreshPort(name: "Keys", kind: .Outlet, description: "Dictionary keys"), name: "outputKeys")
        }

        reorderPorts(named: ["inputDictionary", "outputKeys"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let outputKeys: Port = findPort(named: "outputKeys"),
              inputDictionary.valueDidChange else { return }

        let dictionary = inputDictionary.snapshotValue()?.dictionaryValue ?? [:]
        let keys = sortedDictionaryKeys(dictionary).map { PortValue.String($0) }
        outputKeys.sendBoxed(.Array(ContiguousArray(keys)))
    }
}
