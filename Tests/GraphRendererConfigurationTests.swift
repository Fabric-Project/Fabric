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

        let renderer = GraphRenderer(context: context, graph: Graph(context: context))
        let clearColor = renderer.renderEncoder.clearColor

        #expect(clearColor.red == 0)
        #expect(clearColor.green == 0)
        #expect(clearColor.blue == 0)
        #expect(clearColor.alpha == 0)
    }

    @Test func realtimeExecutionUsesTheFrameTimeItIsHanded() throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )

        let renderer = GraphRenderer(context: context, graph: Graph(context: context))
        try renderer.setup()
        defer { try? renderer.cleanup() }

        let frame = FrameTime(time: 2.5, deltaTime: 0.5, displayTime: 2.75, systemTime: 1_000, hostMediaTime: 500, frameNumber: 7)
        try renderer.update(frame: frame)

        #expect(renderer.currentExecutionInfo.timing == frame)
    }
}
