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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputKey", ParameterPort(parameter: StringParameter("Key", "", .inputfield, "Dictionary key to read"))),
        ]
    }

    private var inputKey: ParameterPort<String> { port(named: "inputKey") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)

        addOrReplaceDynamicPortPreservingIdentity(name: "inputDictionary", displayName: "Dictionary", portType: dictionaryType, kind: .Inlet,  description: "Dictionary to read")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputValue",     displayName: "Value",      portType: valueType,      kind: .Outlet, description: "Value for the key")

        reorderPorts(named: ["inputDictionary", "inputKey", "outputValue"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let outputValue: Port = findPort(named: "outputValue"),
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
