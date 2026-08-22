import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// The reconcile every device-backed node shares (Node.synchronizeDeviceOutputPorts):
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

    private func synchronize(_ node: Node, to descriptors: [DeviceOutputPortDescriptor]) -> [DeviceOutputPortDescriptor]
    {
        node.synchronizeDeviceOutputPorts(to: descriptors,
                                          buttonDescription: "Button",
                                          axisDescription: "Axis")
    }

    @Test("Matching ports survive a resync so their wires do")
    func matchingPortsSurvive() throws
    {
        guard let context = makeContext() else { return }

        let node = GameControllerNode(context: context)
        let descriptors = [DeviceOutputPortDescriptor(name: "Left Stick X", isButton: false),
                           DeviceOutputPortDescriptor(name: "A", isButton: true)]

        #expect(synchronize(node, to: descriptors).count == 2)

        let savedIDs = node.ports.map(\.id)

        #expect(synchronize(node, to: descriptors).isEmpty)
        #expect(node.ports.map(\.id) == savedIDs)
    }

    @Test("A port whose element changed type is replaced, not kept")
    func mistypedPortsAreReplaced() throws
    {
        guard let context = makeContext() else { return }

        let node = GameControllerNode(context: context)
        synchronize(node, to: [DeviceOutputPortDescriptor(name: "Trigger", isButton: false)])
        #expect(node.findPort(named: "Trigger") is NodePort<Float>)

        // Name-only matching kept the Float port here, leaving a button's state
        // with nowhere to go.
        let created = synchronize(node, to: [DeviceOutputPortDescriptor(name: "Trigger", isButton: true)])

        #expect(created.map(\.name) == ["Trigger"])
        #expect(node.findPort(named: "Trigger") is NodePort<Bool>)
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
