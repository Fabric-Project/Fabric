import Metal
import Satin
import Testing
@testable import Fabric

struct GraphRendererConfigurationTests
{
    @Test func renderEncoderUsesTransparentClearColor() throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .rgba16Float,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .stencil8
        )

        let renderer = GraphRenderer(context: context)
        let clearColor = renderer.renderEncoder.clearColor

        #expect(clearColor.red == 0)
        #expect(clearColor.green == 0)
        #expect(clearColor.blue == 0)
        #expect(clearColor.alpha == 0)
    }
}
