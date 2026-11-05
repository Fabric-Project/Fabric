//
//  DictionaryCountNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionaryCountNode: DictionaryTypeAgnosticNode
{
    public override class var name: String { "Dictionary Count" }
    override public class var nodeDescription: String { "Outputs the number of key-value pairs in a dictionary. Choose value type in Settings." }

    public override func declaredPorts() -> [PortDeclaration]
    {
        return [
            PortDeclaration(key: "inputDictionary", portType: dictionaryType, kind: .Inlet, name: "Dictionary", description: "Dictionary to count"),
            PortDeclaration(key: "outputCount", portType: .Int, kind: .Outlet, name: "Count", description: "Dictionary count"),
        ] + super.declaredPorts()
    }

    private var boundInputDictionary: Port?
    private var boundOutputCount: Port?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputDictionary = findPort(named: "inputDictionary")
        self.boundOutputCount = findPort(named: "outputCount")
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionary: Port = self.boundInputDictionary,
              let outputCount: Port = self.boundOutputCount,
              inputDictionary.valueDidChange else { return }

        outputCount.sendBoxed(.Int(inputDictionary.snapshotValue()?.dictionaryValue?.count ?? 0))
    }
}
