//
//  NodeSettingsDraft.swift
//  Fabric
//

import Foundation
import Combine
import Observation
import SwiftUI

/// A settings view's working copy of its node's settings. The node is not
/// written until the draft is committed, through Graph.setSettings, so the
/// draft can go anywhere and come back without touching a port: a draft equal
/// to the node's settings commits nothing.
///
/// The draft takes the node's value whenever the node's settings change as an
/// edit, undo and redo included; a draft not yet committed yields to it. A
/// draft on a node taken out of its graph is dropped: the node comes back, if
/// it does, as it was at its last commit.
///
/// The draft is the only undo record of what its controls edit: a control
/// bound to it records no typing undo on the document's undo manager (see
/// withoutTypingUndo()).
///
@MainActor
@Observable
final class NodeSettingsDraft<Settings: NodeSettings>
{
    var value: Settings
    {
        didSet
        {
            guard !self.isTakingNodeValue, self.value != oldValue else { return }
            self.draftDidChange()
        }
    }

    @ObservationIgnored private weak var node: Node?
    @ObservationIgnored private let wasInGraph: Bool
    @ObservationIgnored private let commitPolicy: EditCommit
    @ObservationIgnored private let pause: Duration
    @ObservationIgnored private let pendingCommit = PendingCommit()
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private var isTakingNodeValue = false

    /// A draft of `settings`, the settings of `node`. `pause` is how long an
    /// after-pause commit waits.
    init(of settings: Settings, on node: Node, commit: EditCommit, pause: Duration = .milliseconds(500))
    {
        self.pause = pause
        self.value = settings
        self.node = node
        self.wasInGraph = node.graph != nil
        self.commitPolicy = commit
        self.subscription = node.settingsChangedSubject.sink { [weak self] in
            // Edits, undo and redo are on the main thread; a reconnecting
            // device may tell of a change from another.
            if Thread.isMainThread
            {
                MainActor.assumeIsolated { self?.takeNodeValue() }
            }
            else
            {
                DispatchQueue.main.async { self?.takeNodeValue() }
            }
        }
    }

    /// Commits the draft now: as editing ends, or for a change that is its own
    /// step whatever the policy.
    func commit()
    {
        self.pendingCommit.cancel()
        guard let node else { return }
        guard !self.wasInGraph || node.graph != nil else
        {
            self.takeNodeValue()
            return
        }
        node.commitSettings(self.value)
    }

    /// A binding to one field of the draft that commits each change, for a
    /// toggle, picker or stepper in a view whose text commits after a pause.
    func committing<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value>
    {
        Binding(get: { self.value[keyPath: keyPath] },
                set: { newValue in
                    self.value[keyPath: keyPath] = newValue
                    self.commit()
                })
    }

    private func draftDidChange()
    {
        switch self.commitPolicy
        {
        case .eachChange:
            self.commit()
        case .afterPause:
            self.pendingCommit.schedule(after: self.pause, undoManager: self.node?.graph?.effectiveUndoManager) { [weak self] in
                self?.commit()
            }
        }
    }

    private func takeNodeValue()
    {
        self.pendingCommit.cancel()
        guard let settings = self.node?.settings as? Settings, settings != self.value else { return }
        self.isTakingNodeValue = true
        self.value = settings
        self.isTakingNodeValue = false
    }
}
