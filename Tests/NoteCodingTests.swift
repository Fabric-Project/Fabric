import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

@Suite("Note Coding")
struct NoteCodingTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(device: device,
                       sampleCount: 1,
                       colorPixelFormat: .bgra8Unorm,
                       depthPixelFormat: .depth32Float,
                       stencilPixelFormat: .invalid)
    }

    @Test("A note keeps its id across a save")
    func noteIDSurvivesASave() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let note = Note(note: "Kept", rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        graph.addNote(note)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: try JSONEncoder().encode(graph))
        #expect(decoded.notes.map(\.id) == [note.id])
    }
}
