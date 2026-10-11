//
//  Graph+CloneSync.swift
//  Fabric
//
//  Created by Claude on 10/9/26.
//

import Foundation
import Satin

/// Keeping a clone set in step: the member edited last is encoded as the
/// set's stored graph, and each sibling's sub graph is replaced with a fresh
/// instance decoded from it. Nothing is diffed: a sibling after a sync is a
/// sibling as a document load would make it, with the parent-facing things
/// that are its own put back, its proxies under their ids with the parent's
/// wires onto them, and its published inlet values. Everything the sibling
/// held at runtime, a movie's position, an integrator's sum, a feedback
/// buffer, starts over. See SubgraphNode.replaceSubGraph.
///
/// Inside an open undo group a sync registers its own steps there: one that
/// puts the stored graph back, and one per sibling that puts the sibling back
/// as it was (see CloneMemberState). Undo and redo replay them and sync
/// nothing. With no undo group open, a sync registers nothing.
extension Graph
{
    /// How the coordinator brings a member's siblings in line with it.
    internal func syncCloneSiblings(of member: SubgraphNode)
    {
        self.reinstantiateCloneSiblings(of: member)
    }

    /// Stores `member`'s sub graph as its set's graph and, where that changed
    /// the stored graph, re-instantiates every sibling from it, undoably
    /// where an undo group is open. A sibling that cannot be decoded keeps
    /// what it has and is reported.
    public func reinstantiateCloneSiblings(of member: SubgraphNode)
    {
        guard member.cloneSetID != nil, !self.cloneSetCoordinator.isSyncing else { return }

        self.whileSyncingClones {
            do
            {
                guard try self.refreshCloneSetGraphUndoably(from: member) else { return }
            }
            catch
            {
                print("Clone set sync: \(member) could not be stored: \(error.localizedDescription)")
                return
            }

            for sibling in self.cloneSiblings(of: member)
            {
                do { try self.reinstantiateCloneMemberUndoably(sibling) }
                catch { print("Clone set sync: \(sibling) not re-instantiated from \(member): \(error.localizedDescription)") }
            }
        }
    }

    /// Makes `target` an instance of `source`'s sub graph now, whether or not
    /// the stored graph changed, undoably where an undo group is open. Throws
    /// where the two are not members of one set.
    internal func reinstantiateCloneMember(_ target: SubgraphNode, from source: SubgraphNode) throws
    {
        guard let setID = source.cloneSetID, target.cloneSetID == setID, target !== source else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(target) and \(source) are not members of one clone set.")
        }

