//
//  BaseFormatStringNode.swift
//  Fabric
//
//  Shared base for the nodes driven by a `{name:spec}` format string — String
//  Formatter, which substitutes values into it, and String Scanner, which reads
//  values back out. Everything the two share lives here: the format string and
//  its serialization, the Settings pane, and the dynamic ports the placeholders
//  build. A subclass says what a placeholder's port looks like and what to do
//  once the ports have been rebuilt; the rest is not its business.
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

// MARK: - Base Format String Node

public class BaseFormatStringNode: Node {

    // MARK: - Subclass contract

    /// The format string a node of this type starts with.
    public class var defaultFormatString: String { "" }

    /// Which side of the node the placeholders build their ports on: inlets for
    /// a node reading values in, outlets for one handing values out.
    public class var placeholderPortKind: PortKind { .Inlet }

    /// Ports on that side the format string does not own, so the placeholder
    /// diff leaves them alone.
    public class var staticPortNames: Set<String> { [] }

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
            self.subtitleSubject.send()
        }
    }

    /// Sets the format string from outside the Settings view — the procedural
    /// equivalent of typing in the inspector.
    public func setFormatString(_ formatString: String) {
        guard formatString != self.formatString else { return }
        self.formatString = formatString
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
        super.init(context: context)
        self.updatePorts()
    }

    /// Procedural construction with a specific format string — the Settings-view
    /// state that shapes this node's ports, so graph building never has to go
    /// through the inspector to reach it.
    public init(context: Context, formatString: String) {
        self.formatString = formatString
        super.init(context: context)
        self.updatePorts()
    }

    public required init(from decoder: any Decoder) throws {
        self.formatString = Self.defaultFormatString

        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Assigning runs didSet, which rebuilds the ports against the restored
        // format string; the decoded ports it matches by name and type are kept,
        // UUIDs and all, so the graph's connection restore still finds them.
        self.formatString = try container.decodeIfPresent(String.self, forKey: .formatString)
            ?? Self.defaultFormatString
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.formatString, forKey: .formatString)
    }

    // MARK: - Settings

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView {
        AnyView(FormatStringSettingsView(model: _settingsModel, guidance: Self.settingsGuidance))
    }

    @Observable final class SettingsModel
    {
        var formatString: String
        {
            didSet
            {
                guard formatString != node?.formatString else { return }
                node?.formatString = formatString
            }
        }
        private weak var node: BaseFormatStringNode?

        init(node: BaseFormatStringNode)
        {
            self.node = node
            self.formatString = node.formatString
        }
    }

    private lazy var _settingsModel = SettingsModel(node: self)

    // MARK: - Dynamic Port Management

    /// Diffs the ports the placeholders ask for against the ones already there:
    /// a name that has gone, or that has changed type, loses its port; a name
    /// with no port gets one. A placeholder whose name and type are unchanged
    /// keeps its port, and so keeps its wire and its value, across an edit.
    private func updatePorts() {
        let newParse = parseFormatString(formatString)
        let newNames = Set(newParse.placeholders.map(\.name))

        let existingNames = Set(
            self.ports
                .filter { $0.kind == Self.placeholderPortKind && !Self.staticPortNames.contains($0.name) }
                .map(\.name)
        )

        for portName in existingNames.subtracting(newNames) {
            if let port: Port = self.findPort(named: portName) {
                self.removePort(port)
            }
        }

        for placeholder in newParse.placeholders {
            if let existingPort: Port = self.findPort(named: placeholder.name),
               existingPort.portType != placeholder.portType {
                self.removePort(existingPort)
            }
        }

        for placeholder in newParse.placeholders
        where (self.findPort(named: placeholder.name) as Port?) == nil {
            self.addDynamicPort(self.makePlaceholderPort(for: placeholder), name: placeholder.name)
        }

        self.parsedFormatString = newParse

        // A format edit reshapes the result even when it reshapes no port, and
        // the renderer skips a node that is not dirty.
        self.markDirty()
        self.formatStringDidChange()
    }
}
