//
//  NodeSettings.swift
//  Fabric
//

import Foundation

/// A node's settings as one value: the state its settings view edits that its
/// ports do not hold. A node gives it through `Node.settings` and is brought to
/// it by `Node.apply(_:)`. It is saved flattened into the node's own container,
/// under the keys the node writes, and decoded by the node's `init(from:)`.
public protocol NodeSettings: Codable, Equatable, Sendable { }

extension NodeSettings
{
    public func isEqual(to other: any NodeSettings) -> Bool
    {
        (other as? Self).map { $0 == self } ?? false
    }
}

extension Graph
{
    /// Applies `settings` to `node`, a node in this graph, as one undo step.
    /// The step holds the settings before and after and the state of each port
    /// the change touched; a port the change takes away takes its wires and
    /// proxies with it as steps of their own, in the same group. An equal value
    /// is no change and records nothing.
    public func setSettings(_ settings: any NodeSettings, on node: Node)
    {
        guard node.graph === self,
              let before = node.settings,
              !before.isEqual(to: settings)
        else { return }
        self.applySettings(settings, to: node, reconcilingTo: nil)
    }

    /// setSettings(_:on:), where each port the change adds takes what `states`
    /// holds under its registry key, its id first: a clone set sibling takes
    /// its settings from its set's stored graph, whose wires and proxies name
    /// the ports by the ids the stored graph has for them.
    internal func setSettings(_ settings: any NodeSettings, on node: Node, addingPortsAs states: [PortState])
    {
        guard node.graph === self,
              let before = node.settings,
              !before.isEqual(to: settings)
        else { return }
        self.applySettings(settings, to: node, reconcilingTo: states)
    }

    /// Undo applies the settings before under the port states before, and redo
    /// the settings after under the states after: a port the change took away
    /// comes back as it was, and a port it added comes back under the id later
    /// steps name it by. Only the ports the change touched are written, so an
    /// inlet something else drives keeps what it has.
    private func applySettings(_ settings: any NodeSettings, to node: Node, reconcilingTo states: [PortState]?)
    {
        guard let before = node.settings else { return }

        self.performEdit(named: "Change Settings") {

            let statesBefore = node.registry.portStates()
            if let states
            {
                node.registry.reconciling(to: states) { node.apply(settings) }
            }
            else
            {
                node.apply(settings)
            }
            let touched = PortState.registryKeys(differingBetween: statesBefore, and: node.registry.portStates())
            let restoring = statesBefore.filter { touched.contains($0.registryKey) }

            self.registerUndo(on: node) { node in
                node.graph?.applySettings(before, to: node, reconcilingTo: restoring)
            }
        }
        node.settingsChangedSubject.send()
    }
}

extension Node
{
    /// Brings the node to `settings` as an edit: through its graph as an undo
    /// step, or, for a node in no graph, directly.
    public func commitSettings(_ settings: any NodeSettings)
    {
        if let graph = self.graph
        {
            graph.setSettings(settings, on: self)
        }
        else if let current = self.settings, !current.isEqual(to: settings)
        {
            self.apply(settings)
            self.settingsChangedSubject.send()
        }
    }
}
