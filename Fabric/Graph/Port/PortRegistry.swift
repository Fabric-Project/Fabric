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
    // Stable order for UI/layout and serialization. Name lookup returns an
    // integer first so optimized reads can borrow the port from this storage.
    private(set) var ordered: ContiguousArray<Port> = []
    private var byName: [String: Int] = [:]
    // lookup by UUID for connections remap
    private var byID: [UUID: Port] = [:]
    
    func register(_ port: Port, name: String, owner: Node)
    {
        port.node = owner
        self.ordered.append(port)
        self.byName[name] = self.ordered.count - 1
        self.byID[port.id] = port
    }

    func addDynamic(_ port: Port, owner: Node, name: String? = nil)
    {
        self.register(port, name: name ?? port.name, owner: owner)
    }

    func remove(_ p: Port)
    {
        if let graph = p.node?.graph {
            graph.disconnectAll(from: p)
        }
        self.byID[p.id] = nil
        if let removedIndex = ordered.firstIndex(where: { $0.id == p.id })
        {
            // Inspect the old storage before removing its element. Keys for
            // later ports shift with the array; registry keys are not labels.
            for (name, index) in self.byName
            {
                if self.ordered[index].id == p.id {
                    self.byName[name] = nil
                } else if index > removedIndex {
                    self.byName[name] = index - 1
                }
            }
            self.ordered.remove(at: removedIndex)
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
            (self.ordered[value].id, key)
        })

        self.ordered = ContiguousArray(reordered)
        self.byName.removeAll(keepingCapacity: true)
        self.byID.removeAll(keepingCapacity: true)

        for (index, port) in self.ordered.enumerated() {
            let name = namesByID[port.id] ?? port.name
            self.byName[name] = index
            self.byID[port.id] = port
        }
    }
    
    func port(named name: String) -> Port?
    {
        guard let index = self.byName[name] else { return nil }
        return self.ordered[index]
    }

    func name(of port: Port) -> String?
    {
        self.byName.first { self.ordered[$0.value].id == port.id }?.key
    }

    // Native Array and ContiguousArray share storage here. Preserve the public
    // Array API and its copy-on-write snapshot semantics.
    func all() -> [Port] { Array(self.ordered) }

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
                port.id == self.ordered[value].id
            })?.key ?? port.name

            return Snapshot(name: name, payload: AnyPort(port))
        }
    }
}
