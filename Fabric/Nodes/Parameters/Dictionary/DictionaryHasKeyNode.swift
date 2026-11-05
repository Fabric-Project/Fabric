//
//  DictionaryHasKeyNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionaryHasKeyNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Dictionary Has Key" }
    override public class var nodeDescription: String { "Outputs whether a dictionary contains a string key. Choose value type in Settings." }

    private let inputKey = ParameterPort(parameter: StringParameter("Key", "", .inputfield, "Dictionary key to test"))

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputDictionary = findPort(named: "inputDictionary")
        self.boundOutputContainsKey = findPort(named: "outputContainsKey")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        return [
            PortDeclaration(key: "inputDictionary", portType: dictionaryType, kind: .Inlet, name: "Dictionary", description: "Dictionary to test"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "inputKey", port: self.inputKey),
            PortDeclaration(key: "outputContainsKey", portType: .Bool, kind: .Outlet, name: "Contains Key", description: "Whether the key exists"),
        ]
    }

    private var boundInputDictionary: Port?
    private var boundOutputContainsKey: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionary: Port = self.boundInputDictionary,
              let outputContainsKey: Port = self.boundOutputContainsKey,
              inputDictionary.valueDidChange || inputKey.valueDidChange else { return }

        let dictionary = inputDictionary.snapshotValue()?.dictionaryValue ?? [:]
        outputContainsKey.sendBoxed(.Bool(dictionary[inputKey.value ?? ""] != nil))
    }
}
