//
//  TypeAgnosticNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

// PortType already has a rawValue: String computed property, satisfying NodeStrategyOption.
extension PortType: NodeStrategyOption {}

/// Base class for nodes whose behavior is identical regardless of data type.
/// The type picker is a practical concession to the type system, not a semantic choice.
public class TypeAgnosticNode: StrategyNode
{
    /// When false, the strategy picker shows scalar element types only (no Array variants).
    /// Set to false for nodes that operate on arrays structurally (Reverse, Shuffle, Subarray, Queue),
    /// where the user picks the element type and the node creates typed array ports accordingly.
    public class var includesArrayTypesInStrategy: Bool { true }

    public override class var strategyOptions: [any NodeStrategyOption]
    {
        let includesArrayTypes = Self.includesArrayTypesInStrategy
        var types: [PortType] = [.Virtual]
        types += includesArrayTypes ? PortType.allCases.filter { $0 != .Virtual } : PortType.scalarCases
        return types
    }

    public override class var separatorAfterFirstStrategy: Bool { true }

    /// The currently active port type, derived from the strategy string.
    public var selectedPortType: PortType { PortType(rawValue: strategy) ?? .Virtual }

    /// Convenience programmatic init for a specific port type.
    public convenience init(context: Context, portType: PortType)
    {
        self.init(context: context, initialStrategy: portType.rawValue)
    }

    /// Node-generated name: the selected port type leads the title, e.g. "Float
    /// Sample and Hold" (NodeTitleView appends the type name after it). Virtual —
    /// the no-configuration default — suppresses the token so the node reads as its
    /// plain type name.
    override public func deriveCustomName() -> String? {
        let portType = selectedPortType
        return portType == .Virtual ? nil : portType.rawValue
    }

    public func addOrReplaceDynamicPortPreservingIdentity(name registryName: String,
                                                          displayName: String,
                                                          portType: PortType,
                                                          kind: PortKind,
                                                          description: String)
    {
        if let existing: Port = findPort(named: registryName), existing.portType != portType
        {
            let oldConnections = existing.connectedPorts
            let oldPublished = existing.published
            let oldPublishedName = existing.publishedName
            let oldValue = existing.snapshotValue()

            removePort(existing)

            let replacement = portType.makeFreshPort(
                name: displayName,
                kind: kind,
                description: description,
                id: existing.id
            )
            replacement.published = oldPublished
            replacement.publishedName = oldPublishedName
            if let oldValue
            {
                replacement.restoreValue(from: oldValue)
            }

            addDynamicPort(replacement, name: registryName)

            for connected in oldConnections where replacement.canConnect(to: connected)
            {
                replacement.connect(to: connected)
            }
        }

        if findPort(named: registryName) == nil
        {
            addDynamicPort(
                portType.makeFreshPort(
                    name: displayName,
                    kind: kind,
                    description: description
                ),
                name: registryName
            )
        }
    }
}
