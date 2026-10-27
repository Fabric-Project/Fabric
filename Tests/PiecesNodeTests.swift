@testable import Fabric
import Metal
import Satin
import simd
import Testing

/// Transform Pieces and Piece Info on hand-built pieces: one top-level piece holding two
/// children, over 12 vertices.
@Suite("Pieces Nodes")
struct PiecesNodeTests
{
    private static func makeTwoGenerationGeometry(context: Context) throws -> Geometry
    {
        let geometry = Geometry(context: context)
        geometry.addAttribute(Float3BufferAttribute(defaultValue: .zero, data: Array(repeating: .zero, count: 12)), for: .Position)
        try geometry.setPieces(GeometryPieces(parentIndices: [-1, 0, 0],
                                              centers: [SIMD3(1, 0, 0), SIMD3(0.5, 0, 0), SIMD3(1.5, 0, 0)],
                                              sizes: [3, 1, 2],
                                              sizeMeasure: .volume,
                                              vertexRanges: [0 ..< 12, 0 ..< 6, 6 ..< 12]))
        return geometry
    }

    @Test("Composed transforms carry each parent's motion to its children, three generations deep")
    func composedTransformsFollowTheHierarchy() throws
    {
        let pieces = try GeometryPieces(parentIndices: [-1, 0, 1, 1], centers: Array(repeating: .zero, count: 4), sizes: [3, 3, 1, 2],
                                        sizeMeasure: .volume, vertexRanges: [0 ..< 6, 0 ..< 6, 0 ..< 3, 3 ..< 6])
        let root = simd_float4x4(translation: SIMD3(1, 0, 0))
        let middle = simd_float4x4(scale: SIMD3(repeating: 2))
        let leaf = simd_float4x4(translation: SIMD3(0, 1, 0))
        #expect(pieces.generations == [0, 1, 2, 2])
        #expect(pieces.composedTransforms([root, middle, leaf, matrix_identity_float4x4]) == [root, root * middle, root * middle * leaf, root * middle])
        // A short array moves only the pieces it covers, and their children with them; extras are ignored.
        #expect(pieces.composedTransforms([root]) == [root, root, root, root])
        #expect(pieces.composedTransforms(Array(repeating: root, count: 9)).count == 4)
    }

    @Test("Piece Info reports every generation, parents first")
    func pieceInfoReportsTheHierarchy() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let node = PieceInfoNode(context: harness.context)
        node.inputGeometry.value = try Self.makeTwoGenerationGeometry(context: harness.context)
        try harness.execute(node)

        #expect(node.outputPieceCount.value == 3)
        #expect(node.outputCenters.value == [SIMD3(1, 0, 0), SIMD3(0.5, 0, 0), SIMD3(1.5, 0, 0)])
        #expect(node.outputVolumes.value == [3, 1, 2])
        #expect(node.outputParentIndices.value == [-1, 0, 0])
        #expect(node.outputGenerations.value == [0, 1, 1])
    }

    @Test("Piece Info reports nothing for geometry without pieces")
    func pieceInfoWithoutPieces() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let node = PieceInfoNode(context: harness.context)
        node.inputGeometry.value = Geometry(context: harness.context)
        try harness.execute(node)

        #expect(node.outputPieceCount.value == 0)
        #expect(node.outputCenters.value == [])
        #expect(node.deriveStatuses().isEmpty == false)
    }

    @Test("Piece Info reports no volume for flat pieces")
    func pieceInfoFlatPiecesHaveNoVolume() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let geometry = Geometry(context: harness.context)
        geometry.addAttribute(Float3BufferAttribute(defaultValue: .zero, data: Array(repeating: .zero, count: 6)), for: .Position)
        try geometry.setPieces(GeometryPieces(parentIndices: [-1, -1], centers: [.zero, .zero], sizes: [2, 5],
                                              sizeMeasure: .area, vertexRanges: [0 ..< 3, 3 ..< 6]))
        let node = PieceInfoNode(context: harness.context)
        node.inputGeometry.value = geometry
        try harness.execute(node)

        #expect(node.outputVolumes.value == [0, 0])
    }

    @Test("Transform Pieces moves each child with its parent's transform, then its own")
    func transformPiecesComposesParents() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let geometry = try Self.makeTwoGenerationGeometry(context: harness.context)
        let node = TransformPiecesNode(context: harness.context)
        node.inputGeometry.value = geometry
        let parentMotion = simd_float4x4(translation: SIMD3(0, 2, 0))
        let childMotion = simd_float4x4(translation: SIMD3(1, 0, 0))
        // A short array from earlier in a chain would cover the parent alone; here the second child has its own.
        node.inputTransforms.value = [parentMotion, matrix_identity_float4x4, childMotion]
        try harness.execute(node)

        let posed = try #require(node.outputGeometry.value)
        #expect(posed !== geometry, "The output is a posed view of the input")
        let palette = try #require(posed.jointPalette)
        #expect(palette.jointCount == 3)
        #expect(palette.matrices == [parentMotion, parentMotion, parentMotion * childMotion])
        #expect(node.deriveStatuses().isEmpty)
    }

    @Test("Transform Pieces passes geometry without pieces through, with a warning")
    func transformPiecesPassesPlainGeometryThrough() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let geometry = Geometry(context: harness.context)
        let node = TransformPiecesNode(context: harness.context)
        node.inputGeometry.value = geometry
        try harness.execute(node)

        #expect(node.outputGeometry.value === geometry)
        #expect(node.deriveStatuses().isEmpty == false)
    }
}
