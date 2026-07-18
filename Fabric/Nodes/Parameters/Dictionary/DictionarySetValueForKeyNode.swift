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

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        let requiredTypes: [(String, PortType)] = [
            ("inputDictionary", dictionaryType),
            ("inputValue", valueType),
            ("outputDictionary", dictionaryType),
        ]

        for (name, type) in requiredTypes
        {
            if let existing: Port = findPort(named: name), existing.portType != type { removePort(existing) }
        }

        if findPort(named: "inputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Inlet, description: "Dictionary to modify"), name: "inputDictionary")
        }
        if findPort(named: "inputValue") == nil
        {
            addDynamicPort(valueType.makeFreshPort(name: "Value", kind: .Inlet, description: "Value to set"), name: "inputValue")
        }
        if findPort(named: "outputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Outlet, description: "Modified dictionary"), name: "outputDictionary")
        }

        reorderPorts(named: ["inputDictionary", "inputKey", "inputValue", "outputDictionary"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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
