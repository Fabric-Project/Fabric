import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

private func publish(_ port: Fabric.Port, in graph: Graph)
{
    graph.setPublished(true, port: port)
}

@Suite("Consolidated Numeric Nodes")
struct ConsolidatedNumericNodeTests
{
    @Test("Wiring a Float outlet into a virtual numeric node specialises it on connect; an unwired one stays virtual")
    func virtualNodeSpecialisesOnConnect() throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let wired = TweenNode(context: context)
        let unwired = TweenNode(context: context)
        graph.addNode(source)
        graph.addNode(wired)
        graph.addNode(unwired)
        #expect(wired.selectedNumericPortType == .NumericVirtual)

        let target: Fabric.Port = wired.port(named: "inputTarget")
        #expect(target.portType == .NumericVirtual)
        graph.connect(source.outputNumber, to: target)

        // Specialised by the connect itself, before anything executes.
        #expect(wired.selectedNumericPortType == .Float)
        let specialised: Fabric.Port = wired.port(named: "inputTarget")
        #expect(specialised.portType == .Float)
        #expect(specialised.connectedPorts.map(\.id) == [source.outputNumber.id])
        #expect(unwired.selectedNumericPortType == .NumericVirtual)

        // A document saved before the strategy was ever set specialises as its
        // wires come back.
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(graph)) as? [String: Any])
        var nodeMap = try #require(json["nodeMap"] as? [[String: Any]])
        for index in nodeMap.indices
        {
            guard var value = nodeMap[index]["value"] as? [String: Any], value["id"] as? String == wired.id.uuidString else { continue }
            value["strategy"] = "Virtual"
            nodeMap[index]["value"] = value
        }
        json["nodeMap"] = nodeMap
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: JSONSerialization.data(withJSONObject: json))
        let reopened = try #require(decoded.node(forID: wired.id) as? TweenNode)
        #expect(reopened.selectedNumericPortType == .Float)
        #expect((reopened.port(named: "inputTarget") as Fabric.Port).connectedPorts.count == 1)
        #expect((decoded.node(forID: unwired.id) as? TweenNode)?.selectedNumericPortType == .NumericVirtual)
    }

    @Test("Undoing the connect that specialised a virtual numeric node disconnects it and puts it back to virtual; redo does both again")
    func undoOfSpecialisingConnect() throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let tween = TweenNode(context: context)
        graph.addNode(source)
        graph.addNode(tween)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager

        // One user event: the connect, and the strategy step it makes.
        undoManager.beginUndoGrouping()
        graph.connect(source.outputNumber, to: tween.port(named: "inputTarget"))
        undoManager.endUndoGrouping()
        #expect(tween.selectedNumericPortType == .Float)

        undoManager.undo()
        #expect(tween.selectedNumericPortType == .NumericVirtual)
        let target: Fabric.Port = tween.port(named: "inputTarget")
        #expect(target.portType == .NumericVirtual)
        #expect(target.connectedPorts.isEmpty)

        undoManager.redo()
        #expect(tween.selectedNumericPortType == .Float)
        let redone: Fabric.Port = tween.port(named: "inputTarget")
        #expect(redone.portType == .Float)
        #expect(redone.connectedPorts.map(\.id) == [source.outputNumber.id])
    }

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

        try harness.graphRenderer(for: graph).startExecution()
        try harness.execute(graph, checkCommandBufferError: false)
        try harness.graphRenderer(for: graph).stopExecution()

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

        try harness.graphRenderer(for: graph).startExecution()
        try harness.execute(graph, checkCommandBufferError: false)
        try harness.graphRenderer(for: graph).stopExecution()

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

        try harness.graphRenderer(for: graph).startExecution()
        try harness.execute(graph, checkCommandBufferError: false)
        try harness.graphRenderer(for: graph).stopExecution()

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
