//
//  CloneSetCoordinator.swift
//  Fabric
//
//  Created by Claude on 9/10/26.
//

import Foundation

/// Keeps a document's clone sets in step; owned by the root graph. Edits are
/// marked by the document's undo manager: when an undo group closes, and
/// after an undo or redo, each set is synced from the member of it whose
/// design is no longer the set's. An edit that registers no undo is caught by
/// the next one that does, and by the explicit syncs: leaving a canvas,
/// closing a node's settings, deleting a member.
final class CloneSetCoordinator
{
    /// Set while a sync runs, so the writes it makes are never taken for edits.
    var isSyncing = false

    private(set) weak var rootGraph: Graph?
    private var observations: [NSObjectProtocol] = []

    init(rootGraph: Graph)
    {
        self.rootGraph = rootGraph
    }

    deinit
    {
        observations.forEach(NotificationCenter.default.removeObserver)
    }

    /// Follows `undoManager`'s edits, in place of any it followed before.
    func attach(to undoManager: UndoManager?)
    {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations = []
        guard let undoManager else { return }

        let center = NotificationCenter.default
        let syncAfterEdit: (Notification) -> Void = { [weak self, weak undoManager] _ in
            // A nested group closes partway through an edit; undo and redo
            // report themselves.
            guard let undoManager, undoManager.groupingLevel == 0,
                  !undoManager.isUndoing, !undoManager.isRedoing
            else { return }
            self?.sync()
        }
        let syncAfterUndo: (Notification) -> Void = { [weak self] _ in self?.sync() }
        observations = [
            center.addObserver(forName: .NSUndoManagerDidCloseUndoGroup, object: undoManager, queue: nil, using: syncAfterEdit),
            center.addObserver(forName: .NSUndoManagerDidUndoChange, object: undoManager, queue: nil, using: syncAfterUndo),
            center.addObserver(forName: .NSUndoManagerDidRedoChange, object: undoManager, queue: nil, using: syncAfterUndo),
        ]
    }

    /// Syncs each set from its first member found out of step, innermost
    /// members first, so an outer member is compared with the members nested
    /// in it already in step. No-op while a sync is running, and off the main
    /// thread: a graph changed elsewhere is being built or decoded, not
    /// edited, and syncs once it is edited.
    func sync()
    {
        guard Thread.isMainThread, !isSyncing, let rootGraph, !rootGraph.cloneSets.isEmpty else { return }

        let members = rootGraph.subgraphNodesRecursive()
            .filter { $0.cloneSetID != nil }
            .map { (member: $0, depth: $0.subGraph.enclosingCloneMembers.count) }
            .sorted { $0.depth > $1.depth }

        var syncedSetIDs = Set<UUID>()
        for (member, _) in members
        {
            // A sync can retire what an earlier one in this pass held.
            guard let setID = member.cloneSetID, !syncedSetIDs.contains(setID),
                  let graph = member.graph, graph.rootGraph === rootGraph,
                  !graph.isCloneMemberInStep(member)
            else { continue }

            syncedSetIDs.insert(setID)
            graph.syncCloneSiblings(of: member)
        }
    }
}

extension Graph
{
    /// Brings every clone set in the document in step now, each from the
    /// member of it that has moved on. The editor's undo groups do this as
    /// edits are made; edits made through the API outside an undo group call
    /// it themselves.
    public func syncCloneSets()
    {
        self.cloneSetCoordinator.sync()
    }
}
