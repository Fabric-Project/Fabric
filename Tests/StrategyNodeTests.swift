import Foundation
import simd
import Testing
@testable import Fabric
import Satin

/// A node holds its strategy typed; the strategy's name is only for documents and the picker.
@Suite("Strategy Nodes")
struct StrategyNodeTests
{
    private let transform = simd_float4x4(columns: (simd_float4(1, 0, 0, 0),
                                                    simd_float4(0, 1, 0, 0),
                                                    simd_float4(0, 0, 1, 0),
                                                    simd_float4(2, 3, 4, 1)))

    private func decompose(_ node: DecomposeTransformNode, harness: GraphExecutionTestHarness) throws
    {
        let input: NodePort<simd_float4x4> = try #require(node.findPort(named: "inputTransform"))
        input.value = transform
        try harness.execute(node)
    }

    @Test("Changing strategy changes what execute does")
    func changingStrategyChangesExecution() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = DecomposeTransformNode(context: harness.context, strategy: TransformCompositionMode.columns)
        #expect(node.strategyOption(as: TransformCompositionMode.self) == .columns)

        try decompose(node, harness: harness)
        let column3: NodePort<simd_float4> = try #require(node.findPort(named: "outputColumn3"))
        #expect(column3.value == simd_float4(2, 3, 4, 1))

        node.setStrategy(TransformCompositionMode.trs)
        #expect(node.strategyOption(as: TransformCompositionMode.self) == .trs)

        try decompose(node, harness: harness)
        let translation: NodePort<simd_float3> = try #require(node.findPort(named: "outputTranslation"))
        #expect(translation.value == simd_float3(2, 3, 4))
    }

    @Test("Undo restores the previous typed strategy")
    func undoRestoresTypedStrategy() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let graph = Graph(context: harness.context)
        let node = DecomposeTransformNode(context: harness.context, strategy: TransformCompositionMode.columns)
        graph.addNode(node)
        let undoManager = UndoManager()
        graph.undoManager = undoManager

        node.setStrategy(TransformCompositionMode.trs)
        undoManager.undo()

        #expect(node.strategyOption(as: TransformCompositionMode.self) == .columns)
        try decompose(node, harness: harness)
        let column3: NodePort<simd_float4> = try #require(node.findPort(named: "outputColumn3"))
        #expect(column3.value == simd_float4(2, 3, 4, 1))
    }

    /// A Decompose Transform node as a document that saved `savedStrategy` loads it.
    private func decode(savedStrategy: String, harness: GraphExecutionTestHarness) throws -> DecomposeTransformNode
    {
        let node = DecomposeTransformNode(context: harness.context)
        var saved = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as? [String: Any])
        saved["strategy"] = savedStrategy
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context)
        return try decoder.decode(DecomposeTransformNode.self, from: JSONSerialization.data(withJSONObject: saved))
    }

    private func savedStrategy(of node: StrategyNode) throws -> String?
    {
        let saved = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as? [String: Any])
        return saved["strategy"] as? String
    }

    @Test("A saved strategy is typed on decode, and an unknown one resolves to nothing")
    func decodedStrategies() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let columns = try decode(savedStrategy: TransformCompositionMode.columns.rawValue, harness: harness)
        #expect(columns.strategyOption(as: TransformCompositionMode.self) == .columns)

        let unknown = try decode(savedStrategy: "Retired Strategy", harness: harness)
        #expect(unknown.strategy == nil)
        #expect(unknown.subtitle == nil)
        try harness.execute(unknown)

        // Saving keeps the unknown name, so a later build that knows it can still read it.
        #expect(try savedStrategy(of: unknown) == "Retired Strategy")
    }

    @Test("Undo after leaving an unknown saved strategy restores its name")
    func undoRestoresUnknownName() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let graph = Graph(context: harness.context)
        let node = try decode(savedStrategy: "Retired Strategy", harness: harness)
        graph.addNode(node)
        let undoManager = UndoManager()
        graph.undoManager = undoManager

        node.setStrategy(TransformCompositionMode.trs)
        #expect(try savedStrategy(of: node) == TransformCompositionMode.trs.rawValue)

        undoManager.undo()
        #expect(node.strategy == nil)
        #expect(try savedStrategy(of: node) == "Retired Strategy")
    }

    @Test("A strategy of another type that names one of the node's options resolves to that option")
    func strategiesResolveToTheNodesOwnOptions() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        // PortType.Vector3 and VectorType.float3 share the name "Vector 3".
        let constructed = ComposeVectorNode(context: harness.context, strategy: PortType.Vector3)
        #expect(constructed.strategyOption(as: VectorType.self) == .float3)
        #expect(constructed.findPort(named: "inputComponent2") as Fabric.Port? != nil)

        let assigned = ComposeVectorNode(context: harness.context, vectorType: .float2)
        assigned.setStrategy(PortType.Vector4)
        #expect(assigned.strategyOption(as: VectorType.self) == .float4)
        #expect(assigned.findPort(named: "inputComponent3") as Fabric.Port? != nil)
    }

    @Test("Numeric type-agnostic nodes read their port type from the typed strategy")
    func numericPortTypeFollowsStrategy() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let easing = EasingNode(context: harness.context)
        #expect(easing.selectedNumericPortType == .NumericVirtual)

        easing.setStrategy(NumericPortStrategy.concrete(.Color))
        #expect(easing.selectedNumericPortType == .Color)
    }
}
