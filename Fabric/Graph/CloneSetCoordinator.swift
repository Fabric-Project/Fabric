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
/// Main thread only. Edits, syncs and the debounce all happen there, as does
/// every other edit of a graph; a call from elsewhere is moved to the main
/// actor rather than run in place.
public final class CloneSetCoordinator
{
    /// Set while a member is being brought in line with its set, so the
    /// writes that reconcile makes are never mistaken for edits of their own.
    var isReconciling = false

    /// How long edits must pause before pending syncs run.
    public var debounceInterval: Duration = .milliseconds(100)

    private(set) weak var rootGraph: Graph?
    private var pendingGraphs: [Graph] = []
    private var debounceTask: Task<Void, Never>?

    init(rootGraph: Graph)
    {
        self.rootGraph = rootGraph
    }

    /// True between an edit inside a member and the sync that follows it.
    public var hasPendingSync: Bool
    {
        !pendingGraphs.isEmpty
    }

    /// An edit landed in `graph`. Coalesces with other edits until they pause.
    func noteContentChanged(in graph: Graph)
    {
        guard Thread.isMainThread else
        {
            Task { @MainActor [weak self] in self?.noteContentChanged(in: graph) }
            return
        }

        if !pendingGraphs.contains(where: { $0 === graph }) { pendingGraphs.append(graph) }

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
    public func flush()
    {
        guard Thread.isMainThread else
        {
            Task { @MainActor [weak self] in self?.flush() }
            return
        }
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

    /// Waits for a pending debounce to run its sync, for callers that need
    /// the siblings in step now rather than after the pause.
    public func settle() async
    {
        await debounceTask?.value
    }
}
