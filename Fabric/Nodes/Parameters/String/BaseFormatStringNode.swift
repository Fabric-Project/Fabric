//
//  BaseFormatStringNode.swift
//  Fabric
//
//  Shared base for the nodes driven by a `{name:spec}` format string — String
//  Formatter, which substitutes values into it, and String Scanner, which reads
//  values back out. Everything the two share lives here: the format string and
//  its serialization, the Settings pane, and the ports the placeholders
//  declare. A subclass says what a placeholder's port looks like and what to do
//  once the ports follow an edit; the rest is not its business.
//
//  The format string is Settings-view state, never a port: it decides how many
//  ports the node has and of what type, so a graph-driven edit would churn ports
//  and drop wires on every change.
//

import Foundation
import Satin
import SwiftUI

// MARK: - Settings View

/// The format-string field with the guidance its node supplies. The syntax is
/// shared, so the field is too; only the wording above it differs.
struct FormatStringSettingsView: View {
    @Bindable var model: BaseFormatStringNode.SettingsModel
    let guidance: String

    var body: some View {
        VStack(alignment: .leading) {
            // As a LocalizedStringKey, so the guidance keeps the markdown
            // styling it had when it was written inline.
            Text(.init(guidance))

            Spacer()

            TextField("Format String", text: $model.formatString)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

/// The settings of a format-string node.
public struct FormatStringSettings: NodeSettings {
    public var formatString: String

    public init(formatString: String) {
        self.formatString = formatString
    }
}

// MARK: - Base Format String Node

public class BaseFormatStringNode: Node {

    // MARK: - Subclass contract

    /// The format string a node of this type starts with.
    public class var defaultFormatString: String { "" }

    /// Markdown shown above the format-string field in the Settings pane.
    public class var settingsGuidance: String { "" }

    /// The port one placeholder builds. Subclasses must override.
    func makePlaceholderPort(for placeholder: FormatPlaceholder) -> Port {
        fatalError("\(Self.self) must override makePlaceholderPort(for:)")
    }

    /// Called after every format-string edit, once the ports match the new
    /// parse. The node is already marked dirty — this is for whatever else the
    /// subclass derives from the format string.
    func formatStringDidChange() { }

    // MARK: - Format string

    public fileprivate(set) var formatString: String {
        didSet {
            self.updatePorts()
            self.namingDidChange()
            self.performOnMainAsync { [weak self] in self?._settingsModelStorage?.refreshFromNode() }
        }
    }

    override public var settings: (any NodeSettings)? { FormatStringSettings(formatString: self.formatString) }

    override public func apply(_ settings: any NodeSettings) {
        guard let settings = settings as? FormatStringSettings else { return }
        if settings.formatString != self.formatString { self.formatString = settings.formatString }
        super.apply(settings)
    }

    /// The current format string, parsed. Rebuilt only when it changes.
    private(set) var parsedFormatString = ParsedFormatString(tokens: [])

    override public func deriveSubtitle() -> String? { formatString }

    // MARK: - Init

    private enum CodingKeys: String, CodingKey {
        case formatString
    }

    public required init(context: Context) {
        self.formatString = Self.defaultFormatString
        self.parsedFormatString = parseFormatString(Self.defaultFormatString)
        super.init(context: context)
        self.updatePorts()
    }

    /// Procedural construction with a specific format string — the Settings-view
    /// state that shapes this node's ports, so graph building never has to go
    /// through the inspector to reach it.
    public init(context: Context, formatString: String) {
        self.formatString = formatString
        self.parsedFormatString = parseFormatString(formatString)
        super.init(context: context)
        self.updatePorts()
    }

    public convenience init(context: Context, settings: FormatStringSettings) {
        self.init(context: context, formatString: settings.formatString)
    }

    public required init(from decoder: any Decoder) throws {
        // Decoded before super.init, which declares the placeholder ports.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formatString = try container.decodeIfPresent(String.self, forKey: .formatString)
            ?? Self.defaultFormatString
        self.parsedFormatString = parseFormatString(self.formatString)

        try super.init(from: decoder)

        self.updatePorts()
    }

    // MARK: - Settings

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView {
        performOnMainSync {
            if _settingsModelStorage == nil { _settingsModelStorage = SettingsModel(node: self) }
            return AnyView(FormatStringSettingsView(model: _settingsModelStorage!, guidance: Self.settingsGuidance))
        }
    }

    @MainActor
    @Observable final class SettingsModel
    {
        var formatString: String
        {
            didSet
            {
                guard formatString != node?.formatString else { return }
                node?.setSettings(FormatStringSettings(formatString: formatString))
            }
        }
        private weak var node: BaseFormatStringNode?

        init(node: BaseFormatStringNode)
        {
            self.node = node
            self.formatString = node.formatString
        }

        func refreshFromNode()
        {
            guard let node, formatString != node.formatString else { return }
            formatString = node.formatString
        }
    }

    /// Nil until a settings view asks for it.
    private var _settingsModelStorage: SettingsModel?

    // MARK: - Placeholder ports

    /// The node's own ports, then one per placeholder on its side, in the
    /// order the format string gives them. A placeholder whose name and type
    /// are unchanged keeps its port, and so its wire and value, across an edit.
    override public func declaredPorts() -> [PortDeclaration] {
        super.declaredPorts() + self.parsedFormatString.placeholders.map { placeholder in
            PortDeclaration(key: placeholder.name, port: self.makePlaceholderPort(for: placeholder))
        }
    }

    /// A placeholder's port, typed by the specifier that built it.
    enum PlaceholderPort {
        case float(NodePort<Float>)
        case int(NodePort<Int>)
        case bool(NodePort<Bool>)
        case string(NodePort<String>)
    }

    /// One per placeholder occurrence, in format-string order: the placeholder
    /// that governs the name (its first occurrence) and the port that name owns.
    private(set) var boundOccurrences: [(placeholder: FormatPlaceholder, port: PlaceholderPort?)] = []

    override public func bindPorts() {
        super.bindPorts()
        self.boundOccurrences = self.parsedFormatString.tokens.compactMap { token in
            guard case .placeholder(let occurrence) = token else { return nil }
            let placeholder = self.parsedFormatString.placeholder(named: occurrence.name) ?? occurrence
            let name = placeholder.name
            let port: PlaceholderPort?
            switch placeholder.portType {
            case .Float: port = (findPort(named: name) as NodePort<Float>?).map(PlaceholderPort.float)
            case .Int: port = (findPort(named: name) as NodePort<Int>?).map(PlaceholderPort.int)
            case .Bool: port = (findPort(named: name) as NodePort<Bool>?).map(PlaceholderPort.bool)
            default: port = (findPort(named: name) as NodePort<String>?).map(PlaceholderPort.string)
            }
            return (placeholder, port)
        }
    }

    private func updatePorts() {
        self.parsedFormatString = parseFormatString(formatString)
        self.reconcilePorts()

        // A format edit reshapes the result even when it reshapes no port, and
        // the renderer skips a node that is not dirty.
        self.markDirty()
        self.formatStringDidChange()
    }
}
