import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin
import MathExpressionEngine

/// Node-level behaviour of the engine-backed Math Expression node: dynamic port
/// derivation, retype, wire-preserving diffing, and diagnostics. Needs a Metal
/// device to build a `Context`; skipped gracefully where none exists.
@Suite struct MathExpressionNodeTests
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

    private func names(_ ports: [Fabric.Port]) -> Set<String> { Set(ports.map(\.name)) }

    @Test func defaultExpressionDerivesTwoFloatInputsOneFloatOutput() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionNode(context: context)

        #expect(names(node.inputPorts()) == ["x", "y"])
        #expect(node.inputPorts().allSatisfy { $0.portType == .Float })

        #expect(node.outputPorts().count == 1)
        #expect(node.outputPorts().first?.name == "result")
        #expect(node.outputPorts().first?.portType == .Float)
    }

    @Test func typedVectorInputAndOutput() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionNode(context: context, expression: "in p: vec3; out o = p * 2")

        #expect(names(node.inputPorts()) == ["p"])
        #expect(node.inputPorts().first?.portType == .Vector3)
        #expect(names(node.outputPorts()) == ["o"])
        #expect(node.outputPorts().first?.portType == .Vector3)
    }

    @Test func comprehensionProducesTransformArrayOutput() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionNode(context: context, expression: "[ translate(vec3(i, 0, 0)) for i in 0..<n ]")

        // n is a float input; the output is a transform[] that can drive an
        // instanced mesh.
        #expect(names(node.inputPorts()) == ["n"])
        #expect(node.outputPorts().first?.portType == .Array(portType: .Transform))
    }

    /// A port whose name and type survive an edit must be the *same* port object
    /// (identity preserved) so its wires aren't dropped. Editing `sin(x)+y^2`
    /// into `sin(x)+z` keeps `x`, removes `y`, adds `z`.
    @Test func unchangedPortsArePreservedAcrossEdits() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionNode(context: context)

        let xPortID = node.findPort(named: "x", as: Fabric.Port.self)?.id
        #expect(xPortID != nil)

        node.stringExpression = "sin(x) + z"

        #expect(node.findPort(named: "x", as: Fabric.Port.self)?.id == xPortID) // preserved
        #expect(node.findPort(named: "y", as: Fabric.Port.self) == nil)         // removed
        #expect(node.findPort(named: "z", as: Fabric.Port.self) != nil)         // added
    }

    /// A transiently invalid edit keeps the last good ports (and their wires)
    /// rather than tearing them down, and surfaces an error diagnostic.
    @Test func invalidEditKeepsPortsAndReportsError() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionNode(context: context)

        node.stringExpression = "sin("
        #expect(names(node.inputPorts()) == ["x", "y"]) // unchanged
        #expect(node._settingsModel.diagnostics.contains { $0.severity == .error })
        #expect(node.name.hasPrefix("⚠"))
    }

    /// Torture-tests for the node-title heuristic, drawn from the language spec:
    /// it drops `in` declarations and `let` locals, strips `//` comments, treats
    /// only `;` as a statement separator (newlines are whitespace), and surfaces
    /// the first output's — or first assignment's — right-hand side.
    @Test func salientTitleTortureCases()
    {
        func title(_ e: String) -> String { MathExpressionNode.salientTitle(from: e) }

        // The motivating case: drop the input decl, take the output RHS.
        #expect(title("in spectrum:float[];\nout scales = [vec3(1,1,x) for (i, x) in spectrum]")
            == "[vec3(1,1,x) for (i, x) in spectrum]")

        // A bare expression with no assignment is kept verbatim.
        #expect(title("1 + 2 * 3") == "1 + 2 * 3")
        #expect(title("sin(x) + y") == "sin(x) + y")

        // Default output name; bare vs named give the same salient text.
        #expect(title("vec3(x, y, 0)") == "vec3(x, y, 0)")
        #expect(title("out position = vec3(x, y, 0)") == "vec3(x, y, 0)")

        // Trailing `//` comment is stripped (and its trailing spaces trimmed).
        #expect(title("out y = amplitude * sin(t * frequency)   // a simple oscillator")
            == "amplitude * sin(t * frequency)")

        // A leading comment is the author's own title, taken verbatim (sans //).
        #expect(title("// My Oscillator\nout y = amp * sin(t)") == "My Oscillator")
        #expect(title("   //   Spacey Title  \nout r = x") == "Spacey Title")
        // Even when the leading comment looks like code, it still wins.
        #expect(title("// out fake = 1\nout real = x + 1") == "out fake = 1")
        // A non-leading comment is stripped and must not win over the real output.
        #expect(title("in p: vec3; // in q: vec3; out z = 9\nout o = p.x") == "p.x")

        // `let` locals are dropped; the first real output is used.
        #expect(title("let r = length(vec2(x, y)); out inside = saturate(1 - r); out glow = 1 - saturate(r)")
            == "saturate(1 - r)")

        // A `let` before a bare expression: local dropped, expression kept.
        #expect(title("let r = length(vec2(x, y));\nsaturate(1 - r)") == "saturate(1 - r)")

        // Only `;` separates statements — a single statement wrapped across
        // several lines must NOT be split at the newline.
        #expect(title("out ring = [ translate(vec3(i, 0, 0))\n             for i in 0..<count ]")
            == "[ translate(vec3(i, 0, 0)) for i in 0..<count ]")

        // Several outputs: the first one wins.
        #expect(title("out x = cos(t);\nout y = sin(t)") == "cos(t)")

        // A division `/` is not a comment; `..<` ranges have no `=`.
        #expect(title("out r = x / 2") == "x / 2")
        #expect(title("[ i * i for i in 0..<n ]") == "[ i * i for i in 0..<n ]")

        // Inline-typed one-off name, bare: kept as-is.
        #expect(title("count(points: vec3[])") == "count(points: vec3[])")

        // Trailing `;` and messy interior whitespace are normalised.
        #expect(title("out a =   vec3( 0 ,  1 , 2 ) ;") == "vec3( 0 , 1 , 2 )")

        // `inverse(...)` must not be mistaken for an `in` declaration.
        #expect(title("out t = inverse(lookAt(eye, target, vec3(0, 1, 0)))")
            == "inverse(lookAt(eye, target, vec3(0, 1, 0)))")

        // A comment-only expression is a leading comment → used as the title.
        #expect(title("// just a note") == "just a note")

        // Declarations only (no comment, no output) → nothing salient → empty
        // (falls back to the type name at the call site).
        #expect(title("in x: float").isEmpty)
    }

    @Test func retypeReplacesPortWithNewType() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionNode(context: context, expression: "x + 1")
        #expect(node.inputPorts().first?.portType == .Float)

        node.stringExpression = "in x: vec3; out o = x + vec3(1)"
        #expect(node.findPort(named: "x", as: Fabric.Port.self)?.portType == .Vector3)
    }
}
