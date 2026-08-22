//
//  NumericVirtualPort.swift
//  Fabric
//

import Foundation

public final class NumericVirtualPort: NodePort<PortValue>
{
    @ObservationIgnored override public var portType: PortType { .NumericVirtual }

    override internal func sendBoxed(_ boxed: PortValue?)
    {
        sendBoxed(boxed, force: false)
    }

    override internal func sendBoxed(_ boxed: PortValue?, force: Bool)
    {
        guard boxed?.numericPortType != nil || boxed == nil else { return }
        self.send(boxed, force: force)
    }
}

extension PortValue
{
    var numericPortType: PortType?
    {
        switch self
        {
        case .Int:
            return .Int
        case .Float:
            return .Float
        case .Vector2:
            return .Vector2
        case .Vector3:
            return .Vector3
        case .Vector4:
            return .Vector4
        case .Quaternion:
            return .Quaternion
        case .Transform:
            return .Transform
        case .Array(let values):
            guard let first = values.first else { return .Array(portType: .Float) }
            guard let elementType = first.numericPortType else { return nil }
            for value in values.dropFirst() where value.numericPortType != elementType
            {
                return nil
            }
            return .Array(portType: elementType)
        default:
            return nil
        }
    }
}
