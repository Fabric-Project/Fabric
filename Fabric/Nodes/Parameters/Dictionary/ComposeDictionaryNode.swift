//
//  ComposeDictionaryNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class ComposeDictionaryNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Compose Dictionary" }
    override public class var nodeDescription: String { "Builds a dictionary from string keys and values. Choose value type in Settings." }

    public override func declaredPorts() -> [PortDeclaration]
    {
        return [
            PortDeclaration(registryKey: "inputKeys", portType: .Array(portType: .String), kind: .Inlet, name: "Keys", description: "String keys"),
            PortDeclaration(registryKey: "inputValues", portType: valuesArrayType, kind: .Inlet, name: "Values", description: "Values matching the keys"),
            PortDeclaration(registryKey: "outputDictionary", portType: dictionaryType, kind: .Outlet, name: "Dictionary", description: "Dictionary built from keys and values"),
        ] + super.declaredPorts()
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputKeys: Port = findPort(named: "inputKeys"),
              let inputValues: Port = findPort(named: "inputValues"),
              let outputDictionary: Port = findPort(named: "outputDictionary") else { return }

        guard inputKeys.valueDidChange || inputValues.valueDidChange else { return }

        guard let keys = inputKeys.snapshotValue()?.arrayValue,
              let values = inputValues.snapshotValue()?.arrayValue else
        {
            outputDictionary.sendBoxed(.Dictionary([:]))
            return
        }

        var dictionary: Dictionary<String, PortValue> = [:]
        dictionary.reserveCapacity(min(keys.count, values.count))

        for index in 0..<min(keys.count, values.count)
        {
            guard case .String(let key) = keys[index] else { continue }
            dictionary[key] = values[index]
        }

        outputDictionary.sendBoxed(.Dictionary(dictionary))
    }
}
