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
    
    // MARK: - Reconciling to declarations

    /// What reconcile(to:owner:hydrating:) changed. Retired ports, those
    /// removed and those replaced, still name their node, so the node can take
    /// their wires and proxies through the graph before it lets them go.
    struct Reconciliation
    {
        var added: [Port] = []
        var removed: [Port] = []
        var replaced: [(old: Port, new: Port)] = []
        var reordered = false

        var isEmpty: Bool { added.isEmpty && removed.isEmpty && replaced.isEmpty && !reordered }
    }

    /// Brings the ports to `declarations`, in their order. A port whose key,
    /// kind and type match its declaration stays as it is; one whose kind or
    /// type differ, or that lacks or has a parameter the declaration says it
    /// has or lacks, is replaced under its id, published as it was; a missing
    /// key is made, taking the state reconciling(to:_:) or decode holds for
    /// it; a port no declaration names is removed. The first of two
    /// declarations under one key counts.
    func reconcile(to declarations: [PortDeclaration],
                   owner: Node,
                   hydrating session: PortHydrationSession?) -> Reconciliation
    {
        var reconciliation = Reconciliation()
        var reconciled: [(key: String, port: Port)] = []
        var made: [(key: String, port: Port)] = []
        var declaredKeys = Set<String>()

        for declaration in declarations where declaredKeys.insert(declaration.registryKey).inserted
        {
            let key = declaration.registryKey

            guard let existing = self.byName[key] else
            {
                let port = Self.make(declaration, id: nil)
                made.append((key, port))
                reconciled.append((key, port))
                reconciliation.added.append(port)
                continue
            }

            if existing.kind == declaration.kind
                && existing.portType == declaration.portType
                && declaration.isParameterPort.map({ $0 == (existing.parameter != nil) }) ?? true
            {
                reconciled.append((key, existing))
                continue
            }

            let replacement = Self.make(declaration, id: existing.id)
            replacement.setPublishing(existing.published, name: existing.publishedName)
            self.retire(existing, hydrating: session)
            made.append((key, replacement))
            reconciled.append((key, replacement))
            reconciliation.replaced.append((existing, replacement))
        }

        let keysByPort = Dictionary(self.byName.map { (ObjectIdentifier($0.value), $0.key) }, uniquingKeysWith: { first, _ in first })
        for port in self.ordered where !declaredKeys.contains(keysByPort[ObjectIdentifier(port)] ?? port.name)
        {
            self.retire(port, hydrating: session)
            reconciliation.removed.append(port)
        }

        // Every retired port has handed back its state before any port takes
        // state, so a key retired and made again takes it.
        for (key, port) in made
        {
            session?.hydrate(port, registryKey: key)
            if let state = self.pendingReconciliation?.removeValue(forKey: key)
            {
                port.take(state)
                self.reconciledByPortID[port.id] = state
            }
            port.node = owner
        }

        reconciliation.reordered = self.ordered.map(\.id) != reconciled.map(\.port.id)

        self.ordered = reconciled.map(\.port)
        self.byName = Dictionary(reconciled.map { ($0.key, $0.port) }, uniquingKeysWith: { first, _ in first })

        return reconciliation
    }

    private static func make(_ declaration: PortDeclaration, id: UUID?) -> Port
    {
        let port = declaration.makePort(id)
        if let id, port.id != id { port.adoptID(id) }
        return port
    }

    /// Hands back the state a port took in this reconciliation or decode, for
    /// a port made again under its key.
    private func retire(_ port: Port, hydrating session: PortHydrationSession?)
    {
        session?.relinquish(port)
        if let state = self.reconciledByPortID.removeValue(forKey: port.id)
        {
            self.pendingReconciliation?[state.registryKey] = state
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
