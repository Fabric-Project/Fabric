import Testing
import Foundation
@testable import Fabric
import Satin

@Suite("OSC Receive", .serialized)
@MainActor
struct OSCReceiveNodeTests
{
    /// An OSC message with one float argument, as a sender puts it on the wire.
    private func floatMessage(_ value: Float, address: String) -> [UInt8]
    {
        func paddedString(_ string: String) -> [UInt8]
        {
            var bytes = Array(string.utf8)
            bytes.append(0)
            while bytes.count % 4 != 0 { bytes.append(0) }
            return bytes
        }

        var message = paddedString(address) + paddedString(",f")
        withUnsafeBytes(of: value.bitPattern.bigEndian) { message.append(contentsOf: $0) }
        return message
    }

    private func send(_ message: [UInt8], toLocalPort port: UInt16) throws
    {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        try #require(socketDescriptor >= 0)
        defer { close(socketDescriptor) }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        destination.sin_addr.s_addr = inet_addr("127.0.0.1")

        let sentCount = message.withUnsafeBytes { bytes in
            withUnsafePointer(to: &destination) { destinationPointer in
                destinationPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(socketDescriptor, bytes.baseAddress, bytes.count, 0, address, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        try #require(sentCount == message.count)
    }

    /// Executes the node until `condition` holds; messages arrive on main.
    private func executeUntil(_ node: OSCReceiveNode, harness: GraphExecutionTestHarness, _ condition: () -> Bool) async throws
    {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while true
        {
            try harness.execute(node)
            if condition() { return }
            try #require(clock.now < deadline, "Timed out waiting for an OSC message")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Receives while started, and stops listening when stopped")
    func receivesOnlyWhileStarted() async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let listenPort = UInt16.random(in: 49152...65000)
        let node = OSCReceiveNode(context: harness.context,
                                  listenPort: listenPort,
                                  addressBindings: [OSCAddressBinding(address: "/fader", dataType: .float)])
        let output = try #require(node.outputPorts().first as? NodePort<Float>)

        try node.enableExecution(renderer: harness.renderer)
        try node.startExecution(renderer: harness.renderer)
        await drainMainQueue()
        #expect(node.deriveStatuses().isEmpty, "the server is listening")

        try send(floatMessage(1.5, address: "/fader"), toLocalPort: listenPort)
        try await executeUntil(node, harness: harness) { output.value == 1.5 }

        try node.stopExecution(renderer: harness.renderer)
        await drainMainQueue()
        try send(floatMessage(2.5, address: "/fader"), toLocalPort: listenPort)
        try await Task.sleep(for: .milliseconds(200))
        try harness.execute(node)
        #expect(output.value == 1.5, "a stopped node does not listen")

        try node.startExecution(renderer: harness.renderer)
        await drainMainQueue()
        try send(floatMessage(3.5, address: "/fader"), toLocalPort: listenPort)
        try await executeUntil(node, harness: harness) { output.value == 3.5 }

        try node.stopExecution(renderer: harness.renderer)
        try node.disableExecution(renderer: harness.renderer)
        await drainMainQueue()
    }

    @Test("A node on a deleted node's port receives once the deleted node has torn down")
    func deletedNodeReleasesItsPort() async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let listenPort = UInt16.random(in: 49152...65000)
        let binding = OSCAddressBinding(address: "/fader", dataType: .float)

        do
        {
            let node = OSCReceiveNode(context: harness.context, listenPort: listenPort, addressBindings: [binding])
            try node.enableExecution(renderer: harness.renderer)
            try node.startExecution(renderer: harness.renderer)
            await drainMainQueue()
            #expect(node.deriveStatuses().isEmpty)

            // As deleting does: stop and disable, then let go.
            try node.stopExecution(renderer: harness.renderer)
            try node.disableExecution(renderer: harness.renderer)
        }
        await drainMainQueue()

        let replacement = OSCReceiveNode(context: harness.context, listenPort: listenPort, addressBindings: [binding])
        let output = try #require(replacement.outputPorts().first as? NodePort<Float>)
        try replacement.enableExecution(renderer: harness.renderer)
        try replacement.startExecution(renderer: harness.renderer)
        await drainMainQueue()
        #expect(replacement.deriveStatuses().isEmpty, "the replacement server started")

        try send(floatMessage(4.5, address: "/fader"), toLocalPort: listenPort)
        try await executeUntil(replacement, harness: harness) { output.value == 4.5 }

        try replacement.stopExecution(renderer: harness.renderer)
        try replacement.disableExecution(renderer: harness.renderer)
        await drainMainQueue()
    }
}
