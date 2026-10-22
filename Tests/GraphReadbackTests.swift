import Testing
import Metal
import MetalPerformanceShaders
@testable import Fabric

@Suite("Graph synchronous GPU readback")
struct GraphReadbackTests {
    @Test("Readback waits for the submitted segment and leaves the wrapper usable")
    func readbackContinuesEncoding() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let raw = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        let commands = GraphCommandBuffer(commandBuffer: raw)
        let output = try #require(harness.context.device.makeBuffer(length: 4, options: .storageModeShared))
        let first = try #require(commands.makeBlitCommandEncoder())
        first.fill(buffer: output, range: 0..<4, value: 7)
        first.endEncoding()
        try harness.renderer.waitForGPUResults(commandBuffer: commands)
        #expect(raw.status == .completed)
        #expect(output.contents().load(as: UInt8.self) == 7)
        #expect(commands.rootCommandBuffer !== raw)

        let second = try #require(commands.makeBlitCommandEncoder())
        second.fill(buffer: output, range: 0..<4, value: 11)
        second.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
        #expect(output.contents().load(as: UInt8.self) == 11)
    }

    @Test("An unsupported buffer fails before it is committed")
    func ordinaryBufferIsNotPartiallyCommitted() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let commands = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        #expect(throws: GraphReadbackError.self) {
            try harness.renderer.waitForGPUResults(commandBuffer: commands)
        }
        #expect(commands.status == .notEnqueued)
    }

    @Test("An external MPS wrapper is rejected before graph execution")
    func externalWrapperCannotBypassContinuationLifetimes() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let raw = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        let commands = MPSCommandBuffer(commandBuffer: raw)
        #expect(throws: GraphReadbackError.self) {
            try harness.renderer.executeAndDraw(executionInfo: harness.makeExecutionInfo(),
                                               renderPassDescriptor: MTLRenderPassDescriptor(),
                                               commandBuffer: commands)
        }
        #expect(raw.status == .notEnqueued)
    }
}
