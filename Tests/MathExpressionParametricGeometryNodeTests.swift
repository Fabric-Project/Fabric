import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

@Suite struct MathExpressionParametricGeometryNodeTests
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

    @discardableResult
    private func evaluate(_ node: MathExpressionParametricGeometryNode) -> Bool
    {
        node.evaluate(geometry: node.geometry, atTime: 0)
    }

    @Test func defaultExpressionsCompileWithoutParametricInputPorts() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionParametricGeometryNode(context: context)

        #expect(node._settingsModel.statusX)
        #expect(node._settingsModel.statusY)
        #expect(node._settingsModel.statusZ)
        #expect(node.findPort(named: "u", as: Fabric.Port.self) == nil)
        #expect(node.findPort(named: "v", as: Fabric.Port.self) == nil)
    }

    @Test func scalarVariablesBecomeEditableFloatInputPorts() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionParametricGeometryNode(context: context)

        node.expressionX = "a * cos(u)"
        node.expressionY = "b * sin(v)"
        node.expressionZ = "a + b"

        let portA = node.findPort(named: "a", as: Fabric.Port.self)
        let portB = node.findPort(named: "b", as: Fabric.Port.self)

        #expect(portA?.portType == .Float)
        #expect(portB?.portType == .Float)
        #expect(portA is ParameterPort<Float>)
        #expect(portB is ParameterPort<Float>)
    }

    @Test func variablePortChangesUpdateGeneratedPosition() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionParametricGeometryNode(context: context)

        node.expressionX = "a * u"
        node.expressionY = "v"
        node.expressionZ = "a + 1"

        let portA = try #require(node.findPort(named: "a", as: ParameterPort<Float>.self))
        portA.value = 2

        evaluate(node)

        let position = node.geometry.generator(3, 4)
        #expect(position == simd_float3(6, 4, 3))
    }

    @Test func invalidExpressionMarksAxisInvalidAndFallsBackToZero() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionParametricGeometryNode(context: context)

        node.expressionX = "sin("

        #expect(!node._settingsModel.statusX)
        #expect(node._settingsModel.statusY)
        #expect(node._settingsModel.statusZ)

        evaluate(node)

        let position = node.geometry.generator(0, 0)
        #expect(position.x == 0)
        #expect(position.y == 0)
        #expect(position.z == 1)
    }

    @Test func nonScalarExpressionInterfacesAreRejectedForGeometryAxes() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionParametricGeometryNode(context: context)

        node.expressionX = "in p: vec3; out result = p"
        #expect(!node._settingsModel.statusX)
        #expect(node.findPort(named: "p", as: Fabric.Port.self) == nil)

        node.expressionX = "out a = u; out b = v"
        #expect(!node._settingsModel.statusX)
    }
}
