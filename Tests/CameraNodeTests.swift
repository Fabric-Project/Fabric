import Testing
import Foundation
import Metal
import CoreImage
import simd
@testable import Fabric
import Satin

/// What a camera node does to what a graph draws. Nothing else measures that:
/// a camera contributes no pixels of its own, so a camera that never reaches
/// the renderer, or reaches it misconfigured, renders a plausible picture of
/// the wrong thing rather than an error.
///
/// Each test draws one white quad and measures the pixels it covers.
@Suite("Camera Nodes", .serialized)
struct CameraNodeTests
{
    static let width = 320
    static let height = 180

    /// The subject's extent in pixels, or nil when nothing was drawn.
    private func drawnSize(_ texture: MTLTexture, device: MTLDevice) throws -> (width: Int, height: Int)?
    {
        let ciImage = try #require(CIImage(mtlTexture: texture, options: nil))
        let context = CIContext(mtlDevice: device)
        let cgImage = try #require(context.createCGImage(ciImage,
                                                         from: CGRect(x: 0, y: 0, width: texture.width, height: texture.height),
                                                         format: .RGBA8,
                                                         colorSpace: CGColorSpaceCreateDeviceRGB()))
        let bytes = [UInt8](try #require(cgImage.dataProvider?.data) as Data)
        let rowBytes = cgImage.bytesPerRow

        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<texture.height
        {
            for x in 0..<texture.width
            {
                let offset = y * rowBytes + x * 4
                guard bytes[offset] > 128, bytes[offset + 1] > 128, bytes[offset + 2] > 128 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (maxX - minX + 1, maxY - minY + 1)
    }

    /// A graph drawing one white quad, and whatever camera the caller adds.
    private func makeGraph(context: Context) -> Graph
    {
        let graph = Graph(context: context)

        let geometry = PerspectiveQuadGeometryNode(context: context)
        graph.addNode(geometry)

        let material = BasicColorMaterialNode(context: context)
        material.inputColor.value = simd_float4(1, 1, 1, 1)
        graph.addNode(material)

        let mesh = MeshNode(context: context)
        // The quad faces the camera either way; culling would decide by winding.
        mesh.inputCullingMode.value = "None"
        graph.addNode(mesh)

        geometry.outputGeometry.connect(to: mesh.inputGeometry)
        material.outputMaterial.connect(to: mesh.inputMaterial)
        graph.markConnectionsChanged()

        return graph
    }

    /// Draw a few frames, so a node added between them has its own frame to
    /// take effect in, and measure the last.
    private func draw(_ graph: Graph, with harness: GraphExecutionTestHarness, from frame: Int) throws -> (width: Int, height: Int)?
    {
        var texture: MTLTexture?
        for frameNumber in frame..<(frame + 3)
        {
            texture = try harness.execute(graph: graph,
                                          executionInfo: harness.makeExecutionInfo(frameNumber: frameNumber),
                                          drawScene: true)
        }
        return try drawnSize(try #require(texture), device: harness.context.device)
    }

    @Test("A camera at its defaults frames what a graph with no camera frames")
    func defaultsMatchTheFreeCamera() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: Self.width, renderHeight: Self.height) else { return }

        let free = makeGraph(context: harness.context)
        try harness.renderer.startExecution(graph: free)
        let withoutCamera = try #require(try draw(free, with: harness, from: 0), "The graph drew nothing")

        let authored = makeGraph(context: harness.context)
        authored.addNode(PerspectiveCameraNode(context: harness.context))
        try harness.renderer.startExecution(graph: authored)
        let withCamera = try #require(try draw(authored, with: harness, from: 10), "The graph drew nothing")

        #expect(withCamera == withoutCamera,
                "\(withCamera) with a camera node, \(withoutCamera) without one")
    }

    @Test("A camera added to a running graph is given the drawable's size")
    func addedLiveIsSized() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: Self.width, renderHeight: Self.height) else { return }

        let graph = makeGraph(context: harness.context)
        try harness.renderer.startExecution(graph: graph)
        let before = try #require(try draw(graph, with: harness, from: 0), "The graph drew nothing")

        graph.addNode(PerspectiveCameraNode(context: harness.context))
        let after = try #require(try draw(graph, with: harness, from: 10), "The graph drew nothing")

        // Sized from the drawable, the camera at its defaults frames what the
        // free camera framed. Sized from Satin's square default aspect, the
        // subject stretches to the target's shape instead.
        #expect(after == before,
                "\(after) once a camera was added, \(before) before it")
    }

    @Test("Moving a perspective camera back shrinks its subject")
    func perspectivePositionCarries() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: Self.width, renderHeight: Self.height) else { return }

        let graph = makeGraph(context: harness.context)
        let camera = PerspectiveCameraNode(context: harness.context)
        camera.inputPosition.value = simd_float3(0, 0, 10)
        graph.addNode(camera)
        try harness.renderer.startExecution(graph: graph)

        let drawn = try #require(try draw(graph, with: harness, from: 0), "The graph drew nothing")
        #expect(drawn.width == drawn.height, "Subject drew \(drawn), which is not square")
        #expect(drawn.width < 45, "Subject drew \(drawn) from ten units back")
    }

    @Test("Scaling an orthographic camera scales its view volume")
    func orthographicScaleCarries() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: Self.width, renderHeight: Self.height) else { return }

        let unscaled = makeGraph(context: harness.context)
        unscaled.addNode(OrthographicCameraNode(context: harness.context))
        try harness.renderer.startExecution(graph: unscaled)
        let atOne = try #require(try draw(unscaled, with: harness, from: 0), "The graph drew nothing")

        let scaled = makeGraph(context: harness.context)
        let camera = OrthographicCameraNode(context: harness.context)
        camera.inputScale.value = simd_float3(2, 2, 1)
        scaled.addNode(camera)
        try harness.renderer.startExecution(graph: scaled)
        let atTwo = try #require(try draw(scaled, with: harness, from: 10), "The graph drew nothing")

        // Twice the view volume, so half the subject — and square either way.
        #expect(atOne.width == atOne.height && atTwo.width == atTwo.height,
                "Subject drew \(atOne) at scale 1 and \(atTwo) at scale 2")
        #expect(abs(atTwo.width * 2 - atOne.width) <= 2,
                "Subject drew \(atOne.width) wide at scale 1 and \(atTwo.width) at scale 2")
    }

    @Test("A camera added to a graph that has one takes control")
    func lastCameraWins() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: Self.width, renderHeight: Self.height) else { return }

        let graph = makeGraph(context: harness.context)
        let sitting = PerspectiveCameraNode(context: harness.context)
        sitting.inputPosition.value = simd_float3(0, 0, 3)
        graph.addNode(sitting)
        try harness.renderer.startExecution(graph: graph)
        let before = try #require(try draw(graph, with: harness, from: 0), "The graph drew nothing")

        let added = PerspectiveCameraNode(context: harness.context)
        added.inputPosition.value = simd_float3(0, 0, 12)
        graph.addNode(added)
        let after = try #require(try draw(graph, with: harness, from: 10), "The graph drew nothing")

        // Twelve units back against three: a smaller subject, and only if the
        // camera that arrived last is the one the graph renders with.
        #expect(after.width < before.width,
                "Subject drew \(before) under the sitting camera and \(after) under the added one")
    }
}
