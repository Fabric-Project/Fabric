import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// Whether the node says on the canvas that its shader will not compile.
@Suite("Live Image status")
@MainActor
struct LiveImageNodeStatusTests
{
    @Test("A shader that will not compile is the node's status")
    func aBrokenShaderIsANodeError() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = LiveImageNode(context: harness.context)

        // The bundled shader compiles. If it has not here, this environment
        // cannot give the node a workspace and there is nothing to test.
        guard node.deriveStatuses().isEmpty else { return }

        node.updateShaderSource("this is not a Metal shader")

        #expect(node.deriveStatuses().isEmpty == false,
                "the node compiled nothing and said nothing")
    }
}
