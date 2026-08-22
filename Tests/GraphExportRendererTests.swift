import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

private func publishExportPort(_ port: Fabric.Port, in graph: Graph) {
    port.published = true
    graph.rebuildPublishedParameterGroup()
}

private func requireExportValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw GraphExecutionTestFailure(message)
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
        guard let harness = GraphExecutionTestHarness() else { return }

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

        try renderer.start()
        try renderer.renderFrame(into: texture, time: 5.0)
        try expectExportEqual(timeNode.outputNumber.value, 5.0)
        try renderer.finish()
    }

    @Test("Sequential export frames derive delta time internally")
    func sequentialExportFramesDeriveDeltaTimeInternally() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

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

        try renderer.start()
        try renderer.renderFrame(into: texture, time: 10.0)
        try expectExportEqual(integralNode.outputNumber.value, 0.0)

        try renderer.renderFrame(into: texture, time: 11.25)
        try expectExportEqual(integralNode.outputNumber.value, 2.5)

        try renderer.renderFrame(into: texture, time: 12.0)
        try expectExportEqual(integralNode.outputNumber.value, 4.0)
        try renderer.finish()
    }

    @Test("Sequential export frames advance internal frame number")
    func sequentialExportFramesAdvanceInternalFrameNumber() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

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

        try renderer.start()
        try renderer.renderFrame(into: texture, time: 1.0)
        #expect(renderInfoNode.outputFrameNumber.value == 0)

        try renderer.renderFrame(into: texture, time: 2.0)
        #expect(renderInfoNode.outputFrameNumber.value == 1)
        try renderer.finish()
    }
}
