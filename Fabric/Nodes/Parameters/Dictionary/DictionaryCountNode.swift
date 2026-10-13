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
            PortDeclaration(registryKey: "inputDictionary", portType: dictionaryType, kind: .Inlet, name: "Dictionary", description: "Dictionary to count"),
            PortDeclaration(registryKey: "outputCount", portType: .Int, kind: .Outlet, name: "Count", description: "Dictionary count"),
        ] + super.declaredPorts()
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputDictionary: Port = findPort(named: "inputDictionary"),
              let outputCount: Port = findPort(named: "outputCount"),
              inputDictionary.valueDidChange else { return }

        outputCount.sendBoxed(.Int(inputDictionary.snapshotValue()?.dictionaryValue?.count ?? 0))
    }
}
