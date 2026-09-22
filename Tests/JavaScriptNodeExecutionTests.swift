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

    /// Doubles what it is given, so what it last emitted says which script ran.
    private static let doublingScript = """
    function main(value: Number): { doubled: Number }
    {
        return { doubled: value * 2 }
    }
    """

    /// Does not parse: there is no signature here for the node to read ports off.
    private static let uncompilableScript = """
    function main(value: Number  {
        return { doubled: value * 2 }
    }
    """

    /// Takes nothing and returns something: a source, not a filter.
    private static let providerScript = """
    function main(): { tick: Number }
    {
        return { tick: context.frameNumber }
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

    @Test("Changing the time dependency also leaves it asking to run again")
    func changingTimeModeMarksItDirty() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)

        node.markClean()
        try #require(node.isDirty == false)

        node.updateTimeMode(.TimeBase)

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

    // MARK: - An edit that does not compile

    /// The node runs the script the editor shows, or it runs nothing. Keeping the
    /// last runtime that compiled had it go on emitting from a script the author
    /// can no longer see — and looking healthy while it did, because the clean run
    /// wrote its empty diagnostics over the compile error.
    @Test("An edit that does not compile stops the script that did")
    func aFailedCompileStopsTheLastGoodScript() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = JavaScriptNode(context: harness.context)
        node.updateScriptSource(Self.doublingScript)

        let input = try #require(node.findPort(named: "value", as: Port.self))
        let output = try #require(node.findPort(named: "doubled", as: Port.self))

        input.sendBoxed(.Float(3), force: true)
        try harness.execute(node)
        try #require(output.snapshotValue() == .Float(6))

        node.updateScriptSource(Self.uncompilableScript)
        input.sendBoxed(.Float(5), force: true)

        #expect(throws: FabricError.self)
        {
            try harness.execute(node)
        }

        #expect(output.snapshotValue() == .Float(6),
                "10 is the old script still running on the new input")
    }

    /// The diagnostic has to outlast the frame it was made in: the canvas glyph
    /// and the editor's gutter both read it, and an author fixing a script is
    /// reading it a good deal longer than one frame.
    @Test("A compile error outlives the frame after it")
    func aCompileErrorSurvivesTheNextExecute() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = JavaScriptNode(context: harness.context)
        node.updateScriptSource(Self.doublingScript)
        try harness.execute(node)
        try #require(node.currentDiagnostics.isEmpty)

        node.updateScriptSource(Self.uncompilableScript)
        let compileDiagnostic = try #require(node.currentDiagnostics.first)

        try? harness.execute(node)

        #expect(node.currentDiagnostics.first == compileDiagnostic,
                "the run cleared the compile error: \(node.currentDiagnostics)")
        #expect(node.deriveStatuses().isEmpty == false, "and the canvas said nothing was wrong")
    }

    /// Ports are minted from the signature, but a script that does not parse has
    /// no signature — and taking the ports down would take the author's wires
    /// with them, mid-edit. MathExpressionNode's port sync guards the same way.
    @Test("An edit that does not compile keeps the ports the last one declared")
    func aFailedCompileKeepsItsPorts() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)
        node.updateScriptSource(Self.doublingScript)
        try #require(node.ports.map(\.name) == ["value", "doubled"])

        node.updateScriptSource(Self.uncompilableScript)

        #expect(node.ports.map(\.name) == ["value", "doubled"])
    }

    // MARK: - The role the signature puts the node in

    @Test("A script that takes and returns is a Processor")
    func inputsAndOutputsAreAProcessor() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)
        node.updateScriptSource(Self.doublingScript)

        #expect(node.nodeExecutionMode == .Processor)
    }

    @Test("A script that takes nothing is a Provider")
    func outputsOnlyIsAProvider() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)
        node.updateScriptSource(Self.providerScript)

        #expect(node.nodeExecutionMode == .Provider)
    }

    /// The case the mode matters most for: with nothing to return there is
    /// nothing downstream to ask for a value, so only a Consumer is ever run.
    @Test("A script with nothing to return is a Consumer")
    func noOutputsIsAConsumer() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)
        node.updateScriptSource(Self.sideEffectScript)

        #expect(node.nodeExecutionMode == .Consumer)
    }

    @Test("The role follows the script when it is rewritten")
    func theModeFollowsAnEdit() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)
        node.updateScriptSource(Self.doublingScript)
        try #require(node.nodeExecutionMode == .Processor)

        node.updateScriptSource(Self.sideEffectScript)

        #expect(node.nodeExecutionMode == .Consumer)
    }

    /// A failed compile leaves the ports alone, and the mode is read off them,
    /// so a half-typed script does not change what the node is either.
    @Test("An edit that does not compile keeps the role the last one gave it")
    func aFailedCompileKeepsItsMode() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)
        node.updateScriptSource(Self.doublingScript)

        node.updateScriptSource(Self.uncompilableScript)

        #expect(node.nodeExecutionMode == .Processor)
    }

    /// Deriving the mode is only half of it: the graph renders from its own list
    /// of Consumers, and that list is rebuilt when a node is added or deleted —
    /// which an edit is not.
    @Test("A script that becomes a Consumer joins the graph's roots")
    func becomingAConsumerReachesTheGraph() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let node = JavaScriptNode(context: harness.context)
        graph.addNode(node)

        try #require(graph.consumerNodes.contains { $0 === node } == false,
                     "the template takes and returns, so it is a Processor")

        node.updateScriptSource(Self.sideEffectScript)

        #expect(graph.consumerNodes.contains { $0 === node },
                "it is a Consumer now, and nothing else will ever pull it")
    }

    @Test("A script that stops being a Consumer leaves them")
    func leavingConsumerReachesTheGraph() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let node = JavaScriptNode(context: harness.context)
        graph.addNode(node)
        node.updateScriptSource(Self.sideEffectScript)
        try #require(graph.consumerNodes.contains { $0 === node })

        node.updateScriptSource(Self.doublingScript)

        #expect(graph.consumerNodes.contains { $0 === node } == false)
    }
}
