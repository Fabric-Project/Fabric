import Foundation
import Metal
import Satin
import Testing
@testable import Fabric

@Suite("Image Mesh")
struct ImageMeshNodeTests {
    @Test("Defaults blend with alpha, depth test and show both sides")
    func defaults() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let imageMesh = ImageMeshNode(context: harness.context)
        let graph = Graph(context: harness.context)
        graph.addNode(imageMesh)

        try harness.graphRenderer(for: graph).startExecution()
        try harness.render(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: false)

        let mesh = try #require(imageMesh.object)
        let material = try #require(mesh.material)
        #expect(material.blending == .alpha)
        #expect(material.depthWriteEnabled)
        #expect(material.depthCompareFunction == .greaterEqual)
        #expect(mesh.doubleSided)
        #expect(!mesh.castShadow)
        #expect(!mesh.receiveShadow)
    }

    @Test("Material and mesh inlets reach the rendered mesh")
    func inletsApplyToMeshAndMaterial() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let imageMesh = ImageMeshNode(context: harness.context)
        let graph = Graph(context: harness.context)
        graph.addNode(imageMesh)

        imageMesh.inputBlending.value = "Additive"
        imageMesh.inputWriteDepth.value = false
        imageMesh.inputDepthTest.value = false
        imageMesh.inputDoubleSided.value = false
        imageMesh.inputCastsShadow.value = true

        try harness.graphRenderer(for: graph).startExecution()
        try harness.render(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: false)

        let mesh = try #require(imageMesh.object)
        let material = try #require(mesh.material)
        #expect(material.blending == .additive)
        #expect(!material.depthWriteEnabled)
        #expect(material.depthCompareFunction == .always)
        #expect(!mesh.doubleSided)
        #expect(mesh.castShadow)
        #expect(mesh.receiveShadow)
    }
}
