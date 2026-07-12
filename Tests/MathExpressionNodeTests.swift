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

    @Test func retypeReplacesPortWithNewType() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionNode(context: context, expression: "x + 1")
        #expect(node.inputPorts().first?.portType == .Float)

        node.stringExpression = "in x: vec3; out o = x + vec3(1)"
        #expect(node.findPort(named: "x", as: Fabric.Port.self)?.portType == .Vector3)
    }
}
