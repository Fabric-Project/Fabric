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
//  wires on every change. This is the same lifecycle MathExpressionNode
//  already uses for its (also non-port) stringExpression property.
//

import Foundation
import Satin
import Metal
import SwiftUI
import Combine

// MARK: - NodeStrategyOption

/// Any enum or type whose rawValue String identifies a StrategyNode strategy.
/// Conforming types serve as compile-time-checked strategy parameters for
/// programmatic node construction, replacing raw String literals.
public protocol NodeStrategyOption {
    var rawValue: String { get }
}

// MARK: - Shared family enums

/// Transform composition/decomposition mode: Translation-Rotation-Scale or
/// raw column vectors.  Shared by ComposeTransformNode, DecomposeTransformNode,
/// ComposeTransformArrayNode, and DecomposeTransformArrayNode.
public enum TransformCompositionMode: String, NodeStrategyOption, CaseIterable {
    case trs     = "TRS"
    case columns = "Columns"
}

/// Orientation composition mode: Euler angles, Axis + Angle, or aim-at-Target.
/// Shared by ComposeOrientationNode and ComposeOrientationArrayNode.
public enum OrientationCompositionMode: String, NodeStrategyOption, CaseIterable {
    case euler     = "Euler"
    case axisAngle = "Axis Angle"
    case target    = "Target"
}

/// Orientation decomposition mode.
/// Shared by DecomposeOrientationNode and DecomposeOrientationArrayNode.
public enum OrientationDecompositionMode: String, NodeStrategyOption, CaseIterable {
    case toEuler     = "To Euler"
    case toAxisAngle = "To Axis Angle"
}

/// Geometry-to-transform extraction mode.
/// Used by GeometryToTransformArrayNode.
public enum GeometryToTransformMode: String, NodeStrategyOption, CaseIterable {
    case transform  = "Transform"
    case components = "Components"
}

/// Vector type for consolidated Compose/Decompose vector nodes (single and array).
/// Raw values delegate to PortType so serialised strategy strings never drift.
public enum VectorType: NodeStrategyOption, CaseIterable {
    case float2, float3, float4

    public var rawValue: String {
        switch self {
        case .float2: return PortType.Vector2.rawValue
        case .float3: return PortType.Vector3.rawValue
        case .float4: return PortType.Vector4.rawValue
        }
    }

    /// Convenience back-conversion for execute dispatch.
    public var portType: PortType {
        switch self {
        case .float2: return .Vector2
        case .float3: return .Vector3
        case .float4: return .Vector4
        }
    }

    /// Component labels and count for this vector type.
    public var componentLabels: [String] {
        switch self {
        case .float2: return ["X", "Y"]
        case .float3: return ["X", "Y", "Z"]
        case .float4: return ["X", "Y", "Z", "W"]
        }
    }
}

// MARK: - Settings

/// The settings of a StrategyNode and of every subclass, which carry the
/// strategy whatever else they hold: the base class reads and writes its part
/// without knowing the leaf's type.
public protocol StrategySettings: NodeSettings
{
    var strategy: String { get set }
}

/// The settings of a StrategyNode with nothing to set but its strategy.
public struct StrategyNodeSettings: StrategySettings
{
    public var strategy: String

    public init(strategy: String)
    {
        self.strategy = strategy
    }

    public init(strategy: some NodeStrategyOption)
    {
        self.strategy = strategy.rawValue
    }
}

// MARK: - StrategyNode

public class StrategyNode: Node
{
    /// Ordered strategy options — the single source of truth for the picker and
    /// for programmatic construction.  Subclasses override this; never override
    /// `strategies` directly.
    public class var strategyOptions: [any NodeStrategyOption] { [] }

    /// Derived from strategyOptions — do not override.
    public class var strategies: [String] { strategyOptions.map(\.rawValue) }
    public class var defaultStrategy: String { strategies.first ?? "" }

    /// When true, the picker inserts a visual separator after the first strategy in the list.
    public class var separatorAfterFirstStrategy: Bool { false }

    /// Standard behaviour: the node-generated `subtitle` is the active strategy,
    /// e.g. "vec3" for "Vector Compose", or "Random" for "Number Generator".
    /// `NodeTitleView` renders the type name after it (yielding "vec3 Vector
    /// Compose"), so the strategy must not repeat it. An unrecognised strategy
    /// (e.g. a legacy or renamed case) falls back to the plain type name.
    ///
    /// Subclasses wanting a different title override `deriveSubtitle()` directly:
    /// return nil for the plain type-name title, or a bespoke string — as the
    /// type-agnostic nodes do, suppressing the token for their Virtual default.
    override public func deriveSubtitle() -> String?
    {
        Self.strategies.contains(strategy) ? strategy : nil
    }

    /// A strategy string resolved to its typed option, or nil when it matches
    /// none (e.g. a removed or renamed case).
    public class func strategyOption<T: NodeStrategyOption>(matching rawValue: String, as _: T.Type = T.self) -> T?
    {
        strategyOptions.first { $0.rawValue == rawValue } as? T
    }

    /// The currently selected strategy resolved to its typed option.
    public func strategyOption<T: NodeStrategyOption>(as _: T.Type = T.self) -> T?
    {
        Self.strategyOption(matching: strategy)
    }

