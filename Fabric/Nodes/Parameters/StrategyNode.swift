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

/// Open so plugins can define strategy nodes: subclass, override `strategyOptions`, and
/// declare the ports for `strategy` in `declaredPorts()`.
open class StrategyNode: Node
{
    /// Ordered strategy options — the single source of truth for the picker and
    /// for programmatic construction.  Subclasses override this; never override
    /// `strategies` directly.
    open class var strategyOptions: [any NodeStrategyOption] { [] }

    /// Derived from strategyOptions — do not override.
    public class var strategies: [String] { strategyOptions.map(\.rawValue) }
    open class var defaultStrategy: (any NodeStrategyOption)? { strategyOptions.first }

    /// When true, the picker inserts a visual separator after the first strategy in the list.
    open class var separatorAfterFirstStrategy: Bool { false }

    /// Standard behaviour: the node-generated `subtitle` is the active strategy,
    /// e.g. "vec3" for "Vector Compose", or "Random" for "Number Generator".
    /// `NodeTitleView` renders the type name after it (yielding "vec3 Vector
    /// Compose"), so the strategy must not repeat it. An unrecognised strategy
    /// (e.g. a legacy or renamed case) falls back to the plain type name.
    ///
    /// Subclasses wanting a different title override `deriveSubtitle()` directly:
    /// return nil for the plain type-name title, or a bespoke string — as the
    /// type-agnostic nodes do, suppressing the token for their Virtual default.
    override open func deriveSubtitle() -> String?
    {
        strategy?.rawValue
    }

    /// The option named `name`, or nil when none matches (e.g. a removed or renamed case).
    /// Names are the saved and settings form of a strategy; everything else is typed.
    public class func strategyOption(named name: String) -> (any NodeStrategyOption)?
    {
        strategyOptions.first { $0.rawValue == name }
    }

    /// The current strategy as `T`, or nil when it is another type or unset.
    public func strategyOption<T: NodeStrategyOption>(as _: T.Type = T.self) -> T?
    {
        strategy as? T
    }

    /// The selected strategy, always one of `strategyOptions`, resolved from `strategyName`
    /// whenever that changes; nil when the name matches none, such as a removed case in a
    /// saved document. Subclasses switch on this, never on the name.
    public private(set) var strategy: (any NodeStrategyOption)?

    /// The strategy's name: what settings, documents and the picker hold. A name that matches
    /// no option is kept, so saving writes it back unchanged.
    /// Changed by apply(_:), through setStrategy(_:) or setSettings(_:).
    public private(set) var strategyName: String
    {
        didSet { strategy = Self.strategyOption(named: strategyName) }
    }

    private enum StrategyCodingKeys: String, CodingKey
    {
        case strategy
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: StrategyCodingKeys.self)
        let decoded = try container.decodeIfPresent(String.self, forKey: .strategy)

        // Stored directly: didSet does not run in an initializer, so the typed strategy is set too.
        let name = decoded ?? Self.defaultStrategy?.rawValue ?? ""
        self.strategyName = name
        self.strategy = Self.strategyOption(named: name)

