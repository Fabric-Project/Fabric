//
//  CloneSetCoordinator.swift
//  Fabric
//
//  Created by Claude on 10/9/26.
//

import Foundation

/// Per-document clone set state, owned by the root graph: the sync
/// re-entrancy flag and the debounced sync that follows edits inside a
/// member. See Graph+CloneSync.
///
/// Main thread only, like every other edit of a graph. Graph hands an edit
/// made elsewhere to the main actor before it reaches here.
final class CloneSetCoordinator
{
    /// Set while siblings are being re-instantiated, so the writes that
    /// makes are never mistaken for edits of their own.
    var isSyncing = false

    /// How long edits must pause before pending syncs run.
    var debounceInterval: Duration = .milliseconds(100)

    private(set) weak var rootGraph: Graph?

    /// The graph to sync each set from, by set id: the last graph edited
    /// inside one of its members.
    private var pendingSources: [UUID: Graph] = [:]
    private var debounceTask: Task<Void, Never>?

    init(rootGraph: Graph)
    {
        self.rootGraph = rootGraph
    }

    /// True between an edit inside a member and the sync that follows it.
    var hasPendingSync: Bool
    {
        !pendingSources.isEmpty
    }

    /// An edit landed in `graph`. Coalesces with other edits until they pause.
    /// Every set around the graph takes it as its source, replacing an
    /// earlier editor of the same set, since syncing from that one would
    /// overwrite the newer edit.
    func noteContentChanged(in graph: Graph)
    {
        dispatchPrecondition(condition: .onQueue(.main))

        for member in graph.enclosingCloneMembers
        {
            guard let setID = member.cloneSetID else { continue }
            pendingSources[setID] = graph
        }
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

    /// Runs every pending sync now, each set from the member of it that
    /// encloses the set's source. Nested sets go first, so an outer member
    /// is stored with its nested members already in step, and an outer sync
    /// never retires a source before that source has been synced from. The
    /// members involved then re-subscribe to their node trees, which the
    /// sync replaced. No-op while a sync is already running.
    func flush()
    {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isSyncing, let rootGraph else { return }

        debounceTask?.cancel()
        debounceTask = nil
        let sources = pendingSources
        pendingSources.removeAll()

        let syncs: [(member: SubgraphNode, depth: Int)] = sources.compactMap { setID, graph in
            let members = graph.enclosingCloneMembers
            guard let index = members.firstIndex(where: { $0.cloneSetID == setID }) else { return nil }
            return (members[index], members.count - index)
        }
        for sync in syncs.sorted(by: { $0.depth > $1.depth })
        {
            sync.member.graph?.reinstantiateCloneSiblings(of: sync.member)
        }

        for setID in sources.keys
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
        pendingSources.removeAll()
    }

    /// Waits for a pending debounce to run its sync, for callers that need
    /// the siblings in step now rather than after the pause.
    func settle() async
    {
        await debounceTask?.value
    }
}
