//
//  Graph+CloneSync.swift
//  Fabric
//
//  Created by Claude on 10/9/26.
//

import Foundation

/// Keeping a clone set in step: the member edited last is encoded as the
/// set's stored graph, and each sibling's sub graph is replaced with a fresh
/// instance decoded from it. Nothing is diffed: a sibling after a sync is a
/// sibling as a document load would make it, with the parent-facing things
/// that are its own put back, its proxies under their ids with the parent's
/// wires onto them, and its published inlet values. Everything the sibling
/// held at runtime, a movie's position, an integrator's sum, a feedback
/// buffer, starts over. See SubgraphNode.replaceSubGraph.
extension Graph
{
    /// Syncs every set that `graph` sits inside, innermost first, taking the
    /// enclosing member as the source each time.
    public func syncCloneSets(enclosing graph: Graph)
    {
        for member in graph.enclosingCloneMembers
        {
            member.graph?.reinstantiateCloneSiblings(of: member)
        }
    }

    /// Stores `member`'s sub graph as its set's graph and, where that changed
    /// the stored graph, re-instantiates every sibling from it. Registers no
    /// undo steps: the edit that caused this is undone on the member, and the
    /// siblings follow again. A sibling that cannot be decoded keeps what it
    /// has and is reported.
    public func reinstantiateCloneSiblings(of member: SubgraphNode)
    {
        guard member.cloneSetID != nil else { return }
        let coordinator = self.cloneSetCoordinator
        guard !coordinator.isSyncing else { return }
        coordinator.isSyncing = true
        defer { coordinator.isSyncing = false }

        do
        {
            guard try self.refreshCloneSetGraph(from: member) else { return }
        }
        catch
        {
            print("Clone set sync: \(member) could not be stored: \(error.localizedDescription)")
            return
        }

        for sibling in self.cloneSiblings(of: member)
        {
            do { try sibling.reinstantiateSubGraph() }
            catch { print("Clone set sync: \(sibling) not re-instantiated from \(member): \(error.localizedDescription)") }
        }
    }

    /// Makes `target` an instance of `source`'s sub graph now, whether or not
    /// the stored graph changed. Throws where the two are not members of one
    /// set.
    public func reinstantiateCloneMember(_ target: SubgraphNode, from source: SubgraphNode) throws
    {
        guard let setID = source.cloneSetID, target.cloneSetID == setID, target !== source else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(target) and \(source) are not members of one clone set.")
        }

        let coordinator = self.cloneSetCoordinator
        coordinator.isSyncing = true
        defer { coordinator.isSyncing = false }

        try self.refreshCloneSetGraph(from: source)
        try target.reinstantiateSubGraph()
    }

    /// Runs any sync still waiting on the debounce, so a document is saved
    /// with every set in step. The sync is a graph edit and runs on the main
    /// thread; a save asks from a background queue and waits for it, since
    /// it would otherwise encode stale members.
    public func flushPendingCloneSync()
    {
        if Thread.isMainThread
        {
            self.cloneSetCoordinator.flush()
        }
        else
        {
            DispatchQueue.main.sync { self.cloneSetCoordinator.flush() }
        }
    }
}
