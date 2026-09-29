#if FABRIC_SYPHON_ENABLED

import Testing
import simd
import Satin
@testable import Fabric

/// Syphon's shared surfaces are bottom-up, and Fabric's canonical images are
/// top-left, so every frame crossing that boundary is turned over exactly once.
/// Which side does the turning is the whole of it: the publisher asks Syphon to
/// do it, and the client declares what it received rather than copying it.
@Suite("Syphon orientation")
struct SyphonOrientationTests
{
    @Test("A canonical image is the one Syphon has to turn over")
    func canonicalIsPublishedFlipped() throws
    {
        #expect(SyphonServerNode.syphonRequiresVerticalFlip(for: matrix_identity_float4x4))
    }

    /// What `SyphonClientNode` emits. Publishing it again is a straight blit:
    /// the bytes are already the way Syphon holds them.
    @Test("An image already stored bottom-up goes across as it stands")
    func aReceivedFrameIsRepublishedUntouched() throws
    {
        #expect(SyphonServerNode.syphonRequiresVerticalFlip(for: .textureVerticalFlip) == false)
    }
}

#endif // FABRIC_SYPHON_ENABLED
