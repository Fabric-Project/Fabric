//
//  StrategyNode.swift
//  Fabric
//
//  Shared base for nodes that build their port set from a user-chosen
//  strategy (e.g. "Euler" vs "Axis Angle" vs "Target") rather than a fixed
//  shape. The strategy lives in the Settings view, not on a port: anything
//  that reshapes a node's ports must only be reachable via explicit user
//  interaction in the inspector, never via graph wiring/automation, since a
//  runtime-driven strategy switch would churn ports and silently disconnect
//  wires on every change. This is the same lifecycle MathExpressionBaseNode
//  already uses for its (also non-port) stringExpression property.
//

import Foundation
import Satin
import Metal
import SwiftUI

public class StrategyNode: Node
{
    /// Ordered strategy names, shown in the Settings view picker.
    public class var strategies: [String] { [] }
    public class var defaultStrategy: String { strategies.first ?? "" }

    /// When true, the picker inserts a visual separator after the first strategy in the list.
    public class var separatorAfterFirstStrategy: Bool { false }

    var strategy: String
    {
        didSet { self.rebuildPorts(forStrategy: strategy) }
    }

    private enum StrategyCodingKeys: String, CodingKey
    {
        case strategy
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: StrategyCodingKeys.self)
        let decoded = try container.decodeIfPresent(String.self, forKey: .strategy)

        // Initializing assignment — didSet does not fire here, matching the
        // plain-creation path (ports are (re)built by rebuildPorts below).
        self.strategy = decoded ?? Self.defaultStrategy

        try super.init(from: decoder)

        // Rebuild from the restored strategy, evicting any dynamic port left
        // over from whatever strategy the document was saved in.
        self.rebuildPorts(forStrategy: self.strategy)
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: StrategyCodingKeys.self)
        try container.encode(self.strategy, forKey: .strategy)
    }

    public required init(context: Context)
    {
        self.strategy = Self.defaultStrategy
        super.init(context: context)
        self.rebuildPorts(forStrategy: self.strategy)
    }

    override public func providesSettingsView() -> Bool { true }

    override public var settingsSize: SettingsViewSize { .Mini }

    override public func settingsView() -> AnyView
    {
        AnyView(StrategyPickerView(model: _settingsModel))
    }

    /// Subclasses: diff current dynamic ports against the wanted set for
    /// `strategy` (removePort for anything dynamic no longer wanted,
    /// addDynamicPort for anything wanted not already present) — the same
    /// name-set-diff pattern MathExpressionBaseNode.registerPorts(forEvaluator:)
    /// already uses. Called on creation, on every Settings-view strategy
    /// change, and once after decode.
    public func rebuildPorts(forStrategy strategy: String) { }

    // MARK: - Settings Model

    @Observable final class SettingsModel
    {
        let strategies: [String]
        let separatorAfterFirst: Bool
        var strategy: String
        {
            didSet
            {
                guard strategy != node?.strategy else { return }
                node?.strategy = strategy
            }
        }
        private weak var node: StrategyNode?

        init(node: StrategyNode)
        {
            self.node = node
            self.strategies = type(of: node).strategies
            self.separatorAfterFirst = type(of: node).separatorAfterFirstStrategy
            self.strategy = node.strategy
        }
    }

    private lazy var _settingsModel = SettingsModel(node: self)
}

private struct StrategyPickerView: View
{
    @Bindable var model: StrategyNode.SettingsModel

    var body: some View
    {
        Picker("Type", selection: $model.strategy)
        {
            if model.separatorAfterFirst, let first = model.strategies.first
            {
                Text(first).tag(first)
                Divider()
                ForEach(model.strategies.dropFirst(), id: \.self) { Text($0).tag($0) }
            }
            else
            {
                ForEach(model.strategies, id: \.self) { Text($0).tag($0) }
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
    }
}
