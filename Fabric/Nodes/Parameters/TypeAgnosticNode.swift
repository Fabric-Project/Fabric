//
//  TypeAgnosticNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

/// Base class for nodes whose behavior is identical regardless of data type.
/// The type picker is a practical concession to the type system, not a semantic choice.
public class TypeAgnosticNode: StrategyNode
{
    /// When false, the strategy picker shows scalar element types only (no Array variants).
    /// Set to false for nodes that operate on arrays structurally (Reverse, Shuffle, Subarray, Queue),
    /// where the user picks the element type and the node creates typed array ports accordingly.
    public class var includesArrayTypesInStrategy: Bool { true }

    public override class var strategies: [String]
    {
        let includesArrayTypes = Self.includesArrayTypesInStrategy
        var types: [PortType] = [.Virtual]
        types += PortType.allCases.filter { portType in
            if portType == .Virtual { return false }
            if !includesArrayTypes, case .Array = portType { return false }
            return true
        }
        return types.map(\.rawValue)
    }

    public override class var defaultStrategy: String { PortType.Virtual.rawValue }
    public override class var separatorAfterFirstStrategy: Bool { true }

    /// The currently active port type, derived from the strategy string.
    public var selectedPortType: PortType { PortType(rawValue: strategy) ?? .Virtual }

    /// Sets displayName from the current strategy. Subclasses must call super first.
    public override func rebuildPorts(forStrategy strategy: String)
    {
        let portType = PortType(rawValue: strategy) ?? .Virtual
        displayName = portType == .Virtual ? nil : "\(type(of: self).name) \(portType.rawValue)"
    }
}
