//
//  NodeSettingsSession.swift
//  Fabric
//

import Foundation

/// A node's settings being edited in its settings view. What the view edits
/// is recorded as one undo step each time the editing pauses: when the view
/// closes, and before anything is undone or redone, so an undo never passes
/// over a change not yet recorded. A settings view edits its node freely,
/// typing in a script or dragging a key on a timeline, and takes one step for
/// it rather than one per keystroke. NodeSettingView holds one while it is
/// shown.
public final class NodeSettingsSession
{
    private let node: Node
    /// The graph the node was in as the session began: a change made before
    /// the node was taken out of it, as a delete does, is still its step.
    private weak var graph: Graph?
    private var observations: [NSObjectProtocol] = []
    private var hasEnded = false
    private var hasFinished = false
    private var isRecording = false
    /// An ended session holds itself until the next checkpoint, and records
    /// then what a control wrote as it went away after the view ended it, as
    /// a code editor writes the text it holds.
    private var lingering: NodeSettingsSession?

    public init(node: Node)
    {
        self.node = node
        self.graph = node.graph
        node.settingsSessionCount += 1
        if node.settingsSessionCount == 1 { node.recordedSettings = node.settingsSnapshot() }

        // Undo and redo, and every group that opens, check in here first,
        // and every edit, undo and redo once done, so the next step starts
        // from the ports and wires that edit left.
        guard let undoManager = node.graph?.effectiveUndoManager else { return }
        let names: [Notification.Name] = [.NSUndoManagerCheckpoint, .NSUndoManagerDidCloseUndoGroup,
                                          .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange]
        self.observations = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: nil) { [weak self, weak undoManager] _ in
                // A group closing inside an edit, with registration off, is
                // part of something else; the group a step opens is its own.
                guard let self, !self.isRecording, let undoManager, undoManager.groupingLevel == 0,
                      undoManager.isUndoRegistrationEnabled,
                      !undoManager.isUndoing, !undoManager.isRedoing
                else { return }
                self.record()
                if self.hasEnded { self.finish() }
            }
        }
    }

    deinit
    {
        if !hasEnded
        {
            hasEnded = true
            self.record()
        }
        self.finish()
    }

    /// Records the settings edited since the last step, if they changed.
    /// Otherwise takes what is there now as where the next step starts from,
    /// since the ports and wires around the settings may have changed in edits
    /// of their own.
    public func record()
    {
        guard let graph = node.graph ?? self.graph,
              let before = node.recordedSettings,
              let now = node.settingsSnapshot()
        else { return }
        guard now.settings != before.settings else
        {
            node.recordedSettings = now
            return
        }

        // Opening the group checks in here again.
        isRecording = true
        defer { isRecording = false }
        let undoManager = graph.effectiveUndoManager
        let opensGroup = undoManager?.groupingLevel == 0
        if opensGroup { undoManager?.beginUndoGrouping() }
        graph.registerSettingsChange(of: node, from: before)
        if opensGroup { undoManager?.endUndoGrouping() }
    }

    /// Records what is left, and stops following the node's edits at the
    /// next checkpoint.
    public func end()
    {
        guard !hasEnded else { return }
        hasEnded = true
        self.record()
        if self.observations.isEmpty { self.finish() } else { self.lingering = self }
    }

    private func finish()
    {
        guard !hasFinished else { return }
        hasFinished = true
        self.observations.forEach(NotificationCenter.default.removeObserver)
        self.observations = []
        node.settingsSessionCount -= 1
        if node.settingsSessionCount == 0 { node.recordedSettings = nil }
        self.lingering = nil
    }
}

extension Node
{
    /// A node's settings as encodeSettings(to:) writes them, with what a
    /// settings change can take from the node's ports: each port's state, for
    /// a port the change removes to come back as it was, the wires on them,
    /// and for a published port what the proxies standing for it hold up the
    /// chain (see Graph.ProxyChainState).
    struct SettingsSnapshot
    {
        let settings: Data
        let ports: [PortRegistry.Snapshot]
        let connections: [Graph.Wire]
        /// What the proxies standing for each published port hold further
        /// up, by the port's id.
        let proxyChains: [UUID: Graph.ProxyChainState]
    }