    /// Changed by apply(_:), through setStrategy(_:) or Graph.setSettings.
    private(set) var strategy: String

    private enum StrategyCodingKeys: String, CodingKey
    {
        case strategy
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: StrategyCodingKeys.self)
        let decoded = try container.decodeIfPresent(String.self, forKey: .strategy)

        self.strategy = decoded ?? Self.defaultStrategy

        try super.init(from: decoder)
        self.didApplyStrategy()
    }

    override public var settings: (any NodeSettings)? { StrategyNodeSettings(strategy: self.strategy) }

    /// Sets the strategy; the base reconciles the ports once, for whatever
    /// else a subclass's settings decide as well.
    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? any StrategySettings else { return }
        let changed = settings.strategy != self.strategy
        self.strategy = settings.strategy
        super.apply(settings)
        self.didApplyStrategy()
        if changed { self.subtitleSubject.send() }
    }

    /// Changes the strategy as an edit, the rest of the node's settings as
    /// they are: the strategy picker's write, and a wire's as it specialises
    /// the node.
    public func setStrategy(_ strategy: String)
    {
        guard var settings = self.settings as? any StrategySettings, settings.strategy != strategy else { return }
        settings.strategy = strategy
        self.commitSettings(settings)
    }

    public func setStrategy(_ strategy: some NodeStrategyOption)
    {
        self.setStrategy(strategy.rawValue)
    }

    public required init(context: Context)
    {
        self.strategy = Self.defaultStrategy
        super.init(context: context)
        self.didApplyStrategy()
    }

    /// Designated init for programmatic construction with a specific initial strategy.
    public init(context: Context, initialStrategy: String)
    {
        self.strategy = initialStrategy
        super.init(context: context)
        self.didApplyStrategy()
    }

    /// Convenience init for compile-time-checked programmatic construction.
    public convenience init(context: Context, strategy: some NodeStrategyOption)
    {
        self.init(context: context, initialStrategy: strategy.rawValue)
    }

    public convenience init(context: Context, settings: StrategyNodeSettings)
    {
        self.init(context: context, initialStrategy: settings.strategy)
    }

    override public func providesSettingsView() -> Bool { true }

    override public var settingsSize: SettingsViewSize { .Mini }

    override public func settingsView() -> AnyView
    {
        AnyView(StrategyPickerView(model: strategySettingsModel))
    }

    /// The model behind the strategy picker.
    var strategySettingsModel: SettingsModel { _settingsModel }

    /// Runs once the ports stand for the strategy: after init, decode and
    /// every apply. For a subclass's state that follows the strategy, as a
    /// held value resets when the type it holds changes. Ports come from
    /// declaredPorts(), which a subclass computes from `strategy`.
    public func didApplyStrategy() { }

    // MARK: - Settings Model

    /// The strategy picker commits each choice, and follows the node's
    /// strategy as undo and redo change it.
    @MainActor
    @Observable final class SettingsModel
    {
        let strategies: [String]
        let separatorAfterFirst: Bool
        var strategy: String
        {
            didSet
            {
                guard !isTakingNodeValue, strategy != oldValue else { return }
                node?.setStrategy(strategy)
            }
        }
        @ObservationIgnored private weak var node: StrategyNode?
        @ObservationIgnored private var subscription: AnyCancellable?
        @ObservationIgnored private var isTakingNodeValue = false

        init(node: StrategyNode)
        {
            self.node = node
            self.strategies = type(of: node).strategies
            self.separatorAfterFirst = type(of: node).separatorAfterFirstStrategy
            self.strategy = node.strategy
            self.subscription = node.settingsChangedSubject.sink { [weak self] in self?.takeNodeValue() }
        }

        private func takeNodeValue()
        {
            guard let strategy = node?.strategy, strategy != self.strategy else { return }
            isTakingNodeValue = true
            self.strategy = strategy
            isTakingNodeValue = false
        }
    }

    // Made for the settings view, on the main thread.
    private lazy var _settingsModel: SettingsModel = MainActor.assumeIsolated { SettingsModel(node: self) }
}

struct StrategyPickerView: View
{
    @Bindable var model: StrategyNode.SettingsModel

    var body: some View
    {
        StrategyPicker(strategies: model.strategies,
                       separatorAfterFirst: model.separatorAfterFirst,
                       selection: $model.strategy)
    }
}

/// The strategy menu, choosing into `selection`.
struct StrategyPicker: View
{
    let strategies: [String]
    let separatorAfterFirst: Bool
    @Binding var selection: String

    var body: some View
    {
        Picker("Type", selection: $selection)
        {
            if separatorAfterFirst, let first = strategies.first
            {
                Text(first).tag(first)
                Divider()
                ForEach(strategies.dropFirst(), id: \.self) { Text($0).tag($0) }
            }
            else
            {
                ForEach(strategies, id: \.self) { Text($0).tag($0) }
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
    }
}

/// A strategy picker followed by usage guidance for the currently-selected
/// strategy. Reusable by any StrategyNode whose modes benefit from an
/// explanatory blurb; `guidance` maps a strategy raw value to its description.
struct StrategyGuidanceView: View
{
    @Bindable var model: StrategyNode.SettingsModel
    let guidance: (String) -> String

    var body: some View
    {
        VStack(alignment: .leading)
        {
            StrategyPickerView(model: model)

            Text(guidance(model.strategy))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
