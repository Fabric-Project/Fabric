#if FABRIC_SYPHON_ENABLED

import Foundation
import Metal
import Syphon
import Testing
@testable import Fabric

@Suite("Syphon server lifecycle")
@MainActor
struct SyphonServerLifecycleTests
{
    @Test("Stop retires the server and restart publishes an unchanged image")
    func stopAndRestart() async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let commandQueue = try #require(harness.context.device.makeCommandQueue())
        let directory = SyphonServerDirectory.shared()
        let serverName = "Fabric lifecycle test \(UUID().uuidString)"
        let node = SyphonServerNode(context: harness.context)
        node.inputServerName.value = serverName
        node.inputTexture.value = try harness.makeImage(width: 8, height: 4)
        defer { try? node.disableExecution(renderer: harness.renderer) }

        func execute() throws
        {
            let commandBuffer = try #require(commandQueue.makeCommandBuffer())
            try node.execute(renderer: harness.renderer,
                             executionInfo: harness.makeExecutionInfo(),
                             renderPassDescriptor: MTLRenderPassDescriptor(),
                             commandBuffer: commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            #expect(commandBuffer.status == .completed)
            node.markClean()
        }

        func descriptions() -> [[String: any NSCoding]]
        {
            directory.servers(matchingName: serverName, appName: "")
        }

        try node.enableExecution(renderer: harness.renderer)
        #expect(node.executionState == .enabled)
        try execute()
        #expect(descriptions().isEmpty)

        try node.startExecution(renderer: harness.renderer)
        #expect(node.executionState == .started)
        try execute()
        try await waitForSyphon { descriptions().count == 1 }
        let firstDescription = try #require(descriptions().first)
        let firstIdentity = try #require(firstDescription[SyphonServerDescriptionUUIDKey] as? String)
        let firstClient = try #require(SyphonMetalClient(serverDescription: firstDescription,
                                                       device: harness.context.device))
        defer { firstClient.stop() }
        try await waitForSyphon { firstClient.newFrameImage()?.width == 8 }

        try node.stopExecution(renderer: harness.renderer)
        #expect(node.executionState == .stopped)
        try await waitForSyphon { descriptions().isEmpty && !firstClient.isValid }
        try execute()
        #expect(descriptions().isEmpty)

        #expect(node.inputTexture.valueDidChange == false)
        try node.startExecution(renderer: harness.renderer)
        try execute()
        try await waitForSyphon { descriptions().count == 1 }
        let restartedDescription = try #require(descriptions().first)
        #expect((restartedDescription[SyphonServerDescriptionUUIDKey] as? String) != firstIdentity)
        let restartedClient = try #require(SyphonMetalClient(serverDescription: restartedDescription,
                                                           device: harness.context.device))
        defer { restartedClient.stop() }
        try await waitForSyphon { restartedClient.newFrameImage()?.width == 8 }

        // Disabling must also retire a running server if called without stop.
        try node.disableExecution(renderer: harness.renderer)
        #expect(node.executionState == .disabled)
        try await waitForSyphon { descriptions().isEmpty && !restartedClient.isValid }
    }

    @Test("Deleting and undoing a server node retires and restores its advertisement")
    func deleteAndUndo() async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let directory = SyphonServerDirectory.shared()
        let serverName = "Fabric undo test \(UUID().uuidString)"
        let node = SyphonServerNode(context: harness.context)
        node.inputServerName.value = serverName
        graph.addNode(node)
        defer { try? renderer.disableExecution() }
        try renderer.startExecution()
        try await waitForSyphon { directory.servers(matchingName: serverName, appName: "").count == 1 }

        let undoManager = UndoManager()
        graph.undoManager = undoManager
        graph.delete(node: node)
        try renderer.synchronizeLifecycle()
        #expect(node.executionState == .disabled)
        try await waitForSyphon { directory.servers(matchingName: serverName, appName: "").isEmpty }

        undoManager.undo()
        try renderer.synchronizeLifecycle()
        #expect(node.executionState == .started)
        try await waitForSyphon { directory.servers(matchingName: serverName, appName: "").count == 1 }

        try renderer.stopExecution()
        try renderer.disableExecution()
        #expect(node.executionState == .disabled)
        try await waitForSyphon { directory.servers(matchingName: serverName, appName: "").isEmpty }
    }

}

#endif
