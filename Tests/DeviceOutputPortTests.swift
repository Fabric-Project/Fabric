import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// The outlets every device-backed node declares (Node.deviceOutputPortDeclarations):
/// ports follow the hardware, but wired-up ports must not be churned for nothing.
@Suite("Device Output Ports")
struct DeviceOutputPortTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
    }

    private func synchronize(_ node: GameControllerNode, to descriptors: [DeviceOutputPortDescriptor])
    {
        node.apply(GameControllerSettings(selectedControllerID: nil, portDescriptors: descriptors))
    }

    @Test("Matching ports survive a resync so their wires do")
    func matchingPortsSurvive() throws
    {
        guard let context = makeContext() else { return }

        let node = GameControllerNode(context: context)
        let descriptors = [DeviceOutputPortDescriptor(name: "Left Stick X", isButton: false),
                           DeviceOutputPortDescriptor(name: "A", isButton: true)]

        synchronize(node, to: descriptors)
        #expect(node.ports.count == 2)

        let savedPorts = node.ports

        synchronize(node, to: descriptors)
        #expect(node.ports.map(ObjectIdentifier.init) == savedPorts.map(ObjectIdentifier.init))
    }

    @Test("A port whose element changed type is replaced under its id, not kept")
    func mistypedPortsAreReplaced() throws
    {
        guard let context = makeContext() else { return }

        let node = GameControllerNode(context: context)
        synchronize(node, to: [DeviceOutputPortDescriptor(name: "Trigger", isButton: false)])
        let axis = try #require(node.findPort(named: "Trigger") as NodePort<Float>?)

        // Name-only matching kept the Float port here, leaving a button's state
        // with nowhere to go.
        synchronize(node, to: [DeviceOutputPortDescriptor(name: "Trigger", isButton: true)])

        let button = try #require(node.findPort(named: "Trigger") as NodePort<Bool>?)
        #expect(button.id == axis.id)
        #expect(node.ports.count == 1)
    }

    @Test("Ports the device no longer offers are removed")
    func retiredPortsAreRemoved() throws
    {
        guard let context = makeContext() else { return }

        let node = GameControllerNode(context: context)
        synchronize(node, to: [DeviceOutputPortDescriptor(name: "A", isButton: true),
                               DeviceOutputPortDescriptor(name: "B", isButton: true)])

        synchronize(node, to: [DeviceOutputPortDescriptor(name: "A", isButton: true)])

        #expect(node.ports.map(\.name) == ["A"])
    }
}
