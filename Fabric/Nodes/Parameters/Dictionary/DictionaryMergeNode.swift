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

    public override func declaredPorts() -> [PortDeclaration]
    {
        return [
            PortDeclaration(registryKey: "inputDictionaryA", portType: dictionaryType, kind: .Inlet, name: "Dictionary A", description: "Base dictionary"),
            PortDeclaration(registryKey: "inputDictionaryB", portType: dictionaryType, kind: .Inlet, name: "Dictionary B", description: "Dictionary whose values override A"),
            PortDeclaration(registryKey: "outputDictionary", portType: dictionaryType, kind: .Outlet, name: "Dictionary", description: "Merged dictionary"),
        ] + super.declaredPorts()
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
