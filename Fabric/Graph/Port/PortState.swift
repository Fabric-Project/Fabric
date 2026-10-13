//
//  PortState.swift
//  Fabric
//

import Foundation

/// A port's document-owned state as a value, under the registry key it is
/// found by: what a port taken away and added back needs to be the same port
/// to the wires and proxies that name it.
struct PortState: Equatable
{
    let registryKey: String
    let id: UUID
    let portType: PortType
    let published: Bool
    let publishedName: String?
    /// An inlet's value. An outlet's is what execution last sent, not state.
    let value: PortValue?

    init(of port: Port, registryKey: String)
    {
        self.registryKey = registryKey
        self.id = port.id
        self.portType = port.portType
        self.published = port.published
        self.publishedName = port.publishedName
        self.value = port.kind == .Inlet ? port.snapshotValue() : nil
    }

    /// The keys whose port is in one list and not the other, or whose state
    /// differs between them.
    static func registryKeys(differingBetween first: [PortState], and second: [PortState]) -> Set<String>
    {
        let firstByKey = Dictionary(first.map { ($0.registryKey, $0) }, uniquingKeysWith: { earlier, _ in earlier })
        let secondByKey = Dictionary(second.map { ($0.registryKey, $0) }, uniquingKeysWith: { earlier, _ in earlier })
        return Set(firstByKey.keys).union(secondByKey.keys).filter { firstByKey[$0] != secondByKey[$0] }
    }
}
