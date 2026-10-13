//
//  Node+DeviceOutputPorts.swift
//  Fabric
//

import Foundation

/// One output port as the device describes it — a HID element, a game
/// controller profile entry, a configured MIDI control. Codable because a
/// device is absent at decode time: the document carries the descriptors and
/// the node rebuilds its ports from them.
public struct DeviceOutputPortDescriptor: Codable, Equatable, Sendable
{
    public let name: String
    public let isButton: Bool

    public init(name: String, isButton: Bool)
    {
        self.name = name
        self.isButton = isButton
    }
}

extension Node
{
    /// The outlets a device offers, in its order: a Bool outlet for a button,
    /// a Float outlet for an axis, under the descriptor's name. Declared, a
    /// port whose descriptor still matches is kept, wires and all, whether the
    /// document or a device that has since unplugged made it; one whose element
    /// turned from an axis into a button is replaced under its id.
    internal static func deviceOutputPortDeclarations(for descriptors: [DeviceOutputPortDescriptor],
                                                      buttonDescription: String,
                                                      axisDescription: String) -> [PortDeclaration]
    {
        descriptors.map { descriptor in
            descriptor.isButton
                ? PortDeclaration(registryKey: descriptor.name, port: NodePort<Bool>(name: descriptor.name, kind: .Outlet, description: buttonDescription))
                : PortDeclaration(registryKey: descriptor.name, port: NodePort<Float>(name: descriptor.name, kind: .Outlet, description: axisDescription))
        }
    }
}