    /// nil for a node with no settings.
    func settingsSnapshot() -> SettingsSnapshot?
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let settings = try? encoder.encode(SettingsWriter(node: self)) else { return nil }

        let portIDs = Set(self.ports.map(\.id))
        let connections = self.graph?.connections.filter {
            portIDs.contains($0.outletPortID) || portIDs.contains($0.inletPortID)
        }.map(Graph.Wire.init) ?? []
        var proxyChains: [UUID: Graph.ProxyChainState] = [:]
        if let graph = self.graph
        {
            for port in self.ports where port.published
            {
                proxyChains[port.id] = graph.proxyChainState(standingFor: port)
            }
        }
        return SettingsSnapshot(settings: settings, ports: self.portSnapshots(), connections: connections, proxyChains: proxyChains)
    }

    /// Puts the node's settings back as `snapshot` holds them, its ports and
    /// their wires with them.
    func restore(_ snapshot: SettingsSnapshot) throws
    {
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: self.context)
        decoder.userInfo[SettingsReader.nodeKey] = self
        try self.withPortHydration(from: snapshot.ports) {
            _ = try decoder.decode(SettingsReader.self, from: snapshot.settings)
        }
        defer { self.settingsRestoredSubject.send() }
        guard let graph = self.graph else { return }
        // A port the change replaced may have kept its wire.
        for wire in snapshot.connections
        {
            graph.restore(wire)
        }

        for (portID, chain) in snapshot.proxyChains
        {
            guard let port = self.ports.first(where: { $0.id == portID }), port.published else { continue }
            graph.restoreProxyChain(standingFor: port, to: chain)
        }
    }
}

/// Writes a node's settings alone. A node with none writes nothing, which
/// fails the encode.
private struct SettingsWriter: Encodable
{
    let node: Node
    func encode(to encoder: Encoder) throws { try node.encodeSettings(to: encoder) }
}

private struct SettingsReader: Decodable
{
    static let nodeKey = CodingUserInfoKey(rawValue: "graphics.fabric.settingsNode")!

    init(from decoder: Decoder) throws
    {
        guard let node = decoder.userInfo[Self.nodeKey] as? Node else { return }
        try node.restoreSettings(from: decoder)
    }
}

extension Graph
{
    /// Records a change to `node`'s settings, from `before` to what they are
    /// now, as an undo step. A node whose settings change outside its settings
    /// view, as a strategy follows a wire, records the change here itself.
    internal func registerSettingsChange(of node: Node, from before: Node.SettingsSnapshot)
    {
        if node.settingsSessionCount > 0 { node.recordedSettings = node.settingsSnapshot() }
        self.registerUndo(on: node) { node in
            node.graph?.restoreSettings(of: node, to: before)
        }
        self.effectiveUndoManager?.setActionName("Change Settings")
    }

    /// Records the settings edit open in `node`'s settings view, if any. An
    /// edit that takes the node out of the graph records this first: a step
    /// registered after the node left finds no node to put the settings back
    /// on.
    internal func recordOpenSettingsChange(of node: Node)
    {
        guard node.settingsSessionCount > 0,
              let before = node.recordedSettings,
              let now = node.settingsSnapshot(),
              now.settings != before.settings
        else { return }
        self.registerSettingsChange(of: node, from: before)
    }

    private func restoreSettings(of node: Node, to snapshot: Node.SettingsSnapshot)
    {
        guard let current = node.settingsSnapshot() else { return }
        self.withoutUndoRegistration {
            do { try node.restore(snapshot) }
            catch { print("Graph: the settings of \(node) could not be put back: \(error.localizedDescription)") }
        }
        self.registerSettingsChange(of: node, from: current)
    }
}
