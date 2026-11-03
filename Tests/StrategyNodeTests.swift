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

    @Test("A saved strategy is typed on decode, and an unknown one resolves to nothing")
    func decodedStrategies() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        func decode(savedStrategy: String) throws -> DecomposeTransformNode
        {
            let node = DecomposeTransformNode(context: harness.context)
            var saved = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as? [String: Any])
            saved["strategy"] = savedStrategy
            let decoder = JSONDecoder()
            decoder.context = DecoderContext(documentContext: harness.context)
            return try decoder.decode(DecomposeTransformNode.self, from: JSONSerialization.data(withJSONObject: saved))
        }

        let columns = try decode(savedStrategy: TransformCompositionMode.columns.rawValue)
        #expect(columns.strategyOption(as: TransformCompositionMode.self) == .columns)

        let unknown = try decode(savedStrategy: "Retired Strategy")
        #expect(unknown.strategy == nil)
        #expect(unknown.subtitle == nil)
        try harness.execute(unknown)

        // Saving keeps the unknown name, so a later build that knows it can still read it.
        let resaved = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(unknown)) as? [String: Any])
        #expect(resaved["strategy"] as? String == "Retired Strategy")
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
