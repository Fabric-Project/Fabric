import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

private func publish(_ port: Fabric.Port, in graph: Graph)
{
    port.published = true
    graph.rebuildPublishedParameterGroup()
}

@Suite("Consolidated Numeric Nodes")
struct ConsolidatedNumericNodeTests
{
    @Test("Distance computes corrected Euclidean vector distance")
    func distanceComputesVectorDistance() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let distance = DistanceNode(context: harness.context, portType: .Vector3)
        let inputA: NodePort<simd_float3> = distance.port(named: "inputA")
        let inputB: NodePort<simd_float3> = distance.port(named: "inputB")
        inputA.value = simd_float3(0, 0, 0)
        inputB.value = simd_float3(3, 4, 0)

        graph.addNode(distance)
        publish(distance.outputDistance, in: graph)

        try harness.renderer.startExecution(graph: graph)
        try harness.execute(graph, checkCommandBufferError: false)
        try harness.renderer.stopExecution(graph: graph)

        #expect(distance.outputDistance.value == 5)
    }

    @Test("Pairwise Distance Array uses zip-shortest")
    func pairwiseDistanceArrayUsesZipShortest() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let distance = PairwiseDistanceArrayNode(context: harness.context, portType: .Array(portType: .Float))
        let inputA: NodePort<ContiguousArray<Float>> = distance.port(named: "inputA")
        let inputB: NodePort<ContiguousArray<Float>> = distance.port(named: "inputB")
        inputA.value = [1, 5, 9]
        inputB.value = [4, 1]

        graph.addNode(distance)
        publish(distance.outputDistances, in: graph)

        try harness.renderer.startExecution(graph: graph)
        try harness.execute(graph, checkCommandBufferError: false)
        try harness.renderer.stopExecution(graph: graph)

        #expect(distance.outputDistances.value == [3, 4])
    }

    @Test("Array Resample interpolates arrays")
    func arrayResampleInterpolates() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let resample = ArrayResampleTypeAgnosticNode(context: harness.context, portType: .Array(portType: .Float))
        let inputArray: NodePort<ContiguousArray<Float>> = resample.port(named: "inputArray")
        let outputArray: NodePort<ContiguousArray<Float>> = resample.port(named: "outputArray")
        inputArray.value = [0, 10]
        resample.inputCount.value = 3

        graph.addNode(resample)
        publish(outputArray, in: graph)

        try harness.renderer.startExecution(graph: graph)
        try harness.execute(graph, checkCommandBufferError: false)
        try harness.renderer.stopExecution(graph: graph)

        #expect(outputArray.value == [0, 5, 10])
    }

    @Test("Concrete numeric strategy nodes expose editable value inputs")
    func concreteStrategyNodesExposeEditableInputs() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let easing = EasingNode(context: harness.context, portType: .Color)
        #expect((easing.port(named: "inputFrom") as NodePort<simd_float4>) is ParameterPort<simd_float4>)
        #expect((easing.port(named: "inputTo") as NodePort<simd_float4>) is ParameterPort<simd_float4>)

        let tween = TweenNode(context: harness.context, portType: .Vector3)
        #expect((tween.port(named: "inputTarget") as NodePort<simd_float3>) is ParameterPort<simd_float3>)

        let distance = DistanceNode(context: harness.context, portType: .Float)
        #expect((distance.port(named: "inputA") as NodePort<Float>) is ParameterPort<Float>)
        #expect((distance.port(named: "inputB") as NodePort<Float>) is ParameterPort<Float>)
    }

    @Test("Ripple Repeat and Array Range Interpolate expose editable concrete inputs")
    func rippleAndRangeExposeEditableConcreteInputs() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let ripple = RippleRepeatNode(context: harness.context, portType: .Vector2)
        #expect((ripple.port(named: "inputValue") as NodePort<simd_float2>) is ParameterPort<simd_float2>)

        let range = ArrayRangeInterpolateNode(context: harness.context, portType: .Color)
        #expect((range.port(named: "inputFrom") as NodePort<simd_float4>) is ParameterPort<simd_float4>)
        #expect((range.port(named: "inputTo") as NodePort<simd_float4>) is ParameterPort<simd_float4>)
    }
}
