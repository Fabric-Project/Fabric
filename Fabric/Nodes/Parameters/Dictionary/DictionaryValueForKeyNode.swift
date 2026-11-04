//
//  DictionaryValueForKeyNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionaryValueForKeyNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Dictionary Value For Key" }
    override public class var nodeDescription: String { "Returns the value for a string key. Choose value type in Settings." }

    private let inputKey = ParameterPort(parameter: StringParameter("Key", "", .inputfield, "Dictionary key to read"))

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputDictionary = findPort(named: "inputDictionary")
        self.boundOutputValue = findPort(named: "outputValue")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        return [
            PortDeclaration(key: "inputDictionary", portType: dictionaryType, kind: .Inlet, name: "Dictionary", description: "Dictionary to read"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "inputKey", port: self.inputKey),
            PortDeclaration(key: "outputValue", portType: valueType, kind: .Outlet, name: "Value", description: "Value for the key"),
        ]
    }

    private var boundInputDictionary: Port?
    private var boundOutputValue: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionary: Port = self.boundInputDictionary,
              let outputValue: Port = self.boundOutputValue,
              inputDictionary.valueDidChange || inputKey.valueDidChange else { return }

        guard let key = inputKey.value,
              let value = inputDictionary.snapshotValue()?.dictionaryValue?[key] else
        {
            outputValue.sendBoxed(nil)
            return
        }

        outputValue.sendBoxed(value)
    }
}
