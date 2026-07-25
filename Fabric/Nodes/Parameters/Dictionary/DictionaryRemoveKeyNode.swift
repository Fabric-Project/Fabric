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

    private var inputKey: ParameterPort<String> { port(named: "inputKey") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        if let existing: Port = findPort(named: "inputDictionary"), existing.portType != dictionaryType { removePort(existing) }
        if let existing: Port = findPort(named: "outputDictionary"), existing.portType != dictionaryType { removePort(existing) }

        if findPort(named: "inputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Inlet, description: "Dictionary to modify"), name: "inputDictionary")
        }
        if findPort(named: "outputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Outlet, description: "Modified dictionary"), name: "outputDictionary")
        }

        reorderPorts(named: ["inputDictionary", "inputKey", "outputDictionary"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let outputDictionary: Port = findPort(named: "outputDictionary"),
              inputDictionary.valueDidChange || inputKey.valueDidChange else { return }

        var dictionary = inputDictionary.snapshotValue()?.dictionaryValue ?? [:]
        if let key = inputKey.value
        {
            dictionary.removeValue(forKey: key)
        }

        outputDictionary.sendBoxed(.Dictionary(dictionary))
    }
}
