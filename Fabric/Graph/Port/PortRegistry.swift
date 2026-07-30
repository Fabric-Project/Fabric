//
//  PortRegistry.swift
//  Fabric
//
//  Created by Anton Marini on 10/20/25.
//


import Foundation

/*
  Swift intentionally lacks Objective-C–style dynamic reflection and Key-Value Coding (KVC),
  which means you can’t generically set stored properties by string name at runtime the way you
  could in Cocoa (e.g. `setValue(forKey:)`). In a node-based graph system, however, we need
  exactly that: a uniform way for the base `Node` class to discover, manage, and serialize its
  heterogeneous collection of input/output ports — without forcing every subclass to manually
  wire up `CodingKeys`, property bindings, and per-class encode/decode logic.

  PortRegistry provides this missing dynamic layer in a controlled, Swift-native way.
  Each `Node` owns a registry that keeps its ports indexed by name, ID, and order. The registry
  can merge declared ports with decoded data, attach ports back to their node, and look them up
  efficiently by name. This allows nodes to define their ports declaratively while letting the
  base class handle generic serialization, deserialization, and runtime access — all without
  resorting to Objective-C runtime features or unsafe reflection.
 */

final class PortRegistry
{
    // stable order for UI/layout, serialize as array
    private(set) var ordered: [Port] = []
    // lookup by friendly name
    private var byName: [String: Port] = [:]
    // lookup by UUID for connections remap
    private var byID: [UUID: Port] = [:]
    
    func register(_ port: Port, name: String, owner: Node)
    {
        port.node = owner
        self.ordered.append(port)
        self.byName[name] = port
        self.byID[port.id] = port
    }

    func addDynamic(_ port: Port, owner: Node, name: String? = nil)
    {
        self.register(port, name: name ?? port.name, owner: owner)
    }

    func remove(_ p: Port)
    {
        p.disconnectAll()
        self.byID[p.id] = nil
        if let i = ordered.firstIndex(where: { $0.id == p.id }) { self.ordered.remove(at: i) }
        for (name, port) in self.byName where port.id == p.id
        {
            self.byName[name] = nil
        }
        // Dynamic type changes replace a Port instance while preserving its
        // UUID. Detach the retired instance so a transient SwiftUI view cannot
        // reconnect that stale object after the replacement is registered.
        p.node = nil
    }

    func reorder(_ reordered: [Port])
    {
        guard reordered.count == self.ordered.count else { return }

        let oldIDs = Set(self.ordered.map(\.id))
        let newIDs = Set(reordered.map(\.id))
        guard oldIDs == newIDs else { return }

        let namesByID: [UUID: String] = Dictionary(uniqueKeysWithValues: self.byName.map { (key, value) in
            (value.id, key)
        })

        self.ordered = reordered
        self.byName.removeAll(keepingCapacity: true)
        self.byID.removeAll(keepingCapacity: true)

        for port in self.ordered {
            let name = namesByID[port.id] ?? port.name
            self.byName[name] = port
            self.byID[port.id] = port
        }
    }
    
    func port(named name: String) -> Port? { self.byName[name] }
    func all() -> [Port] { self.ordered }

    /// A port's persisted form: registry key plus the encoded port object.
    /// Decode treats it as a hydration source only — the port instances that
    /// end up registered always come from the code's declarations (see
    /// Node.init(from:)); the snapshot contributes document-owned state.
    struct Snapshot: Codable
    {
        var name: String
        var payload: AnyPort // you already have this for heterogeneous, codable ports
    }

    func encode() -> [Snapshot] {
        self.ordered.map { port in

            let name = byName.first(where: { (key, value) in
                port.id == value.id
            })?.key ?? port.name

            return Snapshot(name: name, payload: AnyPort(port))
        }
    }
}
