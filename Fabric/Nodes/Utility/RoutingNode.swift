//
//  RoutingNode.swift
//  Fabric
//

import Foundation
import Satin
import SwiftUI

let routingNodeMinimumRouteCount = 2
let routingNodeMaximumRouteCount = 16

/// The settings of a routing node: the value type its routes carry, as the
/// strategy, and how many routes it has.
public struct RoutingSettings: StrategySettings
{
    public var strategy: String
    public var routeCount: Int

    public init(strategy: String, routeCount: Int)
    {
        self.strategy = strategy
        self.routeCount = routeCount
    }

    public init(portType: PortType, routeCount: Int)
    {
        self.init(strategy: portType.rawValue, routeCount: routeCount)
    }
}

/// Shared base for the routing / switching node family (Switch, Gate, Matrix
/// Switch). Owns the route count, the value-type strategy (the Type picker), the
/// settings pane, and the route port declaration. It deliberately holds no notion of
/// *how* a route is selected — subclasses supply that: a single `Index` for
/// Switch/Gate ([[RoutingNode]]), an index map for Matrix Switch.
public class RoutingNodeBase: TypeAgnosticNode
{
    /// Changed by apply(_:), through setRouteCount(_:) or setSettings(_:).
    /// Init and decode assign it before Node's initializer declares the ports.
    public private(set) var routeCount: Int = routingNodeMinimumRouteCount
    {
        didSet
        {
            guard oldValue != routeCount else { return }
            performOnMainAsync { [weak self] in self?._routeCountModelStorage?.refreshFromNode() }
        }
    }

    private enum RoutingCodingKeys: String, CodingKey
    {
        case routeCount
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    /// Takes any strategy string, as apply(_:) does, so a node built from a
    /// settings value matches a fresh node the value is applied to.
    public init(context: Context, routeCount: Int, initialStrategy: String)
    {
        self.routeCount = Self.clampedRouteCount(routeCount)
        super.init(context: context, initialStrategy: initialStrategy)
    }

    public convenience init(context: Context, routeCount: Int, portType: PortType)
    {
        self.init(context: context, routeCount: routeCount, initialStrategy: portType.rawValue)
    }

    public convenience init(context: Context, settings: RoutingSettings)
    {
        self.init(context: context, routeCount: settings.routeCount, initialStrategy: settings.strategy)
    }

    public required init(from decoder: any Decoder) throws
    {
        // Decode before super.init: the ports are declared for the saved route
        // count as Node.init(from:) makes them, so the high-index routes take
        // their saved state and the wires that name them.
        let container = try decoder.container(keyedBy: RoutingCodingKeys.self)
        routeCount = Self.clampedRouteCount(
            try container.decodeIfPresent(Int.self, forKey: .routeCount) ?? routingNodeMinimumRouteCount
        )

        try super.init(from: decoder)
    }

    override public var settings: (any NodeSettings)? { RoutingSettings(strategy: strategyName, routeCount: routeCount) }

    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? RoutingSettings else { return }
        routeCount = Self.clampedRouteCount(settings.routeCount)
        super.apply(settings)
    }

    /// Changes the route count and keeps the type.
    public func setRouteCount(_ count: Int)
    {
        setSettings(RoutingSettings(strategy: strategyName, routeCount: Self.clampedRouteCount(count)))
    }

    /// Changes the type and keeps the route count.
    public func setPortType(_ portType: PortType)
    {
        setStrategy(portType)
    }

    override public var settingsSize: SettingsViewSize { .Small }

    override public func settingsView() -> AnyView
    {
        performOnMainSync { AnyView(RoutingNodeSettingsView(node: self, model: routeCountModel)) }
    }

    @MainActor
    @Observable final class RouteCountModel
    {
        var routeCount: Int
        {
            didSet
            {
                guard routeCount != node?.routeCount else { return }
                node?.setRouteCount(routeCount)
            }
        }
        private weak var node: RoutingNodeBase?

        init(node: RoutingNodeBase)
        {
            self.node = node
            self.routeCount = node.routeCount
        }

        func refreshFromNode()
        {
            guard let node, routeCount != node.routeCount else { return }
            routeCount = node.routeCount
        }
    }

    /// Nil until a settings view asks for it.
    private var _routeCountModelStorage: RouteCountModel?

    var routeCountModel: RouteCountModel
    {
        performOnMainSync
        {
            if let model = _routeCountModelStorage { return model }
            let model = RouteCountModel(node: self)
            _routeCountModelStorage = model
            return model
        }
    }

    // MARK: - Route ports

    /// A route port, carrying the node's type.
    func routePortDeclaration(key: String, name: String, kind: PortKind, description: String) -> PortDeclaration
    {
        PortDeclaration(key: key, portType: selectedPortType, kind: kind, name: name, description: description)
    }

    static func clampedRouteCount(_ count: Int) -> Int
    {
        max(routingNodeMinimumRouteCount, min(count, routingNodeMaximumRouteCount))
    }
}

/// Single-selection routing: a scalar `Index` parameter picks one of `routeCount`
/// routes. Superclass of Switch (N inputs → 1 output) and Gate (1 input → N
/// outputs). For per-input routing to independent outputs see [[MatrixSwitchNode]].
public class RoutingNode: RoutingNodeBase
{
    public var inputIndex: ParameterPort<Int> { _inputIndex }
    private var _inputIndex: ParameterPort<Int>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputIndex = findPort(named: "inputIndex")
    }

    public required init(context: Context)
    {
        super.init(context: context)
        updateIndexRange()
    }

    public override init(context: Context, routeCount: Int, initialStrategy: String)
    {
        super.init(context: context, routeCount: routeCount, initialStrategy: initialStrategy)
        updateIndexRange()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        updateIndexRange()
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputIndex", ParameterPort(parameter: IntParameter("Index",
                                                                 0,
                                                                 0,
                                                                 routingNodeMinimumRouteCount - 1,
                                                                 .inputfield,
                                                                 "Selected route index"))),
        ]
    }

    /// The Index range follows the route count.
    public override func apply(_ settings: any NodeSettings)
    {
        super.apply(settings)
        updateIndexRange()
    }

    func selectedRouteIndex() -> Int
    {
        max(0, min(inputIndex.value ?? 0, routeCount - 1))
    }

    private func updateIndexRange()
    {
        if let parameter = inputIndex.parameter as? IntParameter
        {
            parameter.max = routeCount - 1
        }

        inputIndex.onValueChanged = { [weak self] in
            self?.updateConnectionTopology()
        }

        if let value = inputIndex.value, value >= routeCount
        {
            inputIndex.value = routeCount - 1
        }

        updateConnectionTopology()
    }
}

private struct RoutingNodeSettingsView: View
{
    let node: RoutingNodeBase
    @Bindable var model: RoutingNodeBase.RouteCountModel

    var body: some View
    {
        VStack(alignment: .leading, spacing: 12)
        {
            Text(type(of: node).nodeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Stepper(value: $model.routeCount, in: routingNodeMinimumRouteCount...routingNodeMaximumRouteCount)
            {
                Text("Routes \(model.routeCount)")
            }

            StrategyPickerView(model: node.strategySettingsModel)
        }
        .padding()
    }
}
