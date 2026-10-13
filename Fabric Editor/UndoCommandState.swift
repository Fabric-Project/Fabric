//
//  UndoCommandState.swift
//  Fabric Editor
//

import Foundation
import Observation

/// The Undo and Redo menu items' titles and enabled state, read from the
/// document's undo manager as its notifications come. Reading canRedo or a
/// menu item title posts the manager's checkpoint notification, so the menu
/// reads this rather than the manager as SwiftUI evaluates it.
@MainActor
@Observable
final class UndoCommandState
{
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoTitle = "Undo"
    private(set) var redoTitle = "Redo"

    @ObservationIgnored private weak var undoManager: UndoManager?
    @ObservationIgnored private var observations: [NSObjectProtocol] = []
    @ObservationIgnored private var isRefreshing = false

    /// Follows `undoManager` from now on.
    func follow(_ undoManager: UndoManager?)
    {
        guard undoManager !== self.undoManager || self.observations.isEmpty else { return }
        self.observations.forEach(NotificationCenter.default.removeObserver)
        self.observations = []
        self.undoManager = undoManager

        if let undoManager
        {
            let names: [Notification.Name] = [.NSUndoManagerDidOpenUndoGroup, .NSUndoManagerDidCloseUndoGroup,
                                              .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
                                              .NSUndoManagerCheckpoint]
            self.observations = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: nil) { [weak self] _ in
                    // The document's undo manager is driven on the main thread.
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        }
        self.refresh()
    }

    private func refresh()
    {
        // Reading the flags posts a checkpoint, which comes back here.
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }

        let canUndo = self.undoManager?.canUndo ?? false
        let canRedo = self.undoManager?.canRedo ?? false
        let undoTitle = self.undoManager?.undoMenuItemTitle ?? "Undo"
        let redoTitle = self.undoManager?.redoMenuItemTitle ?? "Redo"
        if self.canUndo != canUndo { self.canUndo = canUndo }
        if self.canRedo != canRedo { self.canRedo = canRedo }
        if self.undoTitle != undoTitle { self.undoTitle = undoTitle }
        if self.redoTitle != redoTitle { self.redoTitle = redoTitle }
    }
}
