//
//  NodeViewModel.swift
//  Fabric
//

import SwiftUI
import Combine
import Satin

/// The SwiftUI-observable face of a Node.
///
/// Graph automatically creates and destroys one NodeViewModel per Node.
/// Node developers never interact with this class — all observation,
/// selection state, drag state, and settings visibility live here so
/// that Node itself remains a pure data/execution model.
@Observable public final class NodeViewModel: Identifiable
{
    public typealias ID = UUID

    // MARK: - Identity
    public let id: UUID

    /// The underlying data/execution model. Strong — Graph owns Node;
    /// NodeViewModel is ephemeral and created/destroyed alongside it.
    public let node: Node

    // MARK: - Pure view state (never serialised)
    public var isSelected: Bool = false
    public var isDragging: Bool = false

    /// Whether the node's settings panel is open.
    /// Writing true/false also syncs node.showSettings so subclasses
    /// can still inspect it (e.g. AudioSpectrumNode).
    public var showSettings: Bool = false
    {
        didSet { node.showSettings = showSettings }
    }

    // MARK: - Layout (Observable here, authoritative on Node for Codable)

    public var offset: CGSize
    {
        get { _offset }
        set { _offset = newValue; node.offset = newValue }
    }
    private var _offset: CGSize

    // MARK: - User name (Observable here, authoritative on Node for Codable)

    public var userName: String?
    {
        get { _userName }
        set { _userName = newValue; node.userName = newValue }
    }
    private var _userName: String?

    public var name: String
    {
        if let u = _userName, !u.isEmpty { return u }
        return _nodeName
    }

    private var _nodeName: String

    // MARK: - Forwarded node metadata

    public var nodeType: Node.NodeType { node.nodeType }

    // MARK: - Ports + nodeSize (stored; updated when ports change)

    public private(set) var ports: [Port]
    public private(set) var nodeSize: CGSize

    // MARK: - Parameters (stable reference — ParameterGroup is not @Observable)

    public var parameterGroup: ParameterGroup { node.parameterGroup }

    // MARK: - Settings view delegation

    public func providesSettingsView() -> Bool { node.providesSettingsView() }
    public func settingsView() -> AnyView      { node.settingsView() }
    public var settingsSize: Node.SettingsViewSize { node.settingsSize }

    // MARK: - Init

    private var cancellables: Set<AnyCancellable> = []

    public init(node: Node)
    {
        self.id           = node.id
        self.node         = node
        self._offset      = node.offset
        self._userName    = node.userName
        self._nodeName    = node.name
        self.ports        = node.ports
        self.nodeSize     = node.nodeSize

        // Sync offset when graph operations (paste, duplicate, auto-layout)
        // set node.offset directly.
        node.offsetSubject
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newOffset in
                self?._offset = newOffset
            }
            .store(in: &cancellables)

        // Sync port list + nodeSize when dynamic ports are added/removed.
        node.portsChangedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.ports    = node.ports
                self.nodeSize = node.nodeSize
            }
            .store(in: &cancellables)

        // Sync cached name when nodes with dynamic names (e.g. MathExpressionNode,
        // StringFormatterNode) change their computed name after user edits.
        node.nameSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?._nodeName = node.name
            }
            .store(in: &cancellables)
    }
}
