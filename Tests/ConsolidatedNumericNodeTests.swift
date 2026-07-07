import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

private struct ConsolidatedNumericHarness
{
    let context: Context
    let renderer: GraphRenderer

    init?()
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
        self.renderer = GraphRenderer(context: context)
        self.renderer.resize(size: (width: 64, height: 64), scaleFactor: 1)
    }

    func executionInfo(time: TimeInterval = 0, frameNumber: Int = 0) -> GraphExecutionInfo
    {
        GraphExecutionInfo(
            timing: GraphExecutionTiming(
                time: time,
                deltaTime: 0,
                displayTime: time,
                systemTime: time,
                frameNumber: frameNumber
            )
        )
    }

    func execute(_ graph: Graph, executionInfo: GraphExecutionInfo? = nil) throws
    {
        let descriptor = MTLRenderPassDescriptor()
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.colorPixelFormat,
            width: 64,
            height: 64,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        descriptor.colorAttachments[0].texture = context.device.makeTexture(descriptor: textureDescriptor)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            throw ConsolidatedNumericTestFailure("Failed to create command buffer")
        }

        renderer.execute(
            graph: graph,
            executionInfo: executionInfo ?? self.executionInfo(),
            renderPassDescriptor: descriptor,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

private struct ConsolidatedNumericTestFailure: Error, CustomStringConvertible
{
    let description: String
    init(_ description: String) { self.description = description }
}

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
        guard let harness = ConsolidatedNumericHarness() else { return }

        let graph = Graph(context: harness.context)
        let distance = DistanceNode(context: harness.context, portType: .Vector3)
        let inputA: NodePort<simd_float3> = distance.port(named: "inputA")
        let inputB: NodePort<simd_float3> = distance.port(named: "inputB")
        inputA.value = simd_float3(0, 0, 0)
        inputB.value = simd_float3(3, 4, 0)

        graph.addNode(distance)
        publish(distance.outputDistance, in: graph)

        harness.renderer.startExecution(graph: graph)
        try harness.execute(graph)
        harness.renderer.stopExecution(graph: graph)

        #expect(distance.outputDistance.value == 5)
    }

    @Test("Pairwise Distance Array uses zip-shortest")
    func pairwiseDistanceArrayUsesZipShortest() throws
    {
        guard let harness = ConsolidatedNumericHarness() else { return }

        let graph = Graph(context: harness.context)
        let distance = PairwiseDistanceArrayNode(context: harness.context, portType: .Array(portType: .Float))
        let inputA: NodePort<ContiguousArray<Float>> = distance.port(named: "inputA")
        let inputB: NodePort<ContiguousArray<Float>> = distance.port(named: "inputB")
        inputA.value = [1, 5, 9]
        inputB.value = [4, 1]

        graph.addNode(distance)
        publish(distance.outputDistances, in: graph)

        harness.renderer.startExecution(graph: graph)
        try harness.execute(graph)
        harness.renderer.stopExecution(graph: graph)

        #expect(distance.outputDistances.value == [3, 4])
    }

    @Test("Array Resample interpolates arrays")
    func arrayResampleInterpolates() throws
    {
        guard let harness = ConsolidatedNumericHarness() else { return }

        let graph = Graph(context: harness.context)
        let resample = ArrayResampleTypeAgnosticNode(context: harness.context, portType: .Array(portType: .Float))
        let inputArray: NodePort<ContiguousArray<Float>> = resample.port(named: "inputArray")
        let outputArray: NodePort<ContiguousArray<Float>> = resample.port(named: "outputArray")
        inputArray.value = [0, 10]
        resample.inputCount.value = 3

        graph.addNode(resample)
        publish(outputArray, in: graph)

        harness.renderer.startExecution(graph: graph)
        try harness.execute(graph)
        harness.renderer.stopExecution(graph: graph)

        #expect(outputArray.value == [0, 5, 10])
    }

    @Test("Concrete numeric strategy nodes expose editable value inputs")
    func concreteStrategyNodesExposeEditableInputs() throws
    {
        guard let harness = ConsolidatedNumericHarness() else { return }

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
        guard let harness = ConsolidatedNumericHarness() else { return }

        let ripple = RippleRepeatNode(context: harness.context, portType: .Vector2)
        #expect((ripple.port(named: "inputValue") as NodePort<simd_float2>) is ParameterPort<simd_float2>)

        let range = ArrayRangeInterpolateNode(context: harness.context, portType: .Color)
        #expect((range.port(named: "inputFrom") as NodePort<simd_float4>) is ParameterPort<simd_float4>)
        #expect((range.port(named: "inputTo") as NodePort<simd_float4>) is ParameterPort<simd_float4>)
    }
}
