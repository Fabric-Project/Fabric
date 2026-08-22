//
//  DictionaryNodeSupport.swift
//  Fabric
//

import Foundation
import Satin
import Metal

extension PortType
{
    var dictionaryPortType: PortType { .Dictionary(valueType: self) }
    var arrayPortType: PortType { .Array(portType: self) }
}

extension PortValue
{
    var dictionaryValue: Dictionary<String, PortValue>?
    {
        guard case .Dictionary(let value) = self else { return nil }
        return value
    }

    var arrayValue: ContiguousArray<PortValue>?
    {
        guard case .Array(let value) = self else { return nil }
        return value
    }
}

func sortedDictionaryKeys(_ dictionary: Dictionary<String, PortValue>) -> [String]
{
    dictionary.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

public class DictionaryTypeAgnosticNode: TypeAgnosticNode
{
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Dictionary) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }

    var valueType: PortType { selectedPortType }
    var dictionaryType: PortType { valueType.dictionaryPortType }
    var valuesArrayType: PortType { valueType.arrayPortType }

    func reorderPorts(named portNames: [String])
    {
        let reordered: [Port] = portNames.compactMap { name in let port: Port? = findPort(named: name); return port }
        if reordered.count == self.ports.count { reorderPorts(reordered) }
    }
}
