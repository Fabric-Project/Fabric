//
//  DictionarySetValueForKeyNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionarySetValueForKeyNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Dictionary Set Value For Key" }
    override public class var nodeDescription: String { "Sets a value for a string key. Choose value type in Settings." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputKey", ParameterPort(parameter: StringParameter("Key", "", .inputfield, "Dictionary key to set"))),
        ]
    }

    private var inputKey: ParameterPort<String> { port(named: "inputKey") }

    public override func declaredPorts() -> [PortDeclaration]
    {
        return [
            PortDeclaration(registryKey: "inputDictionary", portType: dictionaryType, kind: .Inlet, name: "Dictionary", description: "Dictionary to modify"),
        ] + super.declaredPorts() + [
            PortDeclaration(registryKey: "inputValue", portType: valueType, kind: .Inlet, name: "Value", description: "Value to set"),
            PortDeclaration(registryKey: "outputDictionary", portType: dictionaryType, kind: .Outlet, name: "Dictionary", description: "Modified dictionary"),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let inputValue: Port = findPort(named: "inputValue"),
              let outputDictionary: Port = findPort(named: "outputDictionary"),
              inputDictionary.valueDidChange || inputKey.valueDidChange || inputValue.valueDidChange else { return }

        var dictionary = inputDictionary.snapshotValue()?.dictionaryValue ?? [:]
        if let key = inputKey.value, !key.isEmpty, let value = inputValue.snapshotValue()
        {
            dictionary[key] = value
        }

        outputDictionary.sendBoxed(.Dictionary(dictionary))
    }
}
