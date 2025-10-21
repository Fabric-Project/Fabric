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

    func addDynamic(_ port: Port, owner: Node)
    {
        self.register(port, name: port.name, owner: owner)
    }

    func remove(_ p: Port)
    {
        p.disconnectAll()
        self.byID[p.id] = nil
        if let i = ordered.firstIndex(where: { $0.id == p.id }) { self.ordered.remove(at: i) }
    }

    func port(named name: String) -> Port? { self.byName[name] }
    func all() -> [Port] { self.ordered }

    // Snapshot == “data only” payload we can apply onto existing instances
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

    // Rebuild/merge: prefer decoded instances, fallback to freshly declared ones
    func rebuild(from snapshots: [Snapshot],
                 declared: [(name: String, port: Port)],
                 owner: Node)
    {
        self.ordered.removeAll(keepingCapacity: true)
        self.byName.removeAll(keepingCapacity: true)
        self.byID.removeAll(keepingCapacity: true)

        // First: decode payloads → concrete Port objects (via AnyPort)
        var decodedByName: [String: Port] = [:]
        for s in snapshots { decodedByName[s.name] = s.payload.base }

        // Merge with declared set: keep decoded if types match, else use declared
        for (name, dPort) in declared
        {
            let p = decodedByName[name].map { decoded in
                // optional type sanity check
                type(of: decoded) == type(of: dPort) ? decoded : dPort
            } ?? dPort
            
            self.register(p, name: name, owner: owner)
            decodedByName[name] = nil
        }

        // Any leftover decoded ports = previously dynamic additions → keep them
        for (name, extra) in decodedByName {
            self.register(extra, name: name, owner: owner)
        }
    }
}
