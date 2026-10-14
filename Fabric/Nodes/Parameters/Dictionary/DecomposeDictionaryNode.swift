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

        addOrReplaceDynamicPortPreservingIdentity(name: "inputDictionary", displayName: "Dictionary", portType: dictionaryType,            kind: .Inlet,  description: "Dictionary to decompose")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputKeys",      displayName: "Keys",       portType: .Array(portType: .String), kind: .Outlet, description: "Dictionary keys sorted by key")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputValues",    displayName: "Values",     portType: valuesArrayType,           kind: .Outlet, description: "Values sorted by key")

        reorderPorts(named: ["inputDictionary", "outputKeys", "outputValues"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
