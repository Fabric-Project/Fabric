//
//  RoutingNode.swift
//  Fabric
//

import Foundation
import Satin
import SwiftUI

let routingNodeMinimumRouteCount = 2
let routingNodeMaximumRouteCount = 16

/// Shared base for the routing / switching node family (Switch, Gate, Matrix
/// Switch). Owns the route count, the value-type strategy (the Type picker), the
/// settings pane, and the dynamic-port helpers. It deliberately holds no notion of
/// *how* a route is selected — subclasses supply that: a single `Index` for
/// Switch/Gate ([[RoutingNode]]), an index map for Matrix Switch.
public class RoutingNodeBase: TypeAgnosticNode
{
    public var routeCount: Int = routingNodeMinimumRouteCount
    {
        didSet
        {
            let clamped = Self.clampedRouteCount(routeCount)
            if routeCount != clamped
            {
                routeCount = clamped
                return
            }

            rebuildPorts(forStrategy: strategy)
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

    public init(context: Context, routeCount: Int, portType: PortType)
    {
        self.routeCount = Self.clampedRouteCount(routeCount)
        super.init(context: context, initialStrategy: portType.rawValue)
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: RoutingCodingKeys.self)
        routeCount = Self.clampedRouteCount(
            try container.decodeIfPresent(Int.self, forKey: .routeCount) ?? routingNodeMinimumRouteCount
        )
        rebuildPorts(forStrategy: strategy)
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: RoutingCodingKeys.self)
        try container.encode(routeCount, forKey: .routeCount)
    }

    public func setRouteCount(_ count: Int)
    {
        let clamped = Self.clampedRouteCount(count)
        guard clamped != routeCount else { return }
        routeCount = clamped
    }

    public func setPortType(_ portType: PortType)
    {
        let rawValue = portType.rawValue
        guard rawValue != strategy else { return }
        strategy = rawValue
    }

    /// Route selection reads runtime values (Index / map), so the active-input
    /// set can change without a topology change and must not be cached.
    override public var activeInputPortsDependOnValues: Bool { true }

    override public var settingsSize: SettingsViewSize { .Small }

    override public func settingsView() -> AnyView
    {
        AnyView(RoutingNodeSettingsView(node: self))
    }

    // MARK: - Dynamic routing-port helpers

    func addOrReplaceRoutingPort(name registryName: String,
                                 displayName: String,
                                 portType: PortType,
                                 kind: PortKind,
                                 description: String)
    {
        addOrReplaceDynamicPortPreservingIdentity(name: registryName,
                                                  displayName: displayName,
                                                  portType: portType,
                                                  kind: kind,
                                                  description: description)
    }

    func removeRoutingPorts(matching shouldRemove: (String) -> Bool)
    {
        for port in ports where shouldRemove(port.name)
        {
            removePort(port)
        }
    }

    func applyPortOrder(_ registryNames: [String])
    {
        let reordered: [Port] = registryNames.compactMap { name in
            let port: Port? = findPort(named: name)
            return port
        }

        if reordered.count == ports.count
        {
            reorderPorts(reordered)
        }
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

    public required init(context: Context)
    {
        super.init(context: context)
        updateIndexRange()
    }

    public override init(context: Context, routeCount: Int, portType: PortType)
    {
        super.init(context: context, routeCount: routeCount, portType: portType)
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

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
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

        if let value = inputIndex.value, value >= routeCount
        {
            inputIndex.value = routeCount - 1
        }
    }
}

private struct RoutingNodeSettingsView: View
{
    let node: RoutingNodeBase
    @State private var routeCount: Int
    @State private var portTypeRawValue: String

    init(node: RoutingNodeBase)
    {
        self.node = node
        self._routeCount = State(initialValue: node.routeCount)
        self._portTypeRawValue = State(initialValue: node.selectedPortType.rawValue)
    }

    var body: some View
    {
        VStack(alignment: .leading, spacing: 12)
        {
            Text(type(of: node).nodeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Stepper(value: Binding(
                get: { routeCount },
                set: { newRouteCount in
                    node.setRouteCount(newRouteCount)
                    routeCount = node.routeCount
                }
            ), in: routingNodeMinimumRouteCount...routingNodeMaximumRouteCount)
            {
                Text("Routes \(routeCount)")
            }

            Picker("Type", selection: Binding(
                get: { portTypeRawValue },
                set: { rawValue in
                    guard let portType = PortType(rawValue: rawValue) else { return }
                    node.setPortType(portType)
                    portTypeRawValue = node.selectedPortType.rawValue
                }
            ))
            {
                if let first = type(of: node).strategies.first
                {
                    Text(first).tag(first)
                    Divider()
                    ForEach(type(of: node).strategies.dropFirst(), id: \.self) { strategy in
                        Text(strategy).tag(strategy)
                    }
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
        .padding()
    }
}
