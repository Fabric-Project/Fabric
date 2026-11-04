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
    // Stable order for UI/layout and serialization. Key lookup returns an
    // integer first so optimized reads can borrow the port from this storage.
    private(set) var ordered: ContiguousArray<Port> = []
    private var indexByKey: [PortKey: Int] = [:]

    // MARK: - Reconciling to declarations

    /// What reconcile(to:applying:owner:hydrating:) changed. Retired ports,
    /// those removed and those retyped, still name their node, so the node can
    /// take their wires through the graph before it lets them go.
    struct Reconciliation
    {
        var added: [Port] = []
        var removed: [Port] = []
        var retyped: [(old: Port, new: Port)] = []
        var reordered = false

        var isEmpty: Bool { added.isEmpty && removed.isEmpty && retyped.isEmpty && !reordered }
    }

    /// Brings the ports to `declarations`, in their order, and puts `states`
    /// on them. A port whose key, kind and type match its declaration, and
    /// that is a parameter port exactly when the declaration has a control,
    /// stays as it is. One that differs is retyped: made afresh under the old
    /// one's runtime id. A missing key is made. A port no declaration names is
    /// removed. The first of two declarations under one key counts.
    ///
    /// A state goes onto the port at its key when its value fits the port's
    /// type; the port then corrects it (a slider clamps to its range). This
    /// never touches the graph: the caller applies the result to it.
    func reconcile(to declarations: [PortDeclaration],
                   applying states: [PortState],
                   owner: Node,
                   hydrating session: PortHydrationSession?) -> Reconciliation
    {
        var reconciliation = Reconciliation()
        var reconciled: [(key: PortKey, port: Port, control: PortControl?)] = []
        var made: [(key: PortKey, port: Port)] = []
        var declaredKeys = Set<PortKey>()

        for declaration in declarations where declaredKeys.insert(declaration.key).inserted
        {
            let key = declaration.key

            guard let existing = self.port(forKey: key) else
            {
                let port = Self.make(declaration, id: nil)
                made.append((key, port))
                reconciled.append((key, port, declaration.control))
                reconciliation.added.append(port)
                continue
            }

            if existing.kind == declaration.kind
                && existing.portType == declaration.portType
                && (existing.parameter != nil) == (declaration.control != nil)
            {
                reconciled.append((key, existing, declaration.control))
                continue
            }

            let replacement = Self.make(declaration, id: existing.id)
            session?.relinquish(existing)
            made.append((key, replacement))
            reconciled.append((key, replacement, declaration.control))
            reconciliation.retyped.append((existing, replacement))
        }

        for port in self.ordered where !declaredKeys.contains(port.key)
        {
            session?.relinquish(port)
            reconciliation.removed.append(port)
        }

        // Every retired port has handed back its state before any port takes
        // state, so a key retired and made again takes it.
        var hydratedStates: [PortState] = []
        for (key, port) in made
        {
            port.key = key
            port.node = owner
            if let state = session?.hydrate(port, key: key) { hydratedStates.append(state) }
        }

        reconciliation.reordered = self.ordered.map(\.key) != reconciled.map(\.key)

        self.ordered = ContiguousArray(reconciled.map(\.port))
        self.indexByKey = Dictionary(reconciled.enumerated().map { ($0.element.key, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for entry in reconciled
        {
            entry.port.key = entry.key
            entry.port.control = entry.control
        }

        for state in hydratedStates + states
        {
            self.port(forKey: state.key)?.apply(state)
        }

        return reconciliation
    }

    private static func make(_ declaration: PortDeclaration, id: UUID?) -> Port
    {
        let port = declaration.makePort(id)
        if let id, port.id != id { port.adoptID(id) }
        return port
    }

    /// The value every parameter inlet rests at, under its key: the whole of
    /// what a document holds about a node's ports.
    func states() -> [PortState]
    {
        self.ordered.compactMap { port in
            guard port.kind == .Inlet, port.control != nil, let value = port.snapshotValue() else { return nil }
            return PortState(key: port.key, value: value)
        }
    }

    // MARK: - Imperative mutation, until every node declares

    func register(_ port: Port, name: String, owner: Node)
    {
        self.register(port, key: .own(name), owner: owner)
    }

    func register(_ port: Port, key: PortKey, owner: Node)
    {
        port.node = owner
        port.key = key
        port.control = port.parameter.map { PortControl($0.controlType) }
        self.ordered.append(port)
        self.indexByKey[key] = self.ordered.count - 1
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
        if let removedIndex = ordered.firstIndex(where: { $0 === p })
        {
            self.ordered.remove(at: removedIndex)
            self.reindex()
        }
        // Dynamic type changes replace a Port instance while preserving its
        // UUID. Detach the retired instance so a transient SwiftUI view cannot
        // reconnect that stale object after the replacement is registered.
        p.node = nil
    }

    func reorder(_ reordered: [Port])
    {
        guard reordered.count == self.ordered.count,
              Set(reordered.map(ObjectIdentifier.init)) == Set(self.ordered.map(ObjectIdentifier.init))
        else { return }

        self.ordered = ContiguousArray(reordered)
        self.reindex()
    }

    private func reindex()
    {
        self.indexByKey = Dictionary(self.ordered.enumerated().map { ($0.element.key, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Lookup

    func port(forKey key: PortKey) -> Port?
    {
        guard let index = self.indexByKey[key] else { return nil }
        return self.ordered[index]
    }

    func port(named name: String) -> Port?
    {
        self.port(forKey: .own(name))
    }

    func name(of port: Port) -> String?
    {
        guard self.port(forKey: port.key) === port, case .own(let name) = port.key else { return nil }
        return name
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
            Snapshot(name: self.name(of: port) ?? port.name, payload: AnyPort(port))
        }
    }
}
