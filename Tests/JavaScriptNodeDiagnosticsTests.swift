import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// What the node says when running the script goes wrong.
///
/// A script's own exception and a script that returns the wrong thing are
/// different faults with different fixes, and the author only ever sees the
/// diagnostic — so which one is reported, and where it points, is the whole
/// value of it.
@Suite("JavaScript Node diagnostics")
@MainActor
struct JavaScriptNodeDiagnosticsTests
{
    /// Throws from the body. `JSON.parse("")` is the case that reaches an author
    /// first: an empty string is what an unconnected String inlet supplies, so a
    /// graph wired to a spec that has not been pasted in yet lands here.
    private static let throwingScript = """
    function (__int Count) main(__string Spec)
    {
        return { Count: JSON.parse(Spec).surfaces.length };
    }
    """

    /// The TypeScript form with the body brace on its own line — the shape the
    /// rewrite from the annotated form produces, and so the shape every migrated
    /// script has.
    private static let throwingTypeScript = """
    function main(Spec: FabricString): { Count: FabricInt }
    {
        return { Count: JSON.parse(Spec).surfaces.length };
    }
    """

    /// Returns, but not an object carrying the declared outputs.
    private static let nonObjectScript = """
    function (__int Count) main(__string Spec)
    {
        return 42;
    }
    """

    /// Declares three numbers and returns two of them. Nothing throws: the
    /// script is wrong only about the shape of one value it hands back.
    private static let shortVectorScript = """
    function main(a: FabricNumber): { Position: FabricVector3 }
    {
        return { Position: [1, 2] };
    }
    """

    /// Declares an output and sets nothing, which is a script choosing to send
    /// nothing this frame rather than a script getting something wrong.
    private static let silentOutputScript = """
    function main(a: FabricNumber): { Position: FabricVector3 }
    {
        return {};
    }
    """

    private func run(_ source: String) throws -> [JavaScriptNodeDiagnostic]
    {
        guard let harness = GraphExecutionTestHarness() else { return [] }
        let node = JavaScriptNode(context: harness.context)
        node.updateScriptSource(source)

        do {
            try harness.execute(node)
            Issue.record("expected \(source.prefix(40))… to fail execution")
        } catch {
            // The thrown error is the graph's business; the diagnostic is the author's.
        }

        return node.currentDiagnostics
    }

    @Test("A script that throws reports what threw")
    func aThrowingScriptReportsWhatThrew() throws
    {
        guard GraphExecutionTestHarness() != nil else { return }
        let summary = try run(Self.throwingScript).first?.summary ?? ""

        #expect(summary.contains("JSON"),
                "the diagnostic should name the failure the script hit, got: \(summary)")
        #expect(!summary.contains("must return an object"),
                "a throwing script is being reported as a bad return shape, got: \(summary)")
    }

    @Test("A script that returns the wrong shape still says so")
    func aNonObjectReturnIsStillReported() throws
    {
        guard GraphExecutionTestHarness() != nil else { return }
        let summary = try run(Self.nonObjectScript).first?.summary ?? ""

        #expect(summary.contains("must return an object"),
                "a non-object return should be reported as one, got: \(summary)")
    }

    @Test("A throwing script points at the line that threw")
    func aThrowingScriptPointsAtItsLine() throws
    {
        guard GraphExecutionTestHarness() != nil else { return }
        let diagnostic = try run(Self.throwingScript).first

        #expect(diagnostic?.line ?? 0 > 0,
                "the diagnostic should point into the script, not at its first character")
    }

    /// Not merely "into the script": the whole worth of the line is that it is
    /// the right one, and a signature transpiled onto fewer lines than it was
    /// written on is off by exactly the difference.
    @Test("A throwing script points at the line it threw on, not the one above")
    func aThrowingScriptPointsAtTheLineItThrewOn() throws
    {
        guard GraphExecutionTestHarness() != nil else { return }
        let diagnostic = try run(Self.throwingTypeScript).first

        // Zero-based, so the third line of the script.
        #expect(diagnostic?.line == 2,
                "the JSON.parse is on line 3, reported at line \((diagnostic?.line ?? -1) + 1)")
    }

    @Test("A script that will not compile says so on the node")
    func aScriptThatWillNotCompileIsANodeError() throws
    {
        guard let context = makeContextIfPossible() else { return }
        let node = JavaScriptNode(context: context)

        node.updateScriptSource("this is not a signature")

        let statuses = node.deriveStatuses()
        #expect(statuses.count == 1)
        #expect(statuses.first?.kind == "Error")
    }

    @Test("A script that throws says so on the node")
    func aScriptThatThrowsIsANodeError() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = JavaScriptNode(context: harness.context)
        node.updateScriptSource(Self.throwingScript)

        try #require(node.deriveStatuses().isEmpty, "it compiled, so nothing to report yet")

        try? harness.execute(node)

        #expect(node.deriveStatuses().count == 1)
        #expect(node.deriveStatuses().first?.message.contains("JSON") == true)
    }

    @Test("A script that runs leaves the node saying nothing")
    func aWorkingScriptClearsTheNodeStatus() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = JavaScriptNode(context: harness.context)
        node.updateScriptSource(Self.throwingScript)
        try? harness.execute(node)
        try #require(node.deriveStatuses().isEmpty == false)

        node.updateScriptSource("""
        function (__int Count) main(__string Spec)
        {
            return { Count: 1 };
        }
        """)
        try harness.execute(node)

        #expect(node.deriveStatuses().isEmpty)
    }

    /// The failure this is really about: before, an output whose value would not
    /// box sent nil every frame and said nothing at all, so the author watched a
    /// port that never fired with nowhere to look.
    @Test("An output that will not box says so instead of going quiet")
    func anUnboxableOutputIsReported() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = JavaScriptNode(context: harness.context)
        node.updateScriptSource(Self.shortVectorScript)

        try harness.execute(node)

        let diagnostic = try #require(node.currentDiagnostics.first,
                                      "a two-long array is not a FabricVector3, and nothing said so")
        #expect(diagnostic.severity == .warning, "the script ran; only one value was wrong")
        #expect(diagnostic.summary.contains("Position"))
        #expect(diagnostic.summary.contains("FabricVector3"))
        #expect(diagnostic.summary.contains("2"), "the count is the explanation: \(diagnostic.summary)")

        #expect(node.deriveStatuses().first?.kind == "Warning")
    }

    @Test("An output the script never sets stays silent")
    func anUnsetOutputIsNotADiagnostic() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = JavaScriptNode(context: harness.context)
        node.updateScriptSource(Self.silentOutputScript)

        try harness.execute(node)

        #expect(node.currentDiagnostics.isEmpty,
                "declining to set an output is not a mistake: \(node.currentDiagnostics)")
    }

    /// The diagnostic belongs to the last run, not to every run after it.
    @Test("An output that starts boxing again clears the warning")
    func afixedOutputClearsTheWarning() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = JavaScriptNode(context: harness.context)
        node.updateScriptSource(Self.shortVectorScript)
        try harness.execute(node)
        try #require(node.currentDiagnostics.isEmpty == false)

        node.updateScriptSource("""
        function main(a: FabricNumber): { Position: FabricVector3 }
        {
            return { Position: [1, 2, 3] };
        }
        """)
        try harness.execute(node)

        #expect(node.currentDiagnostics.isEmpty)
        #expect(node.deriveStatuses().isEmpty)
    }

    private func makeContextIfPossible() -> Context?
    {
        GraphExecutionTestHarness()?.context
    }
}
