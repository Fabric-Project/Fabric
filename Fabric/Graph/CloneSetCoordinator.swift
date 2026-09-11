//
//  CloneSetCoordinator.swift
//  Fabric
//
//  Created by Claude on 9/10/26.
//

import Foundation

/// Per-document clone set state, owned by the root graph: the reconcile
/// re-entrancy flag and the debounced sync that follows edits inside a
/// member. See Graph+CloneSet.
///
/// Main thread only, like every other edit of a graph. Graph hands an edit
/// made elsewhere to the main actor before it reaches here.
final class CloneSetCoordinator
{
    /// Set while a member is being brought in line with its set, so the
    /// writes that reconcile makes are never mistaken for edits of their own.
    var isReconciling = false

    /// How long edits must pause before pending syncs run.
    var debounceInterval: Duration = .milliseconds(100)

    private(set) weak var rootGraph: Graph?
    private var pendingGraphs: [Graph] = []
    private var debounceTask: Task<Void, Never>?

    init(rootGraph: Graph)
    {
        self.rootGraph = rootGraph
    }

    /// True between an edit inside a member and the sync that follows it.
    var hasPendingSync: Bool
    {
        !pendingGraphs.isEmpty
    }

    /// An edit landed in `graph`. Coalesces with other edits until they pause.
    /// The last graph edited in a set is that set's source: an earlier
    /// pending graph in any of the same sets is dropped, since syncing from
    /// it would overwrite the newer edit.
    func noteContentChanged(in graph: Graph)
    {
        dispatchPrecondition(condition: .onQueue(.main))

        // A pending graph nested inside this one already covers every set
        // around this one, and syncs them from the same members: an edit in a
        // nested member is noted by the outer member's observer as well.
        guard !pendingGraphs.contains(where: { $0 === graph || $0.isDescendant(of: graph) }) else
        {
            restartDebounce()
            return
        }

        // Otherwise this graph is the later editor of its sets: drop pending
        // graphs whose sets it covers entirely, keep those with sets of their
        // own to sync.
        let setIDs = Set(graph.enclosingCloneMembers.compactMap(\.cloneSetID))
        pendingGraphs.removeAll { pending in
            Set(pending.enclosingCloneMembers.compactMap(\.cloneSetID)).isSubset(of: setIDs)
        }
        pendingGraphs.append(graph)
        restartDebounce()
    }

    private func restartDebounce()
    {
        debounceTask?.cancel()
        let interval = self.debounceInterval
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Runs every pending sync now. Each edited graph is the source for the
    /// sets around it; a graph edited while a sync was pending is picked up
    /// by that sync. The members involved then re-subscribe to their node
    /// trees, which the sync may have changed. No-op while a reconcile is
    /// already running.
    func flush()
    {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isReconciling, let rootGraph else { return }

        debounceTask?.cancel()
        debounceTask = nil
        let graphs = pendingGraphs
        pendingGraphs.removeAll()

        var touchedSetIDs = Set<UUID>()
        for graph in graphs
        {
            rootGraph.reconcileCloneSets(enclosing: graph)
            touchedSetIDs.formUnion(graph.enclosingCloneMembers.compactMap(\.cloneSetID))
        }

        for setID in touchedSetIDs
        {
            for member in rootGraph.cloneSetMembers(of: setID)
            {
                member.cloneObserver?.refresh()
            }
        }
    }

    /// Drops any pending sync without running it. For tests that want a
    /// member's edit left unseen by its set.
    func discardPendingSync()
    {
        dispatchPrecondition(condition: .onQueue(.main))
        debounceTask?.cancel()
        debounceTask = nil
        pendingGraphs.removeAll()
    }

    /// Waits for a pending debounce to run its sync, for callers that need
    /// the siblings in step now rather than after the pause.
    func settle() async
    {
        await debounceTask?.value
    }
}
