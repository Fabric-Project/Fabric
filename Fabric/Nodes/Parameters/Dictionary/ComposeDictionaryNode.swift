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
            PortDeclaration(key: "inputKeys", portType: .Array(portType: .String), kind: .Inlet, name: "Keys", description: "String keys"),
            PortDeclaration(key: "inputValues", portType: valuesArrayType, kind: .Inlet, name: "Values", description: "Values matching the keys"),
            PortDeclaration(key: "outputDictionary", portType: dictionaryType, kind: .Outlet, name: "Dictionary", description: "Dictionary built from keys and values"),
        ] + super.declaredPorts()
    }

    private var boundInputKeys: Port?
    private var boundInputValues: Port?
    private var boundOutputDictionary: Port?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputKeys = findPort(named: "inputKeys")
        self.boundInputValues = findPort(named: "inputValues")
        self.boundOutputDictionary = findPort(named: "outputDictionary")
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputKeys: Port = self.boundInputKeys,
              let inputValues: Port = self.boundInputValues,
              let outputDictionary: Port = self.boundOutputDictionary else { return }

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
