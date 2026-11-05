//
//  DictionaryRemoveKeyNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionaryRemoveKeyNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Dictionary Remove Key" }
    override public class var nodeDescription: String { "Removes a string key from a dictionary. Choose value type in Settings." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputKey", ParameterPort(parameter: StringParameter("Key", "", .inputfield, "Dictionary key to remove"))),
        ]
    }

    private var inputKey: ParameterPort<String> { _inputKey }
    private var _inputKey: ParameterPort<String>!

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputDictionary = findPort(named: "inputDictionary")
        self.boundOutputDictionary = findPort(named: "outputDictionary")
        self._inputKey = findPort(named: "inputKey")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        return [
            PortDeclaration(key: "inputDictionary", portType: dictionaryType, kind: .Inlet, name: "Dictionary", description: "Dictionary to modify"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "outputDictionary", portType: dictionaryType, kind: .Outlet, name: "Dictionary", description: "Modified dictionary"),
        ]
    }

    private var boundInputDictionary: Port?
    private var boundOutputDictionary: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionary: Port = self.boundInputDictionary,
              let outputDictionary: Port = self.boundOutputDictionary,
              inputDictionary.valueDidChange || inputKey.valueDidChange else { return }

        var dictionary = inputDictionary.snapshotValue()?.dictionaryValue ?? [:]
        if let key = inputKey.value
        {
            dictionary.removeValue(forKey: key)
        }

        outputDictionary.sendBoxed(.Dictionary(dictionary))
    }
}
