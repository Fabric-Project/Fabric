import Testing
import Foundation
import Metal
@testable import Fabric

@Suite("GPU result delivery", .serialized)
struct GPUResultReadbackTests {
    private func fill(_ harness: GraphExecutionTestHarness, commands: MTLCommandBuffer, value: UInt8) throws -> MTLBuffer {
        let buffer = try #require(harness.context.device.makeBuffer(length: 4, options: .storageModeShared))
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.fill(buffer: buffer, range: 0..<4, value: value)
        blit.endEncoding()
        return buffer
    }

    @Test("Deferred decoding runs once on a later execution, never in a completion callback")
    func deferredResult() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let commands = try #require(harness.renderer.makeCommandBuffer())
        let output = try fill(harness, commands: commands, value: 7)
        let readback = GPUResultReadback<UInt8>()
        var reads = 0
        let immediate = try readback.read(renderer: harness.renderer, commandBuffer: commands,
                                         mode: .nextFrame, frameNumber: 0) {
            reads += 1
            return output.contents().load(as: UInt8.self)
        }
        #expect(immediate == nil)
        #expect(reads == 0)
        #expect(commands.status == .notEnqueued)
        commands.commit()
        commands.waitUntilCompleted()
        #expect(reads == 0)
        #expect(try readback.takeCompleted(beforeFrame: 0) == nil)
        #expect(try readback.takeCompleted(beforeFrame: 1) == 7)
        #expect(reads == 1)
        #expect(try readback.takeCompleted(beforeFrame: 2) == nil)
    }

    @Test("A synchronous request cancels older deferred delivery without discarding encoded GPU work")
    func switchingToSameFrame() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let commands = try #require(harness.renderer.makeCommandBuffer())
        let first = try fill(harness, commands: commands, value: 7)
        let readback = GPUResultReadback<UInt8>()
        _ = try readback.read(renderer: harness.renderer, commandBuffer: commands, mode: .nextFrame, frameNumber: 0) {
            first.contents().load(as: UInt8.self)
        }
        let second = try fill(harness, commands: commands, value: 11)
        let immediate = try readback.read(renderer: harness.renderer, commandBuffer: commands, mode: .sameFrame, frameNumber: 0) {
            second.contents().load(as: UInt8.self)
        }
        #expect(immediate == 11)
        #expect(first.contents().load(as: UInt8.self) == 7)
        #expect(try readback.takeCompleted(beforeFrame: 1) == nil)
        commands.commit()
        commands.waitUntilCompleted()
    }

    @Test("Reset rejects a callback which completes after the node stops")
    func resetPendingDelivery() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let commands = try #require(harness.renderer.makeCommandBuffer())
        let output = try fill(harness, commands: commands, value: 7)
        let readback = GPUResultReadback<UInt8>()
        _ = try readback.read(renderer: harness.renderer, commandBuffer: commands, mode: .nextFrame, frameNumber: 0) {
            output.contents().load(as: UInt8.self)
        }
        readback.reset()
        commands.commit()
        commands.waitUntilCompleted()
        #expect(try readback.takeCompleted(beforeFrame: 1) == nil)
    }

    @Test("Overlapping deferred requests keep their own buffers and return the newest completed value")
    func overlappingRequests() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let commands = try #require(harness.renderer.makeCommandBuffer())
        let readback = GPUResultReadback<UInt8>()
        for value in UInt8(1)...8 {
            let output = try fill(harness, commands: commands, value: value)
            _ = try readback.read(renderer: harness.renderer, commandBuffer: commands, mode: .nextFrame, frameNumber: 0) {
                output.contents().load(as: UInt8.self)
            }
        }
        commands.commit()
        commands.waitUntilCompleted()
        #expect(try readback.takeCompleted(beforeFrame: 1) == 8)
    }

    @Test("An abandoned uncommitted request becomes retryable without publishing an error")
    func abandonedRequest() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let readback = GPUResultReadback<UInt8>()
        try autoreleasepool {
            let commands = try #require(harness.renderer.makeCommandBuffer())
            let output = try fill(harness, commands: commands, value: 7)
            _ = try readback.read(renderer: harness.renderer, commandBuffer: commands, mode: .nextFrame, frameNumber: 0) {
                output.contents().load(as: UInt8.self)
            }
            #expect(readback.hasPendingResult)
        }
        #expect(readback.hasPendingResult)
        #expect(readback.needsRetry)
        #expect(try readback.takeCompleted(beforeFrame: 1) == nil)
        readback.reset()
        #expect(!readback.hasPendingResult)
    }

    @Test("Deferred decoder errors are thrown on the execution owner")
    func decodingFailure() throws {
        enum Failure: Error { case invalidResult }
        let harness = try #require(GraphExecutionTestHarness())
        let commands = try #require(harness.renderer.makeCommandBuffer())
        let readback = GPUResultReadback<Int>()
        _ = try readback.read(renderer: harness.renderer, commandBuffer: commands, mode: .nextFrame, frameNumber: 0) {
            throw Failure.invalidResult
        }
        commands.commit()
        commands.waitUntilCompleted()
        #expect(throws: Failure.self) { try readback.takeCompleted(beforeFrame: 1) }
        #expect(try readback.takeCompleted(beforeFrame: 1) == nil)
    }
}
