import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// How a script says what its ports are.
///
/// The signature is TypeScript, and the annotated form it replaced still parses
/// — a saved script is a document's, and a syntax change cannot cost it its
/// ports. What is read in the old form is written back in the new one, so a
/// document carries one syntax however it was written.
@Suite("JavaScript Node signature")
@MainActor
struct JavaScriptNodeSignatureTests
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

    private func names(_ ports: [JavaScriptNodePortDefinition]) -> [String] { ports.map(\.name) }

    private static func lineCount(_ text: String) -> Int { text.filter(\.isNewline).count + 1 }

    // MARK: - The node a user gets

    /// The template ships as the first script every author reads, so a type name
    /// it spells the parser's way is the difference between a working node and
    /// one that arrives with an error and no ports at all.
    @Test("A new node's template parses to the ports it declares")
    func theDefaultScriptIsValid() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)

        #expect(node.currentDiagnostics.isEmpty,
                "a node a user has only just made has nothing to complain about: \(node.currentDiagnostics)")
        #expect(node.deriveStatuses().isEmpty)

        let inlets = node.ports.filter { $0.kind == .Inlet }
        let outlets = node.ports.filter { $0.kind == .Outlet }
        #expect(inlets.map(\.name) == ["a", "b", "threshold"])
        #expect(outlets.map(\.name) == ["sum", "thresholdPassed"])
        #expect(inlets.allSatisfy { $0.portType == .Float })
        #expect(outlets.map(\.portType) == [.Float, .Bool])
    }

    // MARK: - Commentary is not code

    /// The edit this is really about: writing the replacement signature under the
    /// one being replaced. The patterns took the first `function main` in the
    /// source, so the node read its ports off the commented-out line and handed
    /// JavaScriptCore the real signature untranspiled, types and all.
    @Test("A signature commented out above the real one is not the signature")
    func aCommentedSignatureIsIgnored() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        // function main(oldValue: Number): { oldResult: Number } {
        function main(value: Number): { result: Number } {
          return { result: value }
        }
        """)

        #expect(names(signature.inputs) == ["value"])
        #expect(names(signature.outputs) == ["result"])
        #expect(signature.transpiledSource.contains("function main(value)"),
                "the real signature is the one transpiled: \(signature.transpiledSource)")
    }

    /// And the node built on it runs, which is the half a parse assertion alone
    /// would miss: what JavaScriptCore was handed used to be TypeScript.
    @Test("A node whose script carries a commented signature compiles")
    func aCommentedSignatureLeavesTheNodeClean() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)

        node.updateScriptSource("""
        // function main(oldValue: Number): { oldResult: Number } {
        function main(value: Number): { result: Number } {
          return { result: value }
        }
        """)

        #expect(node.currentDiagnostics.isEmpty, "\(node.currentDiagnostics)")
        #expect(node.ports.map(\.name) == ["value", "result"])
    }

    @Test("A signature inside a block comment is not the signature")
    func aBlockCommentedSignatureIsIgnored() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        /*
          function main(oldValue: Number): { oldResult: Number } {
        */
        function main(value: Number): { result: Number } {
          return { result: value }
        }
        """)

        #expect(names(signature.inputs) == ["value"])
        #expect(names(signature.outputs) == ["result"])
    }

    @Test("A signature inside a string is not the signature")
    func aQuotedSignatureIsIgnored() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        const usage = "function main(oldValue: Number): { oldResult: Number } {"
        function main(value: Number): { result: Number } {
          return { result: value }
        }
        """)

        #expect(names(signature.inputs) == ["value"])
        #expect(names(signature.outputs) == ["result"])
    }

    /// A script that is all commentary has no signature, rather than the one it
    /// talks about.
    @Test("A script that is entirely commented out declares nothing")
    func aFullyCommentedScriptHasNoSignature() throws
    {
        let error = #expect(throws: JavaScriptNodeParseError.self) {
            try JavaScriptNodeSourceParser.parse(source: """
            // function main(value: Number): { result: Number } {
            //   return { result: value }
            // }
            """)
        }

        #expect(error?.errorDescription?.contains("at the top level") == true,
                "got: \(error?.errorDescription ?? "no description")")
    }

    /// The blocked-syntax scan reads the source the same way, and had the same
    /// blind spot: a line a script no longer runs was still a line it was
    /// refused for.
    @Test("A commented-out require is not a require")
    func aCommentedRequireIsNotBlocked() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        // const helper = require("helper")
        function main(value: Number): { result: Number } {
          return { result: value }
        }
        """)

        #expect(names(signature.inputs) == ["value"])
    }

    @Test("A require the script actually makes is still refused")
    func aRealRequireIsStillBlocked() throws
    {
        let error = #expect(throws: JavaScriptNodeParseError.self) {
            try JavaScriptNodeSourceParser.parse(source: """
            const helper = require("helper")
            function main(value: Number): { result: Number } {
              return { result: value }
            }
            """)
        }

        #expect(error?.errorDescription?.contains("require") == true,
                "got: \(error?.errorDescription ?? "no description")")
    }

    /// A comment that says `function main(` without closing the paren used to
    /// take the real signature's `)` and return type into its own match, leaving
    /// no separate match for the real one to be found as. The patterns are
    /// anchored now, so prose about a signature is not a match to begin with.
    @Test("An unclosed signature in prose does not consume the real one")
    func proseAboutASignatureIsNotAMatch() throws
    {
        for commentary in ["// function main(",
                           "/**\n * Replaces function main(\n */",
                           "/* function main( */"]
        {
            let signature = try JavaScriptNodeSourceParser.parse(source: """
            \(commentary)
            function main(value: Number): { result: Number } {
              return { result: value }
            }
            """)

            #expect(names(signature.inputs) == ["value"], "for \(commentary)")
            #expect(names(signature.outputs) == ["result"], "for \(commentary)")
        }
    }

    /// The scan reads comments, not strings: a signature inside one is passed
    /// over because the patterns want the start of a line and a string's
    /// contents have its opening quote ahead of them. That leaves `require` in a
    /// string looking like a require, which is a refusal the script does not
    /// deserve but a safe one, and cheaper than reading string literals to tell.
    @Test("A require inside a string is refused with the rest")
    func aQuotedRequireIsStillBlocked() throws
    {
        let error = #expect(throws: JavaScriptNodeParseError.self) {
            try JavaScriptNodeSourceParser.parse(source: """
            const advice = "call require() somewhere else"
            function main(value: Number): { result: Number } {
              return { result: value }
            }
            """)
        }

        #expect(error?.errorDescription?.contains("require") == true,
                "got: \(error?.errorDescription ?? "no description")")
    }

    /// The scan does not read regular-expression literals, so a quote inside one
    /// opens a string the script never wrote. Bounding a `'` or `"` to its line
    /// is what keeps that from swallowing the signature underneath it.
    @Test("A quote inside a regular expression does not hide the signature")
    func aQuoteInsideARegexLeavesTheSignatureVisible() throws
    {
        for pattern in ["/'/g", #"/"/g"#, "/`/g"]
        {
            let signature = try JavaScriptNodeSourceParser.parse(source: """
            const strip = (s) => s.replace(\(pattern), "")
            function main(value: Number): { result: Number } {
              return { result: value }
            }
            """)

            #expect(names(signature.inputs) == ["value"], "for \(pattern)")
            #expect(names(signature.outputs) == ["result"], "for \(pattern)")
        }
    }

    /// A template literal is multi-line by design, so it is the one string the
    /// scan still follows past a newline.
    @Test("A signature inside a template literal is not the signature")
    func aTemplatedSignatureIsIgnored() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        const usage = `write it as
        function main(oldValue: Number): { oldResult: Number } {
        and it will run`
        function main(value: Number): { result: Number } {
          return { result: value }
        }
        """)

        #expect(names(signature.inputs) == ["value"])
        #expect(names(signature.outputs) == ["result"])
    }

    // MARK: - TypeScript

    @Test("Parameters are inputs and the return type is outputs")
    func typeScriptSignatureDeclaresPorts() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        function main(a: Number, flag: Bool): { total: Number, image: Image } {
          return { total: a, image: null }
        }
        """)

        #expect(names(signature.inputs) == ["a", "flag"])
        #expect(signature.inputs.map(\.portType) == [.Float, .Bool])
        #expect(names(signature.outputs) == ["total", "image"])
        #expect(signature.outputs.map(\.portType) == [.Float, .Image])
    }

    @Test("Collections are written as TypeScript writes them")
    func collectionsComposeFromTheirElement() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        function main(rows: Transform[], named: Record<string, Vector3>, any: Record<string, Value>): { out: String[] } {
          return { out: [] }
        }
        """)

        #expect(signature.inputs.map(\.portType) == [
            .Array(portType: .Transform),
            .Dictionary(valueType: .Vector3),
            .Dictionary(valueType: .Virtual),
        ])
        #expect(signature.outputs.map(\.portType) == [.Array(portType: .String)])
    }

    @Test("A script with nothing to return declares no outputs")
    func aScriptCanHaveNoOutputs() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        function main(value: Number) {
          console.log(value)
        }
        """)

        #expect(names(signature.inputs) == ["value"])
        #expect(signature.outputs.isEmpty)
    }

    @Test("What JavaScriptCore runs carries no types")
    func theRunnableSourceIsPlainJavaScript() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        function main(a: Number, b: Number): { sum: Number } {
          return { sum: a + b }
        }
        """)

        #expect(signature.transpiledSource.contains("function main(a, b)"))
        // The annotation, not the word: `Number` and `String` are JavaScript
        // globals, so a body is entitled to say them.
        #expect(signature.transpiledSource.contains(": Number") == false)
    }

    /// The type names are the JavaScript globals of the same name, now that
    /// they are unprefixed. Only the signature is rewritten, so a body calling
    /// `Number(…)` or `String(…)` has to come through untouched.
    @Test("A body may call the globals the types are named after")
    func theTypeNamesDoNotShadowTheGlobals() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        function main(a: String): { n: Number, s: String } {
          return { n: Number(a), s: String(Number(a) * 2) }
        }
        """)

        #expect(signature.transpiledSource.contains("function main(a)"))
        #expect(signature.transpiledSource.contains("Number(a)"))
        #expect(signature.transpiledSource.contains("String(Number(a) * 2)"))
        #expect(signature.inputs.map(\.name) == ["a"])
        #expect(signature.outputs.map(\.name) == ["n", "s"])
    }

    /// The body brace on its own line, and a parameter list over two. Both are
    /// shapes the rewrite from the annotated form can leave behind, and both put
    /// the signature on more lines than the one it is transpiled to.
    @Test("Transpiling a signature leaves every line below it where it was")
    func transpilingKeepsTheLineNumbering() throws
    {
        let source = """
        function main(a: Number,
                      b: Number): { sum: Number }
        {
          return { sum: a + b }
        }
        """

        let signature = try JavaScriptNodeSourceParser.parse(source: source)

        #expect(Self.lineCount(signature.transpiledSource) == Self.lineCount(source),
                "the body moved: \n\(signature.transpiledSource)")
    }

    @Test("A type Fabric has no port for is named in the error")
    func anUnknownTypeIsReported() throws
    {
        #expect(throws: JavaScriptNodeParseError.self) {
            try JavaScriptNodeSourceParser.parse(source: """
            function main(a: Matrix): { b: Number } { return { b: 0 } }
            """)
        }
    }

    // MARK: - Value

    /// `Value` is how a script says "whatever is plugged in". It is the
    /// value type Fabric's own dictionary nodes default to, so it is the only
    /// spelling that receives them — which is why it is offered at all.
    @Test("A script takes a dictionary of anything")
    func aDictionaryOfAnythingIsAnInput() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        function main(Spec: Record<string, Value>): { Count: Int } {
          return { Count: Object.keys(Spec).length }
        }
        """)

        #expect(names(signature.inputs) == ["Spec"])
        #expect(signature.inputs.first?.portType == .Dictionary(valueType: .Virtual))
    }

    /// The other direction has nothing to box a value back into, so it is
    /// refused where it used to compile and then quietly emit nothing.
    @Test("A script cannot return a Value, however it is wrapped")
    func aVirtualOutputIsRefused() throws
    {
        for returnType in ["Value", "Value[]", "Record<string, Value>"]
        {
            #expect(throws: JavaScriptNodeParseError.self) {
                try JavaScriptNodeSourceParser.parse(source: """
                function main(a: Number): { out: \(returnType) } { return { out: a } }
                """)
            }
        }
    }

    @Test("The refusal says which type it is refusing")
    func theVirtualOutputErrorNamesTheType() throws
    {
        let error = #expect(throws: JavaScriptNodeParseError.self) {
            try JavaScriptNodeSourceParser.parse(source: """
            function main(a: Number): { out: Record<string, Value> } { return { out: {} } }
            """)
        }

        #expect(error?.errorDescription?.contains("Record<string, Value>") == true,
                "got: \(error?.errorDescription ?? "no description")")
    }

    /// `__dictionary` is the annotated form's spelling of the same thing, and
    /// has been emitting nothing for as long as it has been parsed.
    @Test("The annotated form cannot return a dictionary of anything either")
    func anAnnotatedVirtualOutputIsRefused() throws
    {
        #expect(throws: JavaScriptNodeParseError.self) {
            try JavaScriptNodeSourceParser.parse(source: """
            function (__dictionary Out) main(__string Spec)
            {
                return { Out: {} };
            }
            """)
        }
    }

    // MARK: - The annotated form it replaced

    /// The signature of the immersive room document's script, which is the shape
    /// this has to keep reading: arrays out, a string and a bool in.
    private static let annotated = """
    function (__array_transform Geometry, __array_transform UV, __array_string Names, __int Count) main(__string Spec, __bool FlipV)
    {
        return { Geometry: [], UV: [], Names: [], Count: 0 }
    }
    """

    @Test("A script in the annotated form still declares its ports")
    func theAnnotatedFormStillParses() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: Self.annotated)

        #expect(names(signature.inputs) == ["Spec", "FlipV"])
        #expect(signature.inputs.map(\.portType) == [.String, .Bool])
        #expect(names(signature.outputs) == ["Geometry", "UV", "Names", "Count"])
        #expect(signature.outputs.map(\.portType) == [
            .Array(portType: .Transform),
            .Array(portType: .Transform),
            .Array(portType: .String),
            .Int,
        ])
    }

    @Test("Reading the annotated form writes it back as TypeScript")
    func theAnnotatedFormIsRewritten() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: Self.annotated)

        #expect(signature.canonicalSource.contains(
            "function main(Spec: String, FlipV: Bool): { Geometry: Transform[], UV: Transform[], Names: String[], Count: Int }"))
        #expect(signature.canonicalSource.contains("__array_transform") == false)

        // The body is the author's, and is not touched.
        #expect(signature.canonicalSource.contains("return { Geometry: [], UV: [], Names: [], Count: 0 }"))
    }

    @Test("The rewrite leaves every line below the signature where it was")
    func theRewriteKeepsTheLineNumbering() throws
    {
        let source = """
        function (__int Count)
          main(__string Spec)
        {
            return { Count: 1 };
        }
        """

        let signature = try JavaScriptNodeSourceParser.parse(source: source)

        #expect(Self.lineCount(signature.canonicalSource) == Self.lineCount(source),
                "the body moved: \n\(signature.canonicalSource)")
        #expect(Self.lineCount(signature.transpiledSource) == Self.lineCount(source),
                "the body moved: \n\(signature.transpiledSource)")
    }

    @Test("The rewrite parses as itself, to the same ports")
    func theRewriteIsStable() throws
    {
        let first = try JavaScriptNodeSourceParser.parse(source: Self.annotated)
        let second = try JavaScriptNodeSourceParser.parse(source: first.canonicalSource)

        #expect(second.inputs == first.inputs)
        #expect(second.outputs == first.outputs)
        #expect(second.canonicalSource == first.canonicalSource)
    }

    @Test("A node given the annotated form keeps the TypeScript")
    func aNodeAdoptsTheRewrite() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)

        node.updateScriptSource(Self.annotated)

        #expect(node.findPort(named: "Geometry", as: Fabric.Port.self) != nil)
        #expect(node.findPort(named: "Spec", as: Fabric.Port.self) != nil)
        #expect(node.currentDiagnostics.isEmpty)
    }
}
