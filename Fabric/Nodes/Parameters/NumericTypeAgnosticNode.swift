//
//  NumericTypeAgnosticNode.swift
//  Fabric
//

import Foundation
import Satin
import simd

public enum NumericPortStrategy: NodeStrategyOption, Equatable
{
    case virtual
    case concrete(PortType)

    public var rawValue: String
    {
        switch self
        {
        case .virtual: return "Virtual"
        case .concrete(let portType): return portType.rawValue
        }
    }

    public var portType: PortType
    {
        switch self
        {
        case .virtual: return .NumericVirtual
        case .concrete(let portType): return portType
        }
    }
}

public class NumericTypeAgnosticNode: StrategyNode
{
    public class var supportedPortTypes: [PortType] { [] }

    public override class var strategyOptions: [any NodeStrategyOption]
    {
        [NumericPortStrategy.virtual] + supportedPortTypes.map { NumericPortStrategy.concrete($0) }
    }

    public override class var separatorAfterFirstStrategy: Bool { true }

    public var selectedNumericPortType: PortType
    {
        Self.portType(forStrategy: strategy)
    }

    public convenience init(context: Context, portType: PortType)
    {
        self.init(context: context, initialStrategy: portType.rawValue)
    }

    /// Node-generated name: the selected numeric port type leads the title, e.g.
    /// "Float Tween" (NodeTitleView appends the type name after it). NumericVirtual
    /// — the no-configuration default — suppresses the token so the node reads as
    /// its plain type name.
    override public var displayName: String? {
        let portType = selectedNumericPortType
        return portType == .NumericVirtual ? nil : portType.rawValue
    }

    public class func portType(forStrategy strategy: String) -> PortType
    {
        if strategy == NumericPortStrategy.virtual.rawValue { return .NumericVirtual }
        return supportedPortTypes.first(where: { $0.rawValue == strategy }) ?? .NumericVirtual
    }

    public func concretePortType(from port: Port?) -> PortType?
    {
        guard let port else { return nil }
        let portType = port.portType
        if portType == .NumericVirtual,
           let boxed = port.snapshotValue(),
           let boxedType = boxed.numericPortType,
           Self.supportedPortTypes.contains(boxedType)
        {
            return boxedType
        }
        if Self.supportedPortTypes.contains(portType)
        {
            return portType
        }
        if case .Array(let elementType) = portType,
           Self.supportedPortTypes.contains(portType) || Self.supportedPortTypes.contains(elementType)
        {
            return portType
        }
        return nil
    }

    @discardableResult
    public func specializeFromConnectedPort(named portName: String) -> Bool
    {
        guard selectedNumericPortType == .NumericVirtual,
              let port: Port = findPort(named: portName),
              let connectedType = port.connectedPorts.first?.portType,
              Self.supportedPortTypes.contains(connectedType)
        else { return false }

        strategy = connectedType.rawValue
        return true
    }

    public func addOrReplaceDynamicPort(name registryName: String,
                                        displayName: String,
                                        portType: PortType,
                                        kind: PortKind,
                                        description: String,
                                        editable: Bool = false)
    {
        if let existing: Port = findPort(named: registryName), existing.portType != portType
        {
            let oldConnections = existing.connectedPorts
            removePort(existing)
            let replacement = Self.makeFreshPort(
                portType: portType,
                name: displayName,
                kind: kind,
                description: description,
                editable: editable
            )
            addDynamicPort(replacement, name: registryName)
            for connected in oldConnections where replacement.canConnect(to: connected)
            {
                replacement.connect(to: connected)
            }
        }

        if findPort(named: registryName) == nil
        {
            addDynamicPort(
                Self.makeFreshPort(
                    portType: portType,
                    name: displayName,
                    kind: kind,
                    description: description,
                    editable: editable
                ),
                name: registryName
            )
        }
    }

    public func reorderPorts(named names: [String])
    {
        let reordered: [Port] = names.compactMap { name in let p: Port? = findPort(named: name); return p }
        if reordered.count == self.ports.count { reorderPorts(reordered) }
    }

    private static func makeFreshPort(portType: PortType,
                                      name: String,
                                      kind: PortKind,
                                      description: String,
                                      editable: Bool) -> Port
    {
        guard editable, kind == .Inlet else
        {
            return portType.makeFreshPort(name: name, kind: kind, description: description)
        }

        switch portType
        {
        case .Int:
            return ParameterPort(parameter: IntParameter(name, 0, .inputfield, description))
        case .Float:
            return ParameterPort(parameter: FloatParameter(name, 0, .inputfield, description))
        case .Vector2:
            return ParameterPort(parameter: Float2Parameter(name, .zero, .inputfield, description))
        case .Vector3:
            return ParameterPort(parameter: Float3Parameter(name, .zero, .inputfield, description))
        case .Vector4:
            return ParameterPort(parameter: Float4Parameter(name, .zero, .inputfield, description))
        case .Color:
            return ParameterPort(parameter: Float4Parameter(name, simd_float4(0, 0, 0, 1), .colorpicker, description))
        case .Transform:
            return ParameterPort(parameter: Float4x4Parameter(name, matrix_identity_float4x4, .inputfield, description))
        default:
            return portType.makeFreshPort(name: name, kind: kind, description: description)
        }
    }
}
