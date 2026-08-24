import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// Verifies the trigger contract end-to-end: a Pulse driving a Number Generator
/// should yield one new value per pulse period. Drives the graph through the
/// renderer (not the node in isolation) so the pull-based execution path is
/// exercised, with the generator's output published so it is an evaluation root.
@Suite("Number Generator + Pulse")
struct NumberGeneratorPulseTests
{
    private func publish(_ port: Fabric.Port, in graph: Graph)
    {
        port.published = true
        graph.rebuildPublishedParameterGroup()
    }

    @Test("Number Generator emits one new value per Pulse period")
    func generatorFiresOncePerPulsePeriod() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)

        let pulse = NumberPulseNode(context: harness.context)
        pulse.inputPeriod.value = 1.0 // one pulse per second

        let generator = NumberGeneratorNode(context: harness.context, strategy: NumberGeneratorMode.random)

        graph.addNode(pulse)
        graph.addNode(generator)

        guard let generatorSignal = generator.findPort(named: "inputSignal", as: ParameterPort<Bool>.self) else {
            throw GraphExecutionTestFailure("Number Generator has no inputSignal port")
        }
        guard let generatorOutput = generator.findPort(named: "outputValue", as: NodePort<Float>.self) else {
            throw GraphExecutionTestFailure("Number Generator has no outputValue port")
        }

        graph.connect(pulse.outputSignal, to: generatorSignal)
        graph.markConnectionsChanged()

        // Publishing the output makes the generator an evaluation root, so the
        // renderer pulls (and evaluates) it every frame — the same condition as
        // being wired into a live consumer.
        publish(generatorOutput, in: graph)

        try harness.renderer.startExecution(graph: graph)

        // 35 frames at dt = 0.1s spans 3.4 periods → pulses at t≈1,2,3 (three).
        let deltaTime = 0.1
        let frameCount = 35
        var values: [Float] = []
        for frame in 0 ..< frameCount {
            let info = harness.makeExecutionContext(
                time: Double(frame) * deltaTime,
                deltaTime: deltaTime,
                frameNumber: frame
            )
            try harness.execute(graph: graph, executionInfo: info, drawScene: false, checkCommandBufferError: false)
            if let value = generatorOutput.value { values.append(value) }
        }

        try harness.renderer.stopExecution(graph: graph)

        // Each pulse rising edge should produce a new (random) value, so the
        // output changes exactly three times over three periods.
        var changes = 0
        for index in 1 ..< values.count where values[index] != values[index - 1] {
            changes += 1
        }

        #expect(changes == 3, "expected 3 new numbers over 3 pulse periods, got \(changes); values = \(values)")
    }

    @Test("Number Generator is never evaluated when nothing pulls it")
    func generatorRequiresAPullPath() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)

        let pulse = NumberPulseNode(context: harness.context)
        pulse.inputPeriod.value = 1.0

        let generator = NumberGeneratorNode(context: harness.context, strategy: NumberGeneratorMode.random)

        graph.addNode(pulse)
        graph.addNode(generator)

        guard let generatorSignal = generator.findPort(named: "inputSignal", as: ParameterPort<Bool>.self),
              let generatorOutput = generator.findPort(named: "outputValue", as: NodePort<Float>.self)
        else {
            throw GraphExecutionTestFailure("Number Generator missing ports")
        }

        graph.connect(pulse.outputSignal, to: generatorSignal)
        graph.markConnectionsChanged()

        // Deliberately NOT published and not consumed: the generator is not an
        // evaluation root and not upstream of one, so the pull-based renderer
        // never reaches it — reproducing "fires once / never" seen when a node
        // is only inspected, not wired into a live output.
        try harness.renderer.startExecution(graph: graph)

        var emitted = false
        for frame in 0 ..< 35 {
            let info = harness.makeExecutionContext(time: Double(frame) * 0.1, deltaTime: 0.1, frameNumber: frame)
            try harness.execute(graph: graph, executionInfo: info, drawScene: false, checkCommandBufferError: false)
            if generatorOutput.value != nil { emitted = true }
        }

        try harness.renderer.stopExecution(graph: graph)

        #expect(emitted == false, "generator should never emit when nothing pulls it")
    }

    // Builds a fresh Pulse → Number Generator graph (output published so it is an
    // evaluation root) with its own renderer, ready to drive by the live path.
    private func makePulseGeneratorGraph(_ harness: GraphExecutionTestHarness) throws
        -> (graph: Graph, renderer: GraphRenderer, output: NodePort<Float>)
    {
        let graph = Graph(context: harness.context)
        let pulse = NumberPulseNode(context: harness.context)
        pulse.inputPeriod.value = 1.0
        let generator = NumberGeneratorNode(context: harness.context, strategy: NumberGeneratorMode.random)
        graph.addNode(pulse)
        graph.addNode(generator)

        guard let signal = generator.findPort(named: "inputSignal", as: ParameterPort<Bool>.self),
              let output = generator.findPort(named: "outputValue", as: NodePort<Float>.self)
        else { throw GraphExecutionTestFailure("Number Generator missing ports") }

        graph.connect(pulse.outputSignal, to: signal)
        graph.markConnectionsChanged()
        output.published = true
        graph.rebuildPublishedParameterGroup()
        graph.updateRenderingNodes()

        let renderer = GraphRenderer(context: harness.context, graph: graph)
        renderer.resize(size: (width: Float(harness.renderWidth), height: Float(harness.renderHeight)), scaleFactor: 1.0)
        return (graph, renderer, output)
    }

    private func renderOnce(_ renderer: GraphRenderer, _ harness: GraphExecutionTestHarness,
                            _ body: (MTLRenderPassDescriptor, MTLCommandBuffer) throws -> Void) throws
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: harness.context.colorPixelFormat, width: harness.renderWidth, height: harness.renderHeight, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = harness.context.device.makeTexture(descriptor: descriptor),
              let commandBuffer = renderer.commandQueue.makeCommandBuffer()
        else { throw GraphExecutionTestFailure("Failed to make render target / command buffer") }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        try body(rpd, commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func countChanges(_ values: [Float]) -> Int
    {
        var changes = 0
        for index in 1 ..< values.count where values[index] != values[index - 1] { changes += 1 }
        return changes
    }

    // Regression guard for the deferred-scheduling bug (Toby's differences between
    // the update/draw path and a manual execute(graph:), fixed by folding both into
    // one execution strategy). Drives the graph through the *live* update/draw path
    // — planFrame() to set deterministic timing, then draw() to execute — and asserts
    // the generator still fires once per pulse period. If the update/draw path ever
    // re-decouples the dirty check from execution, the edge is missed and this fails.
    @Test("Live update/draw path fires the generator once per pulse period")
    func liveUpdateDrawPathFiresPerPeriod() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let deltaTime = 0.1
        let frameCount = 35 // 3.4 pulse periods at period 1.0

        let live = try makePulseGeneratorGraph(harness)
        try live.renderer.startExecution(graph: live.graph)
        var values: [Float] = []
        for frame in 0 ..< frameCount {
            let info = harness.makeExecutionContext(time: Double(frame) * deltaTime, deltaTime: deltaTime, frameNumber: frame)
            try renderOnce(live.renderer, harness) { rpd, cb in
                live.renderer.planFrame(executionInfo: info)
                try live.renderer.draw(renderPassDescriptor: rpd, commandBuffer: cb)
            }
            values.append(live.output.value ?? .nan)
        }
        try live.renderer.stopExecution(graph: live.graph)

        let changes = countChanges(values)
        #expect(changes == 3, "expected 3 new numbers over 3 pulse periods on the update/draw path, got \(changes); values = \(values)")
    }

    // Drives a Pulse → Number Generator (mode) graph through the renderer and
    // returns the value emitted each frame. Period 1.0 at dt 0.1 puts the first
    // rising edge at frame 9, so `values[0]` is the pre-trigger seed and a change
    // appears once the first pulse lands.
    private func driveNumberGenerator(_ harness: GraphExecutionTestHarness,
                                      mode: NumberGeneratorMode,
                                      frames: Int = 12,
                                      deltaTime: Double = 0.1) throws -> [Float]
    {
        let graph = Graph(context: harness.context)
        let pulse = NumberPulseNode(context: harness.context)
        pulse.inputPeriod.value = 1.0
        let generator = NumberGeneratorNode(context: harness.context, strategy: mode)
        graph.addNode(pulse)
        graph.addNode(generator)

        guard let signal = generator.findPort(named: "inputSignal", as: ParameterPort<Bool>.self),
              let output = generator.findPort(named: "outputValue", as: NodePort<Float>.self)
        else { throw GraphExecutionTestFailure("Number Generator missing ports") }

        graph.connect(pulse.outputSignal, to: signal)
        graph.markConnectionsChanged()
        publish(output, in: graph)

        try harness.renderer.startExecution(graph: graph)
        var values: [Float] = []
        for frame in 0 ..< frames {
            let info = harness.makeExecutionContext(time: Double(frame) * deltaTime, deltaTime: deltaTime, frameNumber: frame)
            try harness.execute(graph: graph, executionInfo: info, drawScene: false, checkCommandBufferError: false)
            if let value = output.value { values.append(value) }
        }
        try harness.renderer.stopExecution(graph: graph)
        return values
    }

    // Verifies the seed/advance contract shared by findings 4 and 9: every mode
    // emits a well-formed first value (no mode is the degenerate 0 outlier), and
    // the first pulse produces a change rather than a dead repeat of the seed.
    @Test("Every generator mode seeds an in-range first value and advances on the first pulse")
    func generatorsSeedInRangeAndAdvanceOnFirstPulse() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        // Number Generator — all three modes: valid seed, then a change on the first pulse.
        for mode in NumberGeneratorMode.allCases {
            let values = try driveNumberGenerator(harness, mode: mode)
            let seed = try #require(values.first, "\(mode.rawValue) emitted no value")
            #expect(seed >= 0 && seed <= 1, "\(mode.rawValue) seed \(seed) is outside [0, 1]")
            #expect(values.contains { $0 != seed }, "\(mode.rawValue) never changed after the first pulse; values = \(values)")
        }

        // Sharper guard for the Random seed (finding 9): it must be a real draw,
        // not the fixed 0 it used to be — independent instances should differ.
        let randomSeeds = try (0 ..< 6).map { _ -> Float in
            try #require(driveNumberGenerator(harness, mode: .random, frames: 1).first)
        }
        #expect(Set(randomSeeds).count > 1, "Random seed looks fixed rather than drawn: \(randomSeeds)")

        // Index Generator, Sequential (finding 4): the seed shows index 0 and the
        // first pulse must advance to 1, not re-emit 0.
        let indices = try driveSequentialIndexGenerator(harness)
        let indexSeed = try #require(indices.first, "Index Generator emitted no value")
        #expect(indexSeed == 0, "Sequential seed should be index 0; got \(indexSeed)")
        let firstChange = indices.first { $0 != indexSeed }
        #expect(firstChange == 1, "Sequential first pulse should advance 0 → 1; values = \(indices)")
    }

    // Pulse → Index Generator in Sequential mode; returns the index emitted each
    // frame (seed at frame 0, first advance at the frame-9 pulse).
    private func driveSequentialIndexGenerator(_ harness: GraphExecutionTestHarness,
                                               frames: Int = 12,
                                               deltaTime: Double = 0.1) throws -> [Int]
    {
        let graph = Graph(context: harness.context)
        let pulse = NumberPulseNode(context: harness.context)
        pulse.inputPeriod.value = 1.0
        let generator = NumberIndexGeneratorNode(context: harness.context, strategy: IndexGeneratorMode.sequential)
        generator.inputSize.value = 8
        generator.inputLoop?.value = true
        graph.addNode(pulse)
        graph.addNode(generator)

        graph.connect(pulse.outputSignal, to: generator.inputSignal)
        graph.markConnectionsChanged()
        publish(generator.outputIndex, in: graph)

        try harness.renderer.startExecution(graph: graph)
        var values: [Int] = []
        for frame in 0 ..< frames {
            let info = harness.makeExecutionContext(time: Double(frame) * deltaTime, deltaTime: deltaTime, frameNumber: frame)
            try harness.execute(graph: graph, executionInfo: info, drawScene: false, checkCommandBufferError: false)
            if let value = generator.outputIndex.value { values.append(value) }
        }
        try harness.renderer.stopExecution(graph: graph)
        return values
    }

    // Finding 1: shrinking Size below the held index must re-emit the clamped
    // index, or downstream keeps reading an index that is now out of range.
    @Test("Index Generator re-emits a clamped index when Size shrinks between pulses")
    func indexGeneratorReEmitsClampedIndexOnSizeShrink() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let generator = NumberIndexGeneratorNode(context: harness.context, strategy: IndexGeneratorMode.sequential) // deterministic advance
        generator.inputSize.value = 10
        generator.inputLoop?.value = true
        graph.addNode(generator)

        // Published so the generator is an evaluation root, pulled every frame.
        publish(generator.outputIndex, in: graph)

        try harness.renderer.startExecution(graph: graph)

        var frame = 0
        func step() throws {
            let info = harness.makeExecutionContext(time: Double(frame) * 0.1, deltaTime: 0.1, frameNumber: frame)
            try harness.execute(graph: graph, executionInfo: info, drawScene: false, checkCommandBufferError: false)
            frame += 1
        }

        try step() // seed: index 0

        // Drive five rising edges (false → true) by hand to advance Sequential to 5.
        for _ in 0 ..< 5 {
            generator.inputSignal.value = true
            try step()
            generator.inputSignal.value = false
            try step()
        }
        #expect(generator.outputIndex.value == 5, "expected index 5 after five pulses; got \(String(describing: generator.outputIndex.value))")

        // Shrink Size below the held index, with NO pulse this frame.
        generator.inputSize.value = 4
        try step()

        try harness.renderer.stopExecution(graph: graph)

        // 5 is now out of range for Size 4; the node must re-emit the clamped 3.
        #expect(generator.outputIndex.value == 3, "Size shrink should re-emit clamped index 3; got \(String(describing: generator.outputIndex.value))")
    }
}
