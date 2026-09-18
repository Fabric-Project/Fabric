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

    /// Returns, but not an object carrying the declared outputs.
    private static let nonObjectScript = """
    function (__int Count) main(__string Spec)
    {
        return 42;
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

    private func makeContextIfPossible() -> Context?
    {
        GraphExecutionTestHarness()?.context
    }
}
