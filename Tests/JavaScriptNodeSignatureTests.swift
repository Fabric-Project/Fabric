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

    // MARK: - TypeScript

    @Test("Parameters are inputs and the return type is outputs")
    func typeScriptSignatureDeclaresPorts() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        function main(a: FabricNumber, flag: FabricBool): { total: FabricNumber, image: FabricImage } {
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
        function main(rows: FabricTransform[], named: Record<string, FabricVector3>, any: Record<string, FabricValue>): { out: FabricString[] } {
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
        function main(value: FabricNumber) {
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
        function main(a: FabricNumber, b: FabricNumber): { sum: FabricNumber } {
          return { sum: a + b }
        }
        """)

        #expect(signature.transpiledSource.contains("function main(a, b)"))
        #expect(signature.transpiledSource.contains("FabricNumber") == false)
    }

    /// The body brace on its own line, and a parameter list over two. Both are
    /// shapes the rewrite from the annotated form can leave behind, and both put
    /// the signature on more lines than the one it is transpiled to.
    @Test("Transpiling a signature leaves every line below it where it was")
    func transpilingKeepsTheLineNumbering() throws
    {
        let source = """
        function main(a: FabricNumber,
                      b: FabricNumber): { sum: FabricNumber }
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
            function main(a: FabricMatrix): { b: FabricNumber } { return { b: 0 } }
            """)
        }
    }

    // MARK: - FabricValue

    /// `FabricValue` is how a script says "whatever is plugged in". It is the
    /// value type Fabric's own dictionary nodes default to, so it is the only
    /// spelling that receives them — which is why it is offered at all.
    @Test("A script takes a dictionary of anything")
    func aDictionaryOfAnythingIsAnInput() throws
    {
        let signature = try JavaScriptNodeSourceParser.parse(source: """
        function main(Spec: Record<string, FabricValue>): { Count: FabricInt } {
          return { Count: Object.keys(Spec).length }
        }
        """)

        #expect(names(signature.inputs) == ["Spec"])
        #expect(signature.inputs.first?.portType == .Dictionary(valueType: .Virtual))
    }

    /// The other direction has nothing to box a value back into, so it is
    /// refused where it used to compile and then quietly emit nothing.
    @Test("A script cannot return a FabricValue, however it is wrapped")
    func aVirtualOutputIsRefused() throws
    {
        for returnType in ["FabricValue", "FabricValue[]", "Record<string, FabricValue>"]
        {
            #expect(throws: JavaScriptNodeParseError.self) {
                try JavaScriptNodeSourceParser.parse(source: """
                function main(a: FabricNumber): { out: \(returnType) } { return { out: a } }
                """)
            }
        }
    }

    @Test("The refusal says which type it is refusing")
    func theVirtualOutputErrorNamesTheType() throws
    {
        let error = #expect(throws: JavaScriptNodeParseError.self) {
            try JavaScriptNodeSourceParser.parse(source: """
            function main(a: FabricNumber): { out: Record<string, FabricValue> } { return { out: {} } }
            """)
        }

        #expect(error?.errorDescription?.contains("Record<string, FabricValue>") == true,
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
            "function main(Spec: FabricString, FlipV: FabricBool): { Geometry: FabricTransform[], UV: FabricTransform[], Names: FabricString[], Count: FabricInt }"))
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
