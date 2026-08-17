//
//  Node+DeviceOutputPorts.swift
//  Fabric
//

import Foundation

/// One output port as the device describes it — a HID element, a game
/// controller profile entry, a configured MIDI control. Codable because a
/// device is absent at decode time: the document carries the descriptors and
/// the node rebuilds its ports from them.
public struct DeviceOutputPortDescriptor: Codable, Equatable
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
    /// Reconciles this node's output ports against what its device currently
    /// offers. Matching ports survive, because their wires — restored from the
    /// document, or drawn by the user before the device was unplugged — die
    /// with them. A port whose descriptor is gone, or whose type no longer
    /// matches it, is removed instead: an element that turned from an axis into
    /// a button cannot keep carrying its value through a Float port. Returns
    /// the descriptors that had to be created.
    ///
    /// Every outlet a device node has comes from its device, so this owns the
    /// node's whole outlet set.
    @discardableResult
    internal func synchronizeDeviceOutputPorts(to descriptors: [DeviceOutputPortDescriptor],
                                               buttonDescription: String,
                                               axisDescription: String) -> [DeviceOutputPortDescriptor]
    {
        let descriptorsByName = Dictionary(descriptors.map { ($0.name, $0) },
                                           uniquingKeysWith: { first, _ in first })

        for port in self.outputPorts()
        {
            let descriptor = descriptorsByName[port.name]

            if descriptor?.isButton != (port is NodePort<Bool>)
            {
                self.removePort(port)
            }
        }

        var created: [DeviceOutputPortDescriptor] = []

        for descriptor in descriptors where (self.findPort(named: descriptor.name) as Port?) == nil
        {
            let port: Port = descriptor.isButton
                ? NodePort<Bool>(name: descriptor.name, kind: .Outlet, description: buttonDescription)
                : NodePort<Float>(name: descriptor.name, kind: .Outlet, description: axisDescription)

            self.addDynamicPort(port)
            created.append(descriptor)
        }

        return created
    }
}
