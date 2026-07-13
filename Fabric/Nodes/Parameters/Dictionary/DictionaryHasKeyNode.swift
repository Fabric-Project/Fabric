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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputKey", ParameterPort(parameter: StringParameter("Key", "", .inputfield, "Dictionary key to test"))),
        ]
    }

    private var inputKey: ParameterPort<String> { port(named: "inputKey") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        if let existing: Port = findPort(named: "inputDictionary"), existing.portType != dictionaryType { removePort(existing) }
        if findPort(named: "inputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Inlet, description: "Dictionary to test"), name: "inputDictionary")
        }
        if findPort(named: "outputContainsKey") == nil
        {
            addDynamicPort(PortType.Bool.makeFreshPort(name: "Contains Key", kind: .Outlet, description: "Whether the key exists"), name: "outputContainsKey")
        }

        reorderPorts(named: ["inputDictionary", "inputKey", "outputContainsKey"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let outputContainsKey: Port = findPort(named: "outputContainsKey"),
              inputDictionary.valueDidChange || inputKey.valueDidChange else { return }

        let dictionary = inputDictionary.snapshotValue()?.dictionaryValue ?? [:]
        outputContainsKey.sendBoxed(.Bool(dictionary[inputKey.value ?? ""] != nil))
    }
}
