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

    /// The strategy's port type, resolved before each reconcile.
    public private(set) var selectedNumericPortType: PortType = .NumericVirtual

    override public func prepareDeclarations()
    {
        super.prepareDeclarations()
        self.selectedNumericPortType = strategyOption(as: NumericPortStrategy.self)?.portType ?? .NumericVirtual
    }

    public convenience init(context: Context, portType: PortType)
    {
        self.init(context: context, strategy: portType == .NumericVirtual ? NumericPortStrategy.virtual : NumericPortStrategy.concrete(portType))
    }

    /// Node-generated name: the selected numeric port type leads the title, e.g.
    /// "Float Tween" (NodeTitleView appends the type name after it). NumericVirtual
    /// — the no-configuration default — suppresses the token so the node reads as
    /// its plain type name.
    override public func deriveSubtitle() -> String? {
        let portType = selectedNumericPortType
        return portType == .NumericVirtual ? nil : portType.rawValue
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

    /// Takes the type of what is wired to `port`, while the node is Numeric
    /// Virtual. Called from execute with a port bindPorts() resolved.
    @discardableResult
    public func specializeFromConnectedPort(_ port: Port?) -> Bool
    {
        guard selectedNumericPortType == .NumericVirtual,
              let port,
              let connectedType = port.connectedPorts.first?.portType,
              Self.supportedPortTypes.contains(connectedType)
        else { return false }

        setStrategy(NumericPortStrategy.concrete(connectedType))
        return true
    }
}
