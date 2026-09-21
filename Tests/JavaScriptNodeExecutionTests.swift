import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// Running a script, and asking to be run.
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

    /// Declares no return type, so it has no outputs and nothing to hand back.
    private static let sideEffectScript = """
    function main(value: Number)
    {
        console.log(value)
    }
    """

    /// The same, throwing. `JSON.parse("")` is what an unconnected String inlet
    /// supplies reaching a script that expects a document.
    private static let throwingSideEffectScript = """
    function main(value: Number)
    {
        JSON.parse("")
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

    /// A script written for its side effects declares no return type, which the
    /// parser accepts. Running one has to agree: a signature that says there is
    /// nothing to hand back is not a script that forgot to hand something back.
    @Test("A script with nothing to return runs")
    func aScriptWithNoOutputsExecutes() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = JavaScriptNode(context: harness.context)

        node.updateScriptSource(Self.sideEffectScript)
        try #require(node.currentDiagnostics.isEmpty, "it compiled: \(node.currentDiagnostics)")

        try harness.execute(node)

        #expect(node.currentDiagnostics.isEmpty,
                "nothing was declared to return, so nothing is missing: \(node.currentDiagnostics)")
        #expect(node.ports.filter { $0.kind == .Outlet }.isEmpty)
    }

    /// The exception is read before the return is, so a side-effect script that
    /// throws still says what threw rather than going quiet.
    @Test("A script with nothing to return still reports what threw")
    func aThrowingScriptWithNoOutputsStillReports() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = JavaScriptNode(context: harness.context)

        node.updateScriptSource(Self.throwingSideEffectScript)

        try? harness.execute(node)

        #expect(node.currentDiagnostics.isEmpty == false)
    }
}
