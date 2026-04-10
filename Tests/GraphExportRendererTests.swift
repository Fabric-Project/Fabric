import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

private struct GraphExportTestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct GraphExportTestHarness {
    let context: Context

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        self.context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
    }

    func makeTexture(width: Int = 320, height: Int = 180, pixelFormat: MTLPixelFormat = .bgra8Unorm) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = self.context.device.makeTexture(descriptor: descriptor) else {
            throw GraphExportTestFailure("Failed to create export texture")
        }

        return texture
    }
}

private func publishExportPort(_ port: Fabric.Port, in graph: Graph) {
    port.published = true
    graph.rebuildPublishedParameterGroup()
}

private func requireExportValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw GraphExportTestFailure(message)
    }

    return value
}

private func expectExportEqual(_ lhs: Float?, _ rhs: Float, tolerance: Float = 0.0001) throws {
    let lhs = try requireExportValue(lhs, "Expected Float value")
    #expect(abs(lhs - rhs) <= tolerance)
}

@Suite("Graph Export Renderer")
struct GraphExportRendererTests {

    @Test("Single frame export uses explicit graph time")
    func singleFrameExportUsesExplicitGraphTime() throws {
        guard let harness = GraphExportTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let timeNode = CurrentTimeNode(context: harness.context)
        graph.addNode(timeNode)
        publishExportPort(timeNode.outputNumber, in: graph)

        let texture = try harness.makeTexture()
        let renderer = GraphExportRenderer(
            graph: graph,
            context: harness.context,
            size: (width: 320, height: 180),
            colorPixelFormat: .bgra8Unorm
        )

        renderer.start()
        try renderer.renderFrame(into: texture, time: 5.0)
        try expectExportEqual(timeNode.outputNumber.value, 5.0)
        renderer.finish()
    }

    @Test("Sequential export frames derive delta time internally")
    func sequentialExportFramesDeriveDeltaTimeInternally() throws {
        guard let harness = GraphExportTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let integralNode = NumberIntegralNode(context: harness.context)
        integralNode.inputNumber.value = 2.0
        graph.addNode(integralNode)
        publishExportPort(integralNode.outputNumber, in: graph)

        let texture = try harness.makeTexture()
        let renderer = GraphExportRenderer(
            graph: graph,
            context: harness.context,
            size: (width: 320, height: 180),
            colorPixelFormat: .bgra8Unorm
        )

        renderer.start()
        try renderer.renderFrame(into: texture, time: 10.0)
        try expectExportEqual(integralNode.outputNumber.value, 0.0)

        try renderer.renderFrame(into: texture, time: 11.25)
        try expectExportEqual(integralNode.outputNumber.value, 2.5)

        try renderer.renderFrame(into: texture, time: 12.0)
        try expectExportEqual(integralNode.outputNumber.value, 4.0)
        renderer.finish()
    }

    @Test("Sequential export frames advance internal frame number")
    func sequentialExportFramesAdvanceInternalFrameNumber() throws {
        guard let harness = GraphExportTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let renderInfoNode = RenderInfoNode(context: harness.context)
        graph.addNode(renderInfoNode)
        publishExportPort(renderInfoNode.outputFrameNumber, in: graph)

        let texture = try harness.makeTexture()
        let renderer = GraphExportRenderer(
            graph: graph,
            context: harness.context,
            size: (width: 320, height: 180),
            colorPixelFormat: .bgra8Unorm
        )

        renderer.start()
        try renderer.renderFrame(into: texture, time: 1.0)
        #expect(renderInfoNode.outputFrameNumber.value == 0)

        try renderer.renderFrame(into: texture, time: 2.0)
        #expect(renderInfoNode.outputFrameNumber.value == 1)
        renderer.finish()
    }
}
