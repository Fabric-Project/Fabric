import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// Duplicating gives a copy new ids and leaves its values as they are.
@Suite("Graph Duplication")
struct GraphDuplicationTests
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

    @Test("Duplicating a node leaves a UUID-shaped string value as it is")
    func duplicateKeepsUUIDShapedValues() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let node = StringLengthNode(context: context)
        graph.addNode(node)
        let text = UUID().uuidString
        node.inputPort.value = text

        let copy = try #require(graph.duplicateNodes([node]).first as? StringLengthNode)
        #expect(copy.id != node.id)
        #expect(copy.inputPort.id != node.inputPort.id)
        #expect(copy.inputPort.value == text)
    }
}
