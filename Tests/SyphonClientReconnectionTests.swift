#if FABRIC_SYPHON_ENABLED

import Foundation
import Metal
import Syphon
import Testing
@testable import Fabric

@Suite("Syphon client reconnection")
@MainActor
struct SyphonClientReconnectionTests
{
    @Test("A newer matching announcement replaces a client that still reports valid")
    func newerPublisherReplacesValidClient() async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let commandQueue = try #require(harness.context.device.makeCommandQueue())
        let directory = SyphonServerDirectory.shared()
        let serverName = "Fabric reconnection test \(UUID().uuidString)"
        let node = SyphonClientNode(context: harness.context)
        node.inputServerName.value = serverName
        try node.enableExecution(renderer: harness.renderer)
        try node.startExecution(renderer: harness.renderer)
        defer
        {
            try? node.stopExecution(renderer: harness.renderer)
            try? node.disableExecution(renderer: harness.renderer)
        }

        func execute() throws
        {
            let commandBuffer = try #require(commandQueue.makeCommandBuffer())
            try node.execute(renderer: harness.renderer,
                             executionInfo: harness.makeExecutionInfo(),
                             renderPassDescriptor: MTLRenderPassDescriptor(),
                             commandBuffer: commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        func publish(_ server: SyphonMetalServer, width: Int) throws
        {
            let texture = try harness.makeTexture(width: width, height: 4)
            let commandBuffer = try #require(commandQueue.makeCommandBuffer())
            server.publishFrameTexture(texture, on: commandBuffer,
                                       imageRegion: CGRect(x: 0, y: 0, width: width, height: 4),
                                       flipped: false)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            #expect(commandBuffer.status == .completed)
        }

        // Starting before the publisher must leave the node ready to connect.
        try execute()
        #expect(node.outputTexturePort.value == nil)

        let originalServer = SyphonMetalServer(name: serverName, device: harness.context.device, options: nil)
        defer { originalServer.stop() }
        try publish(originalServer, width: 4)
        try await waitForSyphon {
            try execute()
            return node.outputTexturePort.value?.texture.width == 4
        }
        let originalImage = try #require(node.outputTexturePort.value)
        try execute()
        #expect(node.outputTexturePort.value === originalImage)

        // Keep the old endpoint valid and present: this reproduces the state
        // observed after a crash without relying on a process timing race.
        let originalClient = try #require(SyphonMetalClient(serverDescription: originalServer.serverDescription,
                                                          device: harness.context.device))
        defer { originalClient.stop() }
        let replacementServer = SyphonMetalServer(name: serverName, device: harness.context.device, options: nil)
        defer { replacementServer.stop() }
        try publish(replacementServer, width: 8)
        try await waitForSyphon {
            directory.servers(matchingName: serverName, appName: "").count == 2
        }
        #expect(originalClient.isValid)
        try await waitForSyphon {
            try execute()
            return node.outputTexturePort.value?.texture.width == 8
        }
        #expect(node.outputTexturePort.value !== originalImage)
        #expect(originalClient.isValid)

        // Retiring the newest publisher should make the older one eligible again.
        replacementServer.stop()
        try await waitForSyphon {
            try execute()
            return node.outputTexturePort.value?.texture.width == 4
        }
        node.inputEnabled.value = false
        try execute()
        #expect(node.outputTexturePort.value == nil)
    }

}

#endif
