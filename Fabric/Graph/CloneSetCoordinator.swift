//
//  CloneSetCoordinator.swift
//  Fabric
//

import Foundation

/// Keeps a document's clone sets in step; owned by the root graph. Every edit
/// registers its undo step through the graph it was made in (see
/// Graph.registerUndo), and that graph is noted here. As the document's undo
/// group closes, each set around a noted graph is synced from its member
/// there, innermost sets first, and the sync registers its own steps into
/// that group: undo and redo put the siblings back with the edit, and sync
/// nothing themselves. An edit that registers no undo is synced by
/// syncCloneSets(editedIn:); a sync with no undo group open registers
/// nothing.
final class CloneSetCoordinator
{
    /// Set while a sync runs, so the writes it makes are never taken for edits.
    var isSyncing = false

    private(set) weak var rootGraph: Graph?
    private weak var undoManager: UndoManager?
    private var observations: [NSObjectProtocol] = []

    /// The graphs inside members that edits were made in since the last
    /// sync, the latest last.
    private var editedGraphs: [Graph] = []

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
        self.undoManager = undoManager
        guard let undoManager else { return }

        // A nested group closes partway through an edit, and undo and redo
        // replay the steps the sync registered.
        observations = [
            NotificationCenter.default.addObserver(forName: .NSUndoManagerWillCloseUndoGroup, object: undoManager, queue: nil) { [weak self, weak undoManager] _ in
                guard let undoManager, undoManager.groupingLevel == 1,
                      !undoManager.isUndoing, !undoManager.isRedoing
                else { return }
                self?.sync()
            },
        ]
    }

    /// An edit was made in `graph`. Only one inside a member can need a sync,
    /// and none made by a sync or replayed by undo or redo, or off the main
    /// thread, where a graph is being built or decoded rather than edited.
    func noteEdit(in graph: Graph)
    {
        guard Thread.isMainThread, !isSyncing,
              undoManager?.isUndoing != true, undoManager?.isRedoing != true,
              !graph.enclosingCloneMembers.isEmpty
        else { return }
        editedGraphs.removeAll { $0 === graph }
        editedGraphs.append(graph)
    }

    /// Syncs each set around the graphs edited since the last sync from its
    /// member there, innermost sets first, so an outer member is read with
    /// the members nested in it already in step. A set edited in two members
    /// takes the later edit.
    func sync()
    {
        guard Thread.isMainThread, !isSyncing, let rootGraph else { return }
        let edited = editedGraphs
        editedGraphs.removeAll()

        var sourceBySetID: [UUID: (member: SubgraphNode, depth: Int)] = [:]
        for graph in edited where graph.rootGraph === rootGraph
        {
            let members = graph.enclosingCloneMembers
            for (index, member) in members.enumerated()
            {
                guard let setID = member.cloneSetID else { continue }
                sourceBySetID[setID] = (member, members.count - index)
            }
        }

        for source in sourceBySetID.values.sorted(by: { $0.depth > $1.depth })
        {
            // A sync earlier in this pass can retire what a later one held.
            guard let graph = source.member.graph, graph.rootGraph === rootGraph else { continue }
            graph.syncCloneSiblings(of: source.member)
        }
    }
}

extension Graph
{
    /// Syncs the clone sets around every graph edited since the last sync.
    /// The editor's undo groups do this as edits are made.
    public func syncCloneSets()
    {
        self.cloneSetCoordinator.sync()
    }

    /// Syncs the clone sets around `graph` from the members around it, for an
    /// edit made there through the API that registered no undo.
    public func syncCloneSets(editedIn graph: Graph)
    {
        self.cloneSetCoordinator.noteEdit(in: graph)
        self.cloneSetCoordinator.sync()
    }
}
