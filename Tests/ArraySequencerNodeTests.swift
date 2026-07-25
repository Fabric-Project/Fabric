import Foundation
import Metal
import Satin
import Testing
@testable import Fabric

@Suite("Array Sequencer Node")
struct ArraySequencerNodeTests
{
    @Test("String specialization and timing controls survive serialization")
    func stringSpecializationSerialization() throws
    {
        guard let context = makeContext() else { return }

        let node = ArraySequencerNode(context: context, portType: .String)
        node.inputCycleDuration.value = 8
        node.inputLoop.value = false

        #expect(node.findPort(named: "inputArray")?.portType == .Array(portType: .String))
        #expect(node.findPort(named: "outputValue")?.portType == .String)

        let encodedNode = try JSONEncoder().encode(node)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decodedNode = try decoder.decode(ArraySequencerNode.self, from: encodedNode)

        #expect(decodedNode.selectedPortType == .String)
        #expect(decodedNode.inputCycleDuration.value == 8)
        #expect(decodedNode.inputLoop.value == false)
        #expect(decodedNode.findPort(named: "inputArray")?.portType == .Array(portType: .String))
        #expect(decodedNode.findPort(named: "outputValue")?.portType == .String)
    }

    @Test("Looping divides the cycle evenly across array elements")
    func loopingSequencePositions()
    {
        #expect(position(at: 0).index == 0)
        #expect(position(at: 1.999).index == 0)
        #expect(position(at: 2).index == 1)
        #expect(position(at: 4).index == 2)
        #expect(position(at: 6).index == 3)
        #expect(position(at: 8).index == 0)
    }

    @Test("Looping progress restarts at each cycle")
    func loopingProgress()
    {
        #expect(position(at: 2).progress == 0.25)
        #expect(position(at: 6).progress == 0.75)
        #expect(position(at: 8).progress == 0)
        #expect(position(at: 10).progress == 0.25)
    }

    @Test("Non-looping playback holds the final element")
    func nonLoopingSequence()
    {
        let atEnd = ArraySequencerNode.sequencePosition(
            elapsedTime: 8,
            cycleDuration: 8,
            elementCount: 4,
            loops: false
        )
        let afterEnd = ArraySequencerNode.sequencePosition(
            elapsedTime: 20,
            cycleDuration: 8,
            elementCount: 4,
            loops: false
        )

        #expect(atEnd.index == 3)
        #expect(atEnd.progress == 1)
        #expect(afterEnd.index == 3)
        #expect(afterEnd.progress == 1)
    }

    @Test("Empty arrays and invalid durations have stable fallback positions")
    func fallbackPositions()
    {
        let empty = ArraySequencerNode.sequencePosition(
            elapsedTime: 2,
            cycleDuration: 8,
            elementCount: 0,
            loops: true
        )
        let zeroDuration = ArraySequencerNode.sequencePosition(
            elapsedTime: 2,
            cycleDuration: 0,
            elementCount: 4,
            loops: true
        )
        let negativeTime = ArraySequencerNode.sequencePosition(
            elapsedTime: -2,
            cycleDuration: 8,
            elementCount: 4,
            loops: true
        )

        #expect(empty.index == nil)
        #expect(empty.progress == 0)
        #expect(zeroDuration.index == 0)
        #expect(zeroDuration.progress == 0)
        #expect(negativeTime.index == 0)
        #expect(negativeTime.progress == 0)
    }

    @Test("Internal time begins at first evaluation and Reset establishes a new origin")
    func sequenceClockReset()
    {
        var clock = ArraySequencerNode.SequenceClock()

        #expect(
            clock.elapsedTime(
                sourceTime: 10,
                shouldReset: false,
                startsAtSourceTime: true
            ) == 0
        )
        #expect(
            clock.elapsedTime(
                sourceTime: 12,
                shouldReset: false,
                startsAtSourceTime: true
            ) == 2
        )
        #expect(
            clock.elapsedTime(
                sourceTime: 12,
                shouldReset: true,
                startsAtSourceTime: true
            ) == 0
        )
        #expect(
            clock.elapsedTime(
                sourceTime: 13.5,
                shouldReset: false,
                startsAtSourceTime: true
            ) == 1.5
        )
    }

    @Test("External time is evaluated from zero until Reset")
    func externalSequenceClock()
    {
        var clock = ArraySequencerNode.SequenceClock()

        #expect(
            clock.elapsedTime(
                sourceTime: 5,
                shouldReset: false,
                startsAtSourceTime: false
            ) == 5
        )
        #expect(
            clock.elapsedTime(
                sourceTime: 7,
                shouldReset: true,
                startsAtSourceTime: false
            ) == 0
        )
    }

    private func position(at elapsedTime: TimeInterval) -> ArraySequencerNode.SequencePosition
    {
        ArraySequencerNode.sequencePosition(
            elapsedTime: elapsedTime,
            cycleDuration: 8,
            elementCount: 4,
            loops: true
        )
    }

    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
    }
}
