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
            PortDeclaration(key: "inputDictionaryA", portType: dictionaryType, kind: .Inlet, name: "Dictionary A", description: "Base dictionary"),
            PortDeclaration(key: "inputDictionaryB", portType: dictionaryType, kind: .Inlet, name: "Dictionary B", description: "Dictionary whose values override A"),
            PortDeclaration(key: "outputDictionary", portType: dictionaryType, kind: .Outlet, name: "Dictionary", description: "Merged dictionary"),
        ] + super.declaredPorts()
    }

    private var boundInputDictionaryA: Port?
    private var boundInputDictionaryB: Port?
    private var boundOutputDictionary: Port?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputDictionaryA = findPort(named: "inputDictionaryA")
        self.boundInputDictionaryB = findPort(named: "inputDictionaryB")
        self.boundOutputDictionary = findPort(named: "outputDictionary")
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionaryA: Port = self.boundInputDictionaryA,
              let inputDictionaryB: Port = self.boundInputDictionaryB,
              let outputDictionary: Port = self.boundOutputDictionary,
              inputDictionaryA.valueDidChange || inputDictionaryB.valueDidChange else { return }

        var dictionary = inputDictionaryA.snapshotValue()?.dictionaryValue ?? [:]
        dictionary.merge(inputDictionaryB.snapshotValue()?.dictionaryValue ?? [:]) { _, new in new }
        outputDictionary.sendBoxed(.Dictionary(dictionary))
    }
}
