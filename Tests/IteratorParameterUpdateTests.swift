import Testing
import Metal
import Satin
@testable import Fabric

@Suite("Iterator parameter updates")
struct IteratorParameterUpdateTests {
    @Test("Reopening an Iterator preserves circle size on its first draw", arguments: [false, true])
    func reopenedCircleSize(initiallyEmpty: Bool) throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        let geometry = CircleGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = InstancedMeshNode(context: harness.context)
        graph.addNode(iterator)
        for node in [geometry, material, mesh] as [Node] { iterator.subGraph.addNode(node) }
        iterator.subGraph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        iterator.subGraph.connect(material.outputMaterial, to: mesh.inputMaterial)
        geometry.inputSize.value = 0.005
        material.inputDepthTest.value = false
        material.inputWriteDepth.value = false
        iterator.inputIteratonCount.value = initiallyEmpty ? 0 : 2
        let data = try JSONEncoder().encode(graph)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context)
        let reopened = try decoder.decode(Graph.self, from: data)
        let reopenedIterator = try #require(reopened.nodes.first as? IteratorNode)
        let reopenedGeometry = try #require(reopenedIterator.subGraph.nodes.compactMap { $0 as? CircleGeometryNode }.first)
        let reopenedMaterial = try #require(reopenedIterator.subGraph.nodes.compactMap { $0 as? BasicColorMaterialNode }.first)
        let reopenedMesh = try #require(reopenedIterator.subGraph.nodes.compactMap { $0 as? InstancedMeshNode }.first)
        reopenedMesh.inputTransforms.value = [matrix_identity_float4x4]
        #expect(reopenedGeometry.inputSize.value == 0.005)
        let renderer = harness.graphRenderer(for: reopened)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        _ = try harness.execute(graph: reopened, executionInfo: harness.makeExecutionInfo(frameNumber: 0), drawScene: true)
        if initiallyEmpty {
            reopenedIterator.inputIteratonCount.value = 2
            _ = try harness.execute(graph: reopened, executionInfo: harness.makeExecutionInfo(frameNumber: 1), drawScene: true)
        }
        #expect(reopenedGeometry.geometry.radius == 0.005)
        #expect(reopenedMaterial.material.depthCompareFunction == .always)
        #expect(!reopenedMaterial.material.depthWriteEnabled)
        let renderedMesh = try #require(reopenedMesh.object)
        #expect(renderedMesh.geometry === reopenedGeometry.geometry)
    }

    @Test("Geometry and depth controls survive an initially empty Iterator", arguments: [false, true])
    func controlsUpdateWithoutSaving(initiallyEmpty: Bool) throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        let geometry = CircleGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = InstancedMeshNode(context: harness.context)
        graph.addNode(iterator)
        for node in [geometry, material, mesh] as [Node] { iterator.subGraph.addNode(node) }
        iterator.subGraph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        iterator.subGraph.connect(material.outputMaterial, to: mesh.inputMaterial)
        iterator.inputIteratonCount.value = 2
        mesh.inputTransforms.value = [matrix_identity_float4x4]
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }

        if initiallyEmpty {
            geometry.inputSize.value = 0.1
            material.inputDepthTest.value = false
            material.inputWriteDepth.value = false
            iterator.inputIteratonCount.value = 0
            _ = try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: 0), drawScene: true)
            iterator.inputIteratonCount.value = 2
            _ = try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: 1), drawScene: true)
            #expect(geometry.geometry.radius == 0.1)
            #expect(material.material.depthCompareFunction == .always)
            #expect(!material.material.depthWriteEnabled)
            #expect(mesh.object != nil)
        }

        var previousDepthState: MTLDepthStencilState?
        for (frameNumber, radius) in [Float(0.1), 0.4, 0.2].enumerated() {
            let size = try #require(geometry.inputSize.parameter as? FloatParameter)
            let depthTest = try #require(material.inputDepthTest.parameter as? BoolParameter)
            let depthWrite = try #require(material.inputWriteDepth.parameter as? BoolParameter)
            size.value = radius
            depthTest.value = frameNumber == 1
            depthWrite.value = frameNumber == 1
            _ = try harness.execute(graph: graph,
                                    executionInfo: harness.makeExecutionInfo(frameNumber: frameNumber),
                                    drawScene: true)
            #expect(geometry.geometry.radius == radius)
            #expect(material.material.depthCompareFunction == (frameNumber == 1 ? .greaterEqual : .always))
            #expect(material.material.depthWriteEnabled == (frameNumber == 1))
            let state = try #require(material.material.depthStencilState)
            #expect(state !== previousDepthState, "Changing depth controls rebuilds the GPU depth state")
            previousDepthState = state
        }
    }
}
