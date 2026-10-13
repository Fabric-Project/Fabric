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
        if let state = self.pendingReconciliation?.removeValue(forKey: name)
        {
            port.take(state)
            self.reconciledByPortID[port.id] = state
        }
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
        if let graph = p.node?.graph {
            graph.disconnectAll(from: p)
        }
        // A port taken away and added again under the same key in one
        // reconciliation takes its state again.
        if let state = self.reconciledByPortID.removeValue(forKey: p.id)
        {
            self.pendingReconciliation?[state.registryKey] = state
        }
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
    func name(of port: Port) -> String? { self.byName.first { $0.value.id == port.id }?.key }
    func all() -> [Port] { self.ordered }

    // MARK: - Reconciliation

    /// The states of reconciling(to:_:) not yet taken by a port added under
    /// their key; nil outside it.
    private var pendingReconciliation: [String: PortState]?
    private var reconciledByPortID: [UUID: PortState] = [:]

    /// Each port's state under its registry key.
    func portStates() -> [PortState]
    {
        self.ordered.map { port in PortState(of: port, registryKey: self.name(of: port) ?? port.name) }
    }

    /// Runs `body`, an edit that may add and take away ports, and puts back
    /// what `states` hold on the ports under their keys: a port `body` adds
    /// takes everything, id first, as it registers; a port that is here
    /// afterwards takes back its value and publishing. A port under a key
    /// `states` does not hold is not written.
    func reconciling(to states: [PortState], _ body: () throws -> Void) rethrows
    {
        let pending = Dictionary(states.map { ($0.registryKey, $0) }, uniquingKeysWith: { earlier, _ in earlier })
        let previous = (self.pendingReconciliation, self.reconciledByPortID)
        self.pendingReconciliation = pending
        self.reconciledByPortID = [:]
        defer { (self.pendingReconciliation, self.reconciledByPortID) = previous }

        try body()

        for state in states where self.pendingReconciliation?[state.registryKey] != nil
        {
            guard let port = self.byName[state.registryKey] else { continue }
            if state.portType == port.portType, let value = state.value, port.snapshotValue() != value
            {
                port.restoreValue(from: value)
            }
            Self.restorePublishing(of: port, to: state)
        }
    }

    /// Publishing changes through the events, for the proxies to follow.
    private static func restorePublishing(of port: Port, to state: PortState)
    {
        guard port.published != state.published || port.publishedName != state.publishedName else { return }
        let graph = port.node?.graph

        switch (port.published, state.published)
        {
        case (false, true):
            port.setPublishing(true, name: state.publishedName)
            graph?.portDidPublish(port)
        case (true, false):
            graph?.portWillUnpublish(port)
            port.setPublishing(false, name: state.publishedName)
            graph?.rebuildPublishedParameterGroup()
        case (true, true):
            port.setPublishing(true, name: state.publishedName)
            graph?.portDidRename(port)
        case (false, false):
            port.setPublishing(false, name: state.publishedName)
        }
    }

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
