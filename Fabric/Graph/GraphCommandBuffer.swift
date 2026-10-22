import Metal
import MetalPerformanceShaders

/// The stable command-buffer object nodes receive. Every continuation protects the image uses
/// encoded so far, including continuations performed internally by an MPS library. A later error
/// or abandonment therefore cannot return storage still used by an earlier submitted segment.
final class GraphCommandBuffer: MPSCommandBuffer {
    private var imageUseScopes: [GraphFrameImageUses] = []

    func beginImageUses(_ uses: GraphFrameImageUses) {
        imageUseScopes.append(uses)
    }

    func endImageUses(_ uses: GraphFrameImageUses) {
        imageUseScopes.removeAll { $0 === uses }
    }

    override func commitAndContinue() {
        for uses in imageUseScopes { uses.retain(untilCompleted: rootCommandBuffer) }
        super.commitAndContinue()
    }
}
