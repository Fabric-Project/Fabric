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
    /// Changed by apply(_:), through Graph.setSettings or setRouteCount(_:).
    /// Init and decode assign it before Node's initializer declares the
    /// ports.
    public private(set) var routeCount: Int = routingNodeMinimumRouteCount

    private enum RoutingCodingKeys: String, CodingKey
    {
        case routeCount
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    public init(context: Context, routeCount: Int, portType: PortType)
    {
        self.routeCount = Self.clampedRouteCount(routeCount)
        super.init(context: context, initialStrategy: portType.rawValue)
    }

    public convenience init(context: Context, settings: RoutingSettings)
    {
        self.init(context: context, routeCount: settings.routeCount, portType: PortType(rawValue: settings.strategy) ?? .Virtual)
    }

    public required init(from decoder: any Decoder) throws
    {
        // Decode before super.init: the ports are declared for the saved route
        // count as Node.init(from:) hydrates them, so the high-index routes
        // take their saved ids and the wires that name them.
        let container = try decoder.container(keyedBy: RoutingCodingKeys.self)
        routeCount = Self.clampedRouteCount(
            try container.decodeIfPresent(Int.self, forKey: .routeCount) ?? routingNodeMinimumRouteCount
        )

        try super.init(from: decoder)
    }

    override public var settings: (any NodeSettings)? { RoutingSettings(strategy: strategy, routeCount: routeCount) }

    /// Sets the route count; StrategyNode sets the strategy, and the ports
    /// are reconciled once for both.
    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? RoutingSettings else { return }
        routeCount = Self.clampedRouteCount(settings.routeCount)
        super.apply(settings)
    }

    /// Changes the route count as an edit, the type as it is.
    public func setRouteCount(_ count: Int)
    {
        commitSettings(RoutingSettings(strategy: strategy, routeCount: Self.clampedRouteCount(count)))
    }

    /// Changes the type as an edit, the route count as it is.
    public func setPortType(_ portType: PortType)
    {
        setStrategy(portType.rawValue)
    }

    override public var settingsSize: SettingsViewSize { .Small }

    override public func settingsView() -> AnyView
    {
        AnyView(RoutingNodeSettingsView(node: self))
    }

    // MARK: - Route ports

    /// A route port, carrying the node's type.
    func routePortDeclaration(registryKey: String, name: String, kind: PortKind, description: String) -> PortDeclaration
    {
        PortDeclaration(registryKey: registryKey, portType: selectedPortType, kind: kind, name: name, description: description)
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
    public var inputIndex: ParameterPort<Int> { port(named: "inputIndex") }

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

    public override func didApplyStrategy()
    {
        super.didApplyStrategy()
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
    @State private var draft: NodeSettingsDraft<RoutingSettings>

    init(node: RoutingNodeBase)
    {
        self.node = node
        let settings = RoutingSettings(strategy: node.strategy, routeCount: node.routeCount)
        self._draft = State(initialValue: NodeSettingsDraft(of: settings, on: node, commit: .eachChange))
    }

    var body: some View
    {
        VStack(alignment: .leading, spacing: 12)
        {
            Text(type(of: node).nodeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Stepper(value: $draft.value.routeCount, in: routingNodeMinimumRouteCount...routingNodeMaximumRouteCount)
            {
                Text("Routes \(draft.value.routeCount)")
            }

            StrategyPicker(strategies: type(of: node).strategies,
                           separatorAfterFirst: type(of: node).separatorAfterFirstStrategy,
                           selection: $draft.value.strategy)
        }
        .padding()
    }
}
