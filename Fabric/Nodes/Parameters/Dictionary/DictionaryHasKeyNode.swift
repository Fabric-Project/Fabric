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

        addOrReplaceDynamicPortPreservingIdentity(name: "inputDictionary",   displayName: "Dictionary",   portType: dictionaryType, kind: .Inlet,  description: "Dictionary to test")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputContainsKey", displayName: "Contains Key", portType: .Bool,          kind: .Outlet, description: "Whether the key exists")

        reorderPorts(named: ["inputDictionary", "inputKey", "outputContainsKey"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let outputContainsKey: Port = findPort(named: "outputContainsKey"),
              inputDictionary.valueDidChange || inputKey.valueDidChange else { return }

        let dictionary = inputDictionary.snapshotValue()?.dictionaryValue ?? [:]
        outputContainsKey.sendBoxed(.Bool(dictionary[inputKey.value ?? ""] != nil))
    }
}
