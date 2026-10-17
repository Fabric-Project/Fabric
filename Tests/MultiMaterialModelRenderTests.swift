import Testing
import Foundation
@testable import Fabric
import Satin

/// Whether a model with several materials on one mesh draws. ModelIO gives
/// such a mesh a submesh per material, each with its own material for Satin
/// to set up. A model with one material draws first: the encoder only takes a
/// depth stencil state that differs from the last, so a missing one reaches
/// Metal only after a real one.
@Suite("Multi-material model render")
@MainActor
struct MultiMaterialModelRenderTests
{
    private let files = ModelFileFolder()

    @Test("A mesh with a material per submesh draws")
    func aMultiMaterialMeshDraws() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        _ = try files.file(named: "colors.mtl", contents: """
            newmtl Red
            Kd 1 0 0
            newmtl Blue
            Kd 0 0 1
            """)
        let singleMaterialURL = try files.file(named: "single.obj", contents: """
            mtllib colors.mtl
            v 0 0 0
            v 1 0 0
            v 0 1 0
            usemtl Red
            f 1 2 3
            """)
        let twoMaterialURL = try files.file(named: "two.obj", contents: """
            mtllib colors.mtl
            v 0 0 0
            v 1 0 0
            v 0 1 0
            v 1 1 0
            usemtl Red
            f 1 2 3
            usemtl Blue
            f 2 4 3
            """)

        let graph = Graph(context: harness.context)
        let singleMaterialNode = ModelMeshNode(context: harness.context)
        singleMaterialNode.inputFilePathParam.value = singleMaterialURL.path
        let twoMaterialNode = ModelMeshNode(context: harness.context)
        twoMaterialNode.inputFilePathParam.value = twoMaterialURL.path
        twoMaterialNode.inputRenderOrder.value = 1
        graph.addNode(singleMaterialNode)
        graph.addNode(twoMaterialNode)
        try harness.graphRenderer(for: graph).startExecution()

        // The models load in the first frame; the frames after draw them.
        for frameNumber in 0..<3
        {
            try harness.render(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: frameNumber))
        }

        let meshes = try #require(twoMaterialNode.getObject()).getChildren(true).compactMap { $0 as? Mesh }
        #expect(meshes.contains { $0.submeshes.count == 2 })
    }
}
