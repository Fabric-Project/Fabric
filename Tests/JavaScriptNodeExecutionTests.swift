import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// Whether the node asks to run again after it is edited.
///
/// `GraphRenderer` skips a Processor whose `isDirty` is false, so a node that
/// changes what it would output without saying so keeps sending the old value
/// until something else in the graph happens to move. Editing a script is
/// exactly that kind of change: nothing upstream of it moved.
@Suite("JavaScript Node execution")
@MainActor
struct JavaScriptNodeExecutionTests
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

    private static let script = """
    function (__int Count) main(__int Scale)
    {
        return { Count: Scale * 2 };
    }
    """

    @Test("A script edit leaves the node asking to run again")
    func editingTheScriptMarksItDirty() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)

        // A node that has just run is clean; this is the state an edit arrives in.
        node.markClean()
        try #require(node.isDirty == false)

        node.updateScriptSource(Self.script)

        #expect(node.isDirty,
                "a Processor that is not dirty is skipped, so the edit would not take effect")
    }

    @Test("Changing the execution mode also leaves it asking to run again")
    func changingModeMarksItDirty() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)

        node.markClean()
        try #require(node.isDirty == false)

        node.updateModes(executionMode: .Consumer, timeMode: .None)

        #expect(node.isDirty)
    }
}
