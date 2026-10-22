import Metal
import MetalPerformanceShaders

public enum GraphReadbackError: Error {
    case requiresRendererCommandBuffer
    case commandBufferFailed(Error?)
}

extension GraphRenderer {
    func validateContinuationOwnership(_ commandBuffer: MTLCommandBuffer) throws {
        if commandBuffer is MPSCommandBuffer, !(commandBuffer is GraphCommandBuffer) {
            throw GraphReadbackError.requiresRendererCommandBuffer
        }
    }
    /// Completes work encoded so far, then continues the logical frame through the same wrapper.
    /// Call on the graph's execution owner, with all encoders ended. For managed storage, encode
    /// its GPU-to-CPU synchronization before this call. The caller may read its results on return.
    public func waitForGPUResults(commandBuffer: MTLCommandBuffer) throws {
        guard let commands = commandBuffer as? GraphCommandBuffer else {
            throw GraphReadbackError.requiresRendererCommandBuffer
        }
        let submitted = commands.rootCommandBuffer
        commands.commitAndContinue()
        submitted.waitUntilCompleted()
        guard submitted.status == .completed else {
            throw GraphReadbackError.commandBufferFailed(submitted.error)
        }
    }
}
