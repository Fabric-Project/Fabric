//
//  PendingCommit.swift
//  Fabric
//

import Foundation

/// An edit a control holds back until it pauses, as typing does, or until the
/// control's edit ends. Graph.undo() and redo() commit every one held for the
/// undo manager they drive before they run, so an undo never passes over a
/// change the user has made, and Graph.canUndo counts them. Used on the main
/// thread.
final class PendingCommit
{
    private var commit: (() -> Void)?
    private var timer: Task<Void, Never>?

    /// Holds `commit` until the control commits it or Graph.undo() does,
    /// replacing any commit held. `undoManager` is the one the commit
    /// records on.
    func hold(on undoManager: UndoManager?, _ commit: @escaping () -> Void)
    {
        self.cancel()
        self.commit = commit
        if let undoManager { Self.register(self, on: undoManager) }
    }

    /// Holds `commit` for `delay`, replacing any commit held; see hold(on:_:).
    func schedule(after delay: Duration, undoManager: UndoManager?, _ commit: @escaping () -> Void)
    {
        self.hold(on: undoManager, commit)
        self.timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush()
    {
        let commit = self.commit
        self.cancel()
        commit?()
    }

    /// Drops what is held.
    func cancel()
    {
        self.commit = nil
        self.timer?.cancel()
        self.timer = nil
    }

    deinit { self.cancel() }

    // MARK: - Registry

    private struct Entry
    {
        weak var pendingCommit: PendingCommit?
    }

    /// The commits held for each undo manager, weakly; an entry whose commit
    /// has gone or holds nothing is swept as the registry is read.
    private static var registry: [ObjectIdentifier: [Entry]] = [:]

    private static func register(_ pendingCommit: PendingCommit, on undoManager: UndoManager)
    {
        let key = ObjectIdentifier(undoManager)
        var entries = self.registry[key, default: []].filter { $0.pendingCommit?.commit != nil && $0.pendingCommit !== pendingCommit }
        entries.append(Entry(pendingCommit: pendingCommit))
        self.registry[key] = entries
    }

    /// Whether a commit is held for `undoManager`.
    static func hasCommits(on undoManager: UndoManager) -> Bool
    {
        self.registry[ObjectIdentifier(undoManager), default: []].contains { $0.pendingCommit?.commit != nil }
    }

    /// Commits now every commit held for `undoManager`.
    static func commitAll(on undoManager: UndoManager)
    {
        let key = ObjectIdentifier(undoManager)
        let pending = (self.registry.removeValue(forKey: key) ?? []).compactMap(\.pendingCommit)
        self.registry = self.registry.filter { !$0.value.allSatisfy { $0.pendingCommit?.commit == nil } }
        pending.forEach { $0.flush() }
    }
}
