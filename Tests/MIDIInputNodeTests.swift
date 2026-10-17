import Testing
import Foundation
@testable import Fabric
import Satin

@Suite("MIDI Input")
struct MIDIInputNodeTests
{
    /// A node saved with these inputs learnt, as a document loads it.
    private func decodeNode(configuredWith inputs: [DetectedMIDIInput], context: Context) throws -> MIDIInputNode
    {
        let node = MIDIInputNode(context: context)
        var saved = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as? [String: Any])
        saved["configuredInputs"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(inputs))

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(MIDIInputNode.self, from: JSONSerialization.data(withJSONObject: saved))
    }

    /// Pitch bend rests at centre; it read fully down until the wheel first moved.
    @Test("Inputs not yet heard send their value at rest")
    func unheardInputsSendTheirRestingValue() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let pitchBend = DetectedMIDIInput(type: .pitchBend, channel: 0, number: 0)
        let aftertouch = DetectedMIDIInput(type: .aftertouch, channel: 0, number: 0)
        let controlChange = DetectedMIDIInput(type: .controlChange, channel: 0, number: 1)
        let noteGate = DetectedMIDIInput(type: .noteGate, channel: 0, number: 60)

        let node = try decodeNode(configuredWith: [pitchBend, aftertouch, controlChange, noteGate],
                                  context: harness.context)
        try harness.execute(node)

        #expect((node.findPort(named: pitchBend.portName) as? NodePort<Float>)?.value == 0.5)
        #expect((node.findPort(named: aftertouch.portName) as? NodePort<Float>)?.value == 0.0)
        #expect((node.findPort(named: controlChange.portName) as? NodePort<Float>)?.value == 0.0)
        #expect((node.findPort(named: noteGate.portName) as? NodePort<Bool>)?.value == false)
    }
}
