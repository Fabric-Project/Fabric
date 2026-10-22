import Testing
import Metal
@testable import Fabric
import Satin

/// The Iterator records its subgraph into the frame's Satin submission once per iteration, each
/// record snapshotting the subgraph as that iteration left it: N iterations of one mesh draw exactly
/// what N separately placed meshes draw.
@Suite("Iterator records")
struct IteratorRecordTests
{
    /// Places its mesh by the iteration it executes in: iteration `i` at x = `offsets[i]`.
    private final class IterationPlacedMeshNode: MeshNode
    {
        var offsets: [Float] = []

        override public func execute(renderer: GraphRenderer,
                                     executionInfo: GraphExecutionInfo,
                                     renderPassDescriptor: MTLRenderPassDescriptor,
                                     commandBuffer: MTLCommandBuffer) throws
        {
            try super.execute(renderer: renderer,
                              executionInfo: executionInfo,
                              renderPassDescriptor: renderPassDescriptor,
                              commandBuffer: commandBuffer)
            guard !offsets.isEmpty else { return }
            let iteration = executionInfo.iterationInfo?.currentIteration ?? 0
            object?.position = [offsets[min(iteration, offsets.count - 1)], 0, 0]
        }
    }

    private static let offsets: [Float] = [-0.5, 0.5]
    private static let scale = simd_float3(repeating: 0.3)

    private func makeIteratorGraph(_ harness: GraphExecutionTestHarness, iterations: Int) -> (graph: Graph, iterator: IteratorNode)
    {
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        graph.addNode(iterator)

        let geometry = BoxGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = IterationPlacedMeshNode(context: harness.context)
        mesh.offsets = Self.offsets
        mesh.inputScale.value = Self.scale
        iterator.subGraph.addNode(geometry)
        iterator.subGraph.addNode(material)
        iterator.subGraph.addNode(mesh)
        iterator.subGraph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        iterator.subGraph.connect(material.outputMaterial, to: mesh.inputMaterial)

        iterator.inputIteratonCount.value = iterations
        return (graph, iterator)
    }

    /// One plain mesh per offset in `offsets`, in the graph's own scene.
    private func makeReferenceGraph(_ harness: GraphExecutionTestHarness, offsets: ArraySlice<Float>) -> Graph
    {
        let graph = Graph(context: harness.context)
        let geometry = BoxGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        graph.addNode(geometry)
        graph.addNode(material)
        for offset in offsets
        {
            let mesh = MeshNode(context: harness.context)
            mesh.inputPosition.value = [offset, 0, 0]
            mesh.inputScale.value = Self.scale
            graph.addNode(mesh)
            graph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
            graph.connect(material.outputMaterial, to: mesh.inputMaterial)
        }
        return graph
    }

    private func render(_ graph: Graph, _ harness: GraphExecutionTestHarness, frameNumber: Int = 0) throws -> [UInt8]
    {
        let texture = try harness.execute(graph: graph,
                                          executionInfo: harness.makeExecutionInfo(frameNumber: frameNumber),
                                          drawScene: true)
        return try pixels(of: texture, harness)
    }

    private func pixels(of texture: MTLTexture, _ harness: GraphExecutionTestHarness) throws -> [UInt8]
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat,
                                                                  width: texture.width,
                                                                  height: texture.height,
                                                                  mipmapped: false)
        descriptor.storageMode = .shared
        guard let readback = harness.context.device.makeTexture(descriptor: descriptor),
              let commandBuffer = harness.renderer.commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else { throw GraphExecutionTestFailure("Failed to make the readback texture") }
        blit.copy(from: texture, to: readback)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress
            {
                readback.getBytes(baseAddress, bytesPerRow: texture.width * 4,
                                  from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            }
        }
        return bytes
    }

    @Test("Each iteration draws where that iteration placed the mesh")
    func eachIterationDrawsWhereItWasPlaced() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let (iteratorGraph, _) = makeIteratorGraph(harness, iterations: 2)
        let referenceGraph = makeReferenceGraph(harness, offsets: Self.offsets[...])
        let emptyGraph = makeReferenceGraph(harness, offsets: [])

        try harness.graphRenderer(for: iteratorGraph).startExecution()
        try harness.graphRenderer(for: referenceGraph).startExecution()
        try harness.graphRenderer(for: emptyGraph).startExecution()
        let iterated = try render(iteratorGraph, harness)
        let reference = try render(referenceGraph, harness)
        let empty = try render(emptyGraph, harness)
        try harness.graphRenderer(for: iteratorGraph).stopExecution()
        try harness.graphRenderer(for: referenceGraph).stopExecution()
        try harness.graphRenderer(for: emptyGraph).stopExecution()

        #expect(reference != empty, "the reference draws its meshes")
        #expect(iterated == reference, "two iterations draw both placements, not the last one twice")
    }

    @Test("Changing the iteration count changes what the next frame draws")
    func changingTheIterationCountChangesTheNextFrame() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let (iteratorGraph, iterator) = makeIteratorGraph(harness, iterations: 2)
        let bothGraph = makeReferenceGraph(harness, offsets: Self.offsets[...])
        let firstGraph = makeReferenceGraph(harness, offsets: Self.offsets.prefix(1))

        try harness.graphRenderer(for: iteratorGraph).startExecution()
        try harness.graphRenderer(for: bothGraph).startExecution()
        try harness.graphRenderer(for: firstGraph).startExecution()
        let twoIterations = try render(iteratorGraph, harness, frameNumber: 0)
        iterator.inputIteratonCount.value = 1
        let oneIteration = try render(iteratorGraph, harness, frameNumber: 1)
        let both = try render(bothGraph, harness)
        let first = try render(firstGraph, harness)
        try harness.graphRenderer(for: iteratorGraph).stopExecution()
        try harness.graphRenderer(for: bothGraph).stopExecution()
        try harness.graphRenderer(for: firstGraph).stopExecution()

        #expect(twoIterations == both)
        #expect(oneIteration == first, "each frame's records are its own: last frame's second iteration is gone")
    }
}
