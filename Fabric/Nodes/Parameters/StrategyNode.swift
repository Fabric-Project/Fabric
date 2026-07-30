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

    /// Standard behaviour: the node-generated `displayName` is the active strategy,
    /// e.g. "vec3" for "Vector Compose", or "Random" for "Number Generator".
    /// `NodeTitleView` renders the type name after it (yielding "vec3 Vector
    /// Compose"), so the strategy must not repeat it. An unrecognised strategy
    /// (e.g. a legacy or renamed case) falls back to the plain type name.
    ///
    /// Subclasses wanting a different title override `displayName` directly: return
    /// nil for the plain type-name title, or a bespoke string — as the type-agnostic
    /// nodes do, suppressing the token for their Virtual default.
    override public var displayName: String?
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

    var strategy: String
    {
        didSet
        {
            // One lock acquisition for the whole rebuild — see
            // Node.withStructuralMutationLockIfAttached.
            withStructuralMutationLockIfAttached {
                self.rebuildPorts(forStrategy: strategy)
            }
            // `displayName` is derived from `strategy`; notify so the title refreshes.
            self.nameSubject.send()
        }
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

    /// Designated init for programmatic construction with a specific initial strategy.
    /// Sets strategy before super.init so didSet never fires, then calls rebuildPorts exactly once.
    public init(context: Context, initialStrategy: String)
    {
        self.strategy = initialStrategy
        super.init(context: context)
        self.rebuildPorts(forStrategy: self.strategy)
    }

    /// Convenience init for compile-time-checked programmatic construction.
    public convenience init(context: Context, strategy: some NodeStrategyOption)
    {
        self.init(context: context, initialStrategy: strategy.rawValue)
    }

    override public func providesSettingsView() -> Bool { true }

    override public var settingsSize: SettingsViewSize { .Mini }

    override public func settingsView() -> AnyView
    {
        AnyView(StrategyPickerView(model: strategySettingsModel))
    }

    /// Shared settings model behind the strategy picker; composite settings
    /// views (e.g. the routing nodes') reuse it to embed StrategyPickerView.
    var strategySettingsModel: SettingsModel { _settingsModel }

    /// Subclasses: diff current dynamic ports against the wanted set for
    /// `strategy` (removePort for anything dynamic no longer wanted,
    /// addDynamicPort for anything wanted not already present) — the same
    /// name-set-diff pattern MathExpressionNode.syncPorts(to:)
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

struct StrategyPickerView: View
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