        try self.whileSyncingClones {
            try self.refreshCloneSetGraphUndoably(from: source)
            try self.reinstantiateCloneMemberUndoably(target)
        }
    }

    /// Runs `body` as a sync, its writes not taken for edits. With no undo
    /// group open, nothing it does is registered: an undo step registered
    /// then would open a group of its own and stand apart from the edit.
    private func whileSyncingClones<Result>(_ body: () throws -> Result) rethrows -> Result
    {
        let coordinator = self.cloneSetCoordinator
        let wasSyncing = coordinator.isSyncing
        coordinator.isSyncing = true
        defer { coordinator.isSyncing = wasSyncing }

        guard let undoManager = self.effectiveUndoManager,
              undoManager.groupingLevel > 0, undoManager.isUndoRegistrationEnabled
        else { return try self.withoutUndoRegistration(body) }
        return try body()
    }

    /// refreshCloneSetGraph, with a step that puts the stored graph back.
    @discardableResult
    private func refreshCloneSetGraphUndoably(from member: SubgraphNode) throws -> Bool
    {
        guard let setID = member.cloneSetID, let set = self.cloneSet(for: setID) else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(member) is not in a clone set.")
        }
        let previous = set.graphJSON
        guard try self.refreshCloneSetGraph(from: member) else { return false }
        self.registerCloneSetGraphRestore(setID, to: previous)
        return true
    }

    private func registerCloneSetGraphRestore(_ setID: UUID, to graphJSON: Data)
    {
        self.registerUndo { graph in
            guard let set = graph.cloneSet(for: setID) else { return }
            let current = set.graphJSON
            set.graphJSON = graphJSON
            graph.registerCloneSetGraphRestore(setID, to: current)
        }
    }

    /// Re-instantiates `member` from its set's stored graph, with a step on
    /// its graph that puts it back as it was.
    private func reinstantiateCloneMemberUndoably(_ member: SubgraphNode) throws
    {
        guard let parent = member.graph else { return }
        let registers = parent.effectiveUndoManager?.isUndoRegistrationEnabled == true
        let before = registers ? try member.cloneMemberState() : nil

        try member.reinstantiateSubGraph()
        // An unpublish takes the proxy from the member, and any proxy over it
        // published further up, but not the wires onto them.
        parent.pruneDanglingConnectionsOutward()

        if let before { parent.registerCloneMemberRestore(member, to: before) }
    }

    /// Registers the step that puts `member`, a node in this graph, back to
    /// `state`. It registers the opposite step in turn, with the state the
    /// member had when it ran.
    private func registerCloneMemberRestore(_ member: SubgraphNode, to state: CloneMemberState)
    {
        self.registerUndo(on: member) { member in
            guard let graph = member.graph else { return }
            let coordinator = graph.cloneSetCoordinator
            let wasSyncing = coordinator.isSyncing
            coordinator.isSyncing = true
            defer { coordinator.isSyncing = wasSyncing }

            do
            {
                let current = try member.cloneMemberState()
                try graph.withoutUndoRegistration { try graph.restoreCloneMember(member, to: state) }
                graph.registerCloneMemberRestore(member, to: current)
            }
            catch { print("Clone set undo: \(member) not put back: \(error.localizedDescription)") }
        }
    }

    /// Puts `member` back to `state`: its sub graph decoded from the state's
    /// encoding, then each proxy's published state and the wires onto it,
    /// level by level up, as they were. Registers nothing.
    private func restoreCloneMember(_ member: SubgraphNode, to state: CloneMemberState) throws
    {
        guard let object = CloneSet.jsonObject(from: state.subGraphJSON) else
        {
            throw recoverableGraphError(.cloneOperationFailed, message: "\(member)'s earlier sub graph could not be read.")
        }
        let instance = try Self.decodeCloneInstance(of: object, decodeContext: self.makeDecoderContext())
        member.replaceSubGraph(with: instance, keepingOwnValues: false)
        self.pruneDanglingConnectionsOutward()

        for (innerPortID, chain) in state.proxyChains
        {
            guard let port = instance.nodePort(forID: innerPortID) else { continue }
            instance.restoreProxyChain(standingFor: port, to: chain)
        }

        // As a sync does: a canvas inside the member follows the replacement.
        self.rootGraph.cloneSyncCount += 1
    }

    /// Drops dangling wires in this graph and every graph around it.
    private func pruneDanglingConnectionsOutward()
    {
        for graph in self.ancestors { graph.pruneDanglingConnections() }
    }
}

/// A clone set member as a sync found it, for the undo step that puts it
/// back: its sub graph encoded whole, its own values and nested members in
/// it, and for each proxy the state of the chain of proxies over it, the
/// parent's wires and published state at each level. Held by the undo stack:
/// one encoding of the member's sub graph per sibling per edit.
internal struct CloneMemberState
{
    let subGraphJSON: Data
    let proxyChains: [UUID: Graph.ProxyChainState]
}

extension SubgraphNode
{
    internal func cloneMemberState() throws -> CloneMemberState
    {
        let chains = self.subGraph.getPublishedPorts().map { ($0.id, self.subGraph.proxyChainState(standingFor: $0)) }
        return CloneMemberState(subGraphJSON: try JSONEncoder().encode(self.subGraph),
                                proxyChains: Dictionary(chains, uniquingKeysWith: { first, _ in first }))
    }
}
