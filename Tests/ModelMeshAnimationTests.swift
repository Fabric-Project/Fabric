import Testing
import Foundation
import simd
@testable import Fabric
import Satin

/// Model Mesh and Instanced Model Mesh playing an animated model at Time, with Satin's CC0
/// gyroscope (skinned). Skipped when the Satin submodule's example assets are absent.
@Suite("Model Mesh Animation", .serialized)
struct ModelMeshAnimationTests
{
    private static let modelPath = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../Satin/Example/Assets/Shared/Models/Magical_gyroscope.usdz")
        .standardizedFileURL
        .path(percentEncoded: false)

    private static var modelExists: Bool { FileManager.default.fileExists(atPath: modelPath) }

    private func meshWorldMatrices(_ object: Object?) -> [simd_float4x4]
    {
        (object?.getChildren(true) ?? []).compactMap { $0 as? Mesh }.map(\.worldMatrix)
    }

    /// How the model's skins are posed: each skinned mesh's joint matrices, in mesh order.
    private func jointMatrices(_ object: Object?) -> [simd_float4x4]
    {
        (object?.getChildren(true) ?? []).compactMap { $0 as? Mesh }.flatMap { $0.geometry?.jointPalette?.joints.map(\.current) ?? [] }
    }

    private func isClose(_ a: simd_float4x4, _ b: simd_float4x4, tolerance: Float = 1e-4) -> Bool
    {
        (0 ..< 4).allSatisfy { simd_reduce_max(simd_abs(a[$0] - b[$0])) < tolerance }
    }

    @Test("Time moves an animated model and Duration reports its length", .enabled(if: modelExists))
    func timeMovesTheModel() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let node = ModelMeshNode(context: harness.context)
        node.inputFilePathParam.value = Self.modelPath
        try harness.execute(node)

        let duration = try #require(node.outputDuration.value)
        #expect(duration > 0)
        let start = meshWorldMatrices(node.getObject()) + jointMatrices(node.getObject())
        #expect(start.isEmpty == false)

        node.markClean()
        node.inputTime.value = duration / 2
        try harness.execute(node)
        let middle = meshWorldMatrices(node.getObject()) + jointMatrices(node.getObject())

        #expect(middle.count == start.count)
        #expect(zip(start, middle).contains { isClose($0, $1) == false }, "Some part or joint moved")
    }

    @Test("Instanced parts follow the model's parts at any Time", .enabled(if: modelExists))
    func instancedPartsMatchTheModel() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let model = ModelMeshNode(context: harness.context)
        let instanced = InstancedModelMeshNode(context: harness.context)
        for time: Float in [0, 0.5]
        {
            model.inputFilePathParam.value = Self.modelPath
            instanced.inputFilePathParam.value = Self.modelPath
            model.inputTime.value = time
            instanced.inputTime.value = time
            try harness.execute(model)
            try harness.execute(instanced)
            model.markClean()
            instanced.markClean()

            let parts = meshWorldMatrices(model.getObject())
            // One instance at identity, so each instance draws where its part does. Updating, as
            // a frame does, picks up the pose's moves.
            let instances = (instanced.getObject()?.getChildren(true) ?? []).compactMap { $0 as? InstancedMesh }
                .map { instancedMesh in
                    instancedMesh.update()
                    return instancedMesh.getWorldMatrixAt(index: 0)
                }

            #expect(instances.count == parts.count, "time \(time)")
            #expect(zip(parts, instances).allSatisfy { isClose($0, $1) }, "time \(time)")

            // Each instanced mesh is posed as the plain one: its skin's palette is the same.
            let modelJoints = jointMatrices(model.getObject())
            let instancedJoints = jointMatrices(instanced.getObject())
            #expect(instancedJoints.count == modelJoints.count, "time \(time)")
            #expect(zip(modelJoints, instancedJoints).allSatisfy { isClose($0, $1) }, "time \(time)")
        }
    }

    @Test("An instance transform moves the whole model, its parts in place", .enabled(if: modelExists))
    func instanceTransformMovesTheWholeModel() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let model = ModelMeshNode(context: harness.context)
        let instanced = InstancedModelMeshNode(context: harness.context)
        model.inputFilePathParam.value = Self.modelPath
        instanced.inputFilePathParam.value = Self.modelPath
        let move = simd_float4x4(translation: [5, 0, 0])
        instanced.inputTransforms.value = [move]
        try harness.execute(model)
        try harness.execute(instanced)

        let parts = meshWorldMatrices(model.getObject())
        let instances = (instanced.getObject()?.getChildren(true) ?? []).compactMap { $0 as? InstancedMesh }
            .map { instancedMesh in
                instancedMesh.update()
                return instancedMesh.getWorldMatrixAt(index: 0)
            }

        // Both models sit at the origin, so moving the model is moving each part in world space.
        #expect(instances.count == parts.count)
        #expect(zip(parts, instances).allSatisfy { isClose(move * $0, $1) })
    }
}
