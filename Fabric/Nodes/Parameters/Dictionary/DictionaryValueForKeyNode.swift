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

        if let existing: Port = findPort(named: "inputDictionary"), existing.portType != dictionaryType { removePort(existing) }
        if let existing: Port = findPort(named: "outputValue"), existing.portType != valueType { removePort(existing) }

        if findPort(named: "inputDictionary") == nil
        {
            addDynamicPort(dictionaryType.makeFreshPort(name: "Dictionary", kind: .Inlet, description: "Dictionary to read"), name: "inputDictionary")
        }
        if findPort(named: "outputValue") == nil
        {
            addDynamicPort(valueType.makeFreshPort(name: "Value", kind: .Outlet, description: "Value for the key"), name: "outputValue")
        }

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
