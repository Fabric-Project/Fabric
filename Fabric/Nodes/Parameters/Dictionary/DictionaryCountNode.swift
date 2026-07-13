//
//  DictionaryCountNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionaryCountNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Dictionary Count" }
    override public class var nodeDescription: String { "Outputs the number of key-value pairs in a dictionary. Choose value type in Settings." }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        if let existing: Port = findPort(named: "inputDictionary"), existing.portType != dictionaryType { removePort(existing) }
        if findPort(named: "inputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Inlet, description: "Dictionary to count"), name: "inputDictionary")
        }
        if findPort(named: "outputCount") == nil
        {
            addDynamicPort(PortType.Int.makeFreshPort(name: "Count", kind: .Outlet, description: "Dictionary count"), name: "outputCount")
        }

        reorderPorts(named: ["inputDictionary", "outputCount"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let outputCount: Port = findPort(named: "outputCount"),
              inputDictionary.valueDidChange else { return }

        outputCount.sendBoxed(.Int(inputDictionary.snapshotValue()?.dictionaryValue?.count ?? 0))
    }
}
