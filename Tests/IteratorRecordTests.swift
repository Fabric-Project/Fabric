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
    private final class ImageCollectorNode: Node {
        override class var name: String { "Image Collector" }
        override class var nodeType: Node.NodeType { .Utility }
        override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
        override class var nodeTimeMode: Node.TimeMode { .None }
        override class var nodeDescription: String { "Collects each iteration's image for tests" }
        var images: [FabricImage] = []
        var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
        override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)] {
            super.registerPorts(context: context) + [
                ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet))
            ]
        }
        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
            if let image = inputImage.value { images.append(image) }
        }
    }
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

    private final class FailingIteratorNode: IteratorNode {
        var failAfterRecording = false

        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor,
                              commandBuffer: MTLCommandBuffer) throws {
            try super.execute(renderer: renderer, executionInfo: executionInfo,
                              renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
            if failAfterRecording {
                throw FabricError(.execution(.failed), severity: .fatal, message: "Failure after Iterator recording")
            }
        }
    }

    @Test("Direct evaluation never replays its Iterator records in a later draw", arguments: [false, true])
    func directEvaluationDiscardsRecords(fails: Bool) throws {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let iterator = FailingIteratorNode(context: harness.context)
        iterator.inputIteratonCount.value = 2
        iterator.failAfterRecording = fails
        addMesh(to: iterator.subGraph, harness: harness)
        graph.addNode(iterator)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }

        if fails {
            #expect(throws: FabricError.self) {
                try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: false)
            }
        } else {
            try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: false)
        }

        iterator.failAfterRecording = false
        iterator.inputIteratonCount.value = 0
        let actual = try render(graph, harness, frameNumber: 1)
        let empty = Graph(context: harness.context)
        let emptyRenderer = harness.graphRenderer(for: empty)
        try emptyRenderer.startExecution()
        defer { try? emptyRenderer.stopExecution() }
        let expected = try render(empty, harness)
        #expect(actual.elementsEqual(expected), "Direct evaluation's old mesh records must not reach the next draw")
    }

    private final class IterationImageProducer: Node {
        override class var name: String { "Iteration Image Producer" }
        override class var nodeType: Node.NodeType { .Utility }
        override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
        override class var nodeTimeMode: Node.TimeMode { .None }
        override class var nodeDescription: String { "Produces an occurrence-specific colour image" }
        override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)] {
            super.registerPorts(context: context) + [
                ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet))
            ]
        }
        var outputImage: NodePort<FabricImage> { port(named: "outputImage") }
        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor,
                              commandBuffer: MTLCommandBuffer) throws {
            let image = try renderer.newImage(withWidth: 4, height: 4)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = image.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = executionInfo.iterationInfo?.currentIteration == 0
                ? MTLClearColorMake(1, 0, 0, 1) : MTLClearColorMake(0, 0, 1, 1)
            let encoder = try #require(commandBuffer.makeRenderCommandEncoder(descriptor: pass))
            encoder.endEncoding()
            outputImage.send(image, force: true)
        }
    }

    private final class IterationImageMesh: ImageMeshNode {
        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor,
                              commandBuffer: MTLCommandBuffer) throws {
            try super.execute(renderer: renderer, executionInfo: executionInfo,
                              renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
            object?.position.x = executionInfo.iterationInfo?.currentIteration == 0 ? -0.5 : 0.5
        }
    }

    @Test("Recorded image meshes preserve each occurrence's image after ports advance")
    func recordedImageVersionsStayDistinct() throws {
        let harness = try #require(GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64))
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        iterator.inputIteratonCount.value = 2
        let producer = IterationImageProducer(context: harness.context)
        let mesh = IterationImageMesh(context: harness.context)
        mesh.inputSize.value = 0.5
        iterator.subGraph.addNode(producer)
        iterator.subGraph.addNode(mesh)
        iterator.subGraph.connect(producer.outputImage, to: mesh.inputImage)
        graph.addNode(iterator)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        let result = try render(graph, harness)
        let left = (32 * 64 + 16) * 4
        let right = (32 * 64 + 48) * 4
        // The target is BGRA; both draws replay after the two input images were produced.
        #expect(Array(result[left..<(left + 4)]) == [0, 0, 255, 255])
        #expect(Array(result[right..<(right + 4)]) == [255, 0, 0, 255])
    }

    private static let offsets: [Float] = [-0.5, 0.5]
    private static let scale = simd_float3(repeating: 0.3)

    private func makeIteratorGraph(_ harness: GraphExecutionTestHarness, iterations: Int) -> (graph: Graph, iterator: IteratorNode)
    {
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        graph.addNode(iterator)

        addMesh(to: iterator.subGraph, harness: harness)
        iterator.inputIteratonCount.value = iterations
        return (graph, iterator)
    }

    private func addMesh(to graph: Graph, harness: GraphExecutionTestHarness) {
        let geometry = BoxGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = IterationPlacedMeshNode(context: harness.context)
        mesh.offsets = Self.offsets
        mesh.inputScale.value = Self.scale
        graph.addNode(geometry)
        graph.addNode(material)
        graph.addNode(mesh)
        graph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        graph.connect(material.outputMaterial, to: mesh.inputMaterial)
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

    @Test("Iterator inside Render to Image draws all occurrences into its own target")
    func iteratorInsideRenderToImageMatchesRootRendering() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let (inside, _) = makeIteratorGraph(harness, iterations: 2)
        let imageNode = DeferredSubgraphNode(context: harness.context, subGraph: inside)
        imageNode.inputWidth.value = 64
        imageNode.inputHeight.value = 64
        let outer = Graph(context: harness.context)
        outer.addNode(imageNode)
        let reference = makeReferenceGraph(harness, offsets: Self.offsets[...])
        try harness.graphRenderer(for: outer).startExecution()
        try harness.graphRenderer(for: reference).startExecution()
        defer {
            try? harness.graphRenderer(for: outer).stopExecution()
            try? harness.graphRenderer(for: reference).stopExecution()
        }
        try harness.render(graph: outer, executionInfo: harness.makeExecutionInfo())
        let image = try #require(imageNode.outputColorTexture.value)
        #expect(try pixels(of: image.texture, harness) == render(reference, harness))
    }

    @Test("Render to Image inside Iterator publishes distinct iteration images")
    func renderToImageInsideIteratorKeepsEachImage() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let inside = Graph(context: harness.context)
        addMesh(to: inside, harness: harness)
        let imageNode = DeferredSubgraphNode(context: harness.context, subGraph: inside)
        imageNode.inputWidth.value = 64
        imageNode.inputHeight.value = 64
        let collector = ImageCollectorNode(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        iterator.inputIteratonCount.value = 2
        iterator.subGraph.addNode(imageNode)
        iterator.subGraph.addNode(collector)
        iterator.subGraph.connect(imageNode.outputColorTexture, to: collector.inputImage)
        let outer = Graph(context: harness.context)
        outer.addNode(iterator)
        let first = makeReferenceGraph(harness, offsets: Self.offsets.prefix(1))
        let second = makeReferenceGraph(harness, offsets: Self.offsets.suffix(1))
        for graph in [outer, first, second] { try harness.graphRenderer(for: graph).startExecution() }
        defer { for graph in [outer, first, second] { try? harness.graphRenderer(for: graph).stopExecution() } }
        try harness.render(graph: outer, executionInfo: harness.makeExecutionInfo())
        #expect(collector.images.count == 2)
        guard collector.images.count == 2 else { return }
        #expect(collector.images[0].texture !== collector.images[1].texture)
        #expect(try pixels(of: collector.images[0].texture, harness) == render(first, harness))
        #expect(try pixels(of: collector.images[1].texture, harness) == render(second, harness))
    }

    @Test("An inner Iterator restores the enclosing iteration context")
    func innerIteratorRestoresOuterContext() throws {
        guard let harness = GraphExecutionTestHarness() else { return }
        let iterator = IteratorNode(context: harness.context)
        iterator.inputIteratonCount.value = 0
        let execution = harness.makeExecutionInfo()
        let outer = GraphIterationInfo(totalIterationCount: 3, currentIteration: 1)
        execution.iterationInfo = outer
        let commands = try #require(harness.renderer.makeCommandBuffer())
        try iterator.execute(renderer: harness.renderer, executionInfo: execution,
                             renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
        #expect(execution.iterationInfo == outer)
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
