import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// A node whose outlets are a device's, as HID, MIDI Input and Game Controller
/// declare them.
private final class DeviceTestNode: Node
{
    override class var name: String { "Device Test" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override class var nodeTimeMode: Node.TimeMode { .None }

    var descriptors: [DeviceOutputPortDescriptor] = []

    override func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + Self.deviceOutputPortDeclarations(for: descriptors, buttonDescription: "Button", axisDescription: "Axis")
    }
}

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

    /// Reconciles to `descriptors`, returning those it had to make a port for.
    @discardableResult
    private func synchronize(_ node: DeviceTestNode, to descriptors: [DeviceOutputPortDescriptor]) -> [DeviceOutputPortDescriptor]
    {
        let created = node.deviceOutputDescriptorsNeedingPorts(descriptors)
        node.descriptors = descriptors
        node.reconcilePorts()
        return created
    }

    @Test("Matching ports survive a resync so their wires do")
    func matchingPortsSurvive() throws
    {
        guard let context = makeContext() else { return }

        let node = DeviceTestNode(context: context)
        let descriptors = [DeviceOutputPortDescriptor(name: "Left Stick X", isButton: false),
                           DeviceOutputPortDescriptor(name: "A", isButton: true)]

        #expect(synchronize(node, to: descriptors).count == 2)

        let savedPorts = node.ports.map(ObjectIdentifier.init)

        #expect(synchronize(node, to: descriptors).isEmpty)
        #expect(node.ports.map(ObjectIdentifier.init) == savedPorts)
    }

    @Test("A port whose element changed type is retyped under its runtime id, not kept")
    func mistypedPortsAreReplaced() throws
    {
        guard let context = makeContext() else { return }

        let node = DeviceTestNode(context: context)
        synchronize(node, to: [DeviceOutputPortDescriptor(name: "Trigger", isButton: false)])
        let axis = try #require(node.findPort(named: "Trigger") as NodePort<Float>?)

        // Name-only matching kept the Float port here, leaving a button's state
        // with nowhere to go.
        let created = synchronize(node, to: [DeviceOutputPortDescriptor(name: "Trigger", isButton: true)])

        #expect(created.map(\.name) == ["Trigger"])
        let button = try #require(node.findPort(named: "Trigger") as NodePort<Bool>?)
        #expect(button.id == axis.id)
        #expect(node.ports.count == 1)
    }

    @Test("Ports the device no longer offers are removed")
    func retiredPortsAreRemoved() throws
    {
        guard let context = makeContext() else { return }

        let node = DeviceTestNode(context: context)
        synchronize(node, to: [DeviceOutputPortDescriptor(name: "A", isButton: true),
                               DeviceOutputPortDescriptor(name: "B", isButton: true)])

        synchronize(node, to: [DeviceOutputPortDescriptor(name: "A", isButton: true)])

        #expect(node.ports.map(\.name) == ["A"])
    }
}