        // Set before super.init, so Node's initializer declares the ports for the saved strategy.
        try super.init(from: decoder)
    }

    override open var settings: (any NodeSettings)? { StrategyNodeSettings(strategy: self.strategyName) }

    override open func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? any StrategySettings,
              let current = self.settings,
              type(of: current) == type(of: settings)
        else { return }
        let changed = settings.strategy != self.strategyName
        self.strategyName = settings.strategy
        if changed, let graph
        {
            // A retyped port keeps its connections that fit, so the reconcile
            // registers nothing of its own; recordSettingsChange records the
            // strategy step. A removed port's disconnects go unrecorded.
            graph.withoutUndoRegistration {
                self.reconcilePorts()
            }
        }
        else
        {
            self.reconcilePorts()
        }
        super.apply(settings)
        guard changed else { return }
        // `subtitle` is derived from `strategy`; notify so the title refreshes.
        self.namingDidChange()
        self.settingsDidChange()
    }

    /// A change of strategy in a graph is an undo step that puts back the
    /// strategy and nothing else in the settings. See Node.recordSettingsChange(from:).
    override open func recordSettingsChange(from previous: any NodeSettings)
    {
        guard let graph,
              let previous = previous as? any StrategySettings,
              previous.strategy != self.strategyName
        else { return }

        let previousStrategy = previous.strategy
        graph.undoManager?.registerUndo(withTarget: self) { node in
            node.setStrategy(previousStrategy)
        }
        graph.undoManager?.setActionName("Change Node Strategy")
    }

    /// Changes the strategy and keeps the rest of the node's settings. The
    /// strategy picker writes through this, as does a node specialising from
    /// execute().
    public func setStrategy(_ strategy: String)
    {
        guard var settings = self.settings as? any StrategySettings else { return }
        guard settings.strategy != strategy else { return }
        settings.strategy = strategy
        self.setSettings(settings)
    }

    /// Resolves by name, so a value of another type that names one of this node's options, such
    /// as `PortType.Vector3` for `VectorType.float3`, selects that option.
    public func setStrategy(_ strategy: any NodeStrategyOption)
    {
        self.setStrategy(strategy.rawValue)
    }

    public required init(context: Context)
    {
        // Resolved by name, as every other entry point resolves it.
        let name = Self.defaultStrategy?.rawValue ?? ""
        self.strategyName = name
        self.strategy = Self.strategyOption(named: name)
        super.init(context: context)
    }

    /// Designated init for programmatic construction with a strategy given by name, as settings hold
    /// it. Set before super.init, so Node's initializer declares the ports for it.
    public init(context: Context, initialStrategy: String)
    {
        self.strategyName = initialStrategy
        self.strategy = Self.strategyOption(named: initialStrategy)
        super.init(context: context)
    }

    /// Convenience init for compile-time-checked programmatic construction. Resolves by name, as
    /// setStrategy(_:) does.
    public convenience init(context: Context, strategy: any NodeStrategyOption)
    {
        self.init(context: context, initialStrategy: strategy.rawValue)
    }

    public convenience init(context: Context, settings: StrategyNodeSettings)
    {
        self.init(context: context, initialStrategy: settings.strategy)
    }

    override open func providesSettingsView() -> Bool { true }

    override open var settingsSize: SettingsViewSize { .Mini }

    override open func settingsView() -> AnyView
    {
        AnyView(StrategyPickerView(model: strategySettingsModel))
    }

    /// Shared settings model behind the strategy picker; composite settings
    /// views (e.g. the routing nodes') reuse it to embed StrategyPickerView.
    public var strategySettingsModel: SettingsModel
    {
        performOnMainSync
        {
            if let model = _settingsModelStorage { return model }
            let model = SettingsModel(node: self)
            _settingsModelStorage = model
            return model
        }
    }

    // MARK: - Settings Model

    @MainActor
    @Observable public final class SettingsModel
    {
        let strategies: [String]
        let separatorAfterFirst: Bool
        var strategy: String
        {
            didSet
            {
                guard strategy != node?.strategyName else { return }
                node?.setStrategy(strategy)
            }
        }
        private weak var node: StrategyNode?

        init(node: StrategyNode)
        {
            self.node = node
            self.strategies = type(of: node).strategies
            self.separatorAfterFirst = type(of: node).separatorAfterFirstStrategy
            self.strategy = node.strategyName
        }

        func refreshFromNode()
        {
            guard let node, strategy != node.strategyName else { return }
            strategy = node.strategyName
        }
    }

    /// Nil until a settings view asks for it.
    private var _settingsModelStorage: SettingsModel?

    override open func refreshSettingsModel()
    {
        super.refreshSettingsModel()
        _settingsModelStorage?.refreshFromNode()
    }
}

public struct StrategyPickerView: View
{
    @Bindable var model: StrategyNode.SettingsModel

    public init(model: StrategyNode.SettingsModel)
    {
        self.model = model
    }

    public var body: some View
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

/// A strategy picker followed by usage guidance for the currently-selected
/// strategy. Reusable by any StrategyNode whose modes benefit from an
/// explanatory blurb; `guidance` maps a strategy raw value to its description.
public struct StrategyGuidanceView: View
{
    @Bindable var model: StrategyNode.SettingsModel
    let guidance: (String) -> String

    public init(model: StrategyNode.SettingsModel, guidance: @escaping (String) -> String)
    {
        self.model = model
        self.guidance = guidance
    }

    public var body: some View
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
