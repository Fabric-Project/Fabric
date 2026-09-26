import Foundation
import Metal
import Satin
import Testing
import simd
@testable import Fabric

@Suite("Displacement Material")
struct DisplacementMaterialNodeTests {
    @Test("Shader parameters back the ports and survive shader reconfiguration")
    func sharedParametersSurviveSetup() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let node = DisplacementMaterialNode(context: harness.context)

        #expect(node.inputAmount.value == 0)
        #expect(node.inputBrightness.value == 1)
        #expect(node.inputMinPointSize.value == 1)
        #expect(node.inputMaxPointSize.value == 1)
        #expect(node.inputLumaVsRGBAmount.value == 0)

        let brightness = try #require(node.material.get("Brightness", as: FloatParameter.self))
        #expect(node.inputBrightness.parameter === brightness)
        #expect(brightness.controlType == .slider)
        #expect(brightness.min == 0 && brightness.max == 2)

        node.inputBrightness.value = 1.5
        #expect(brightness.value == 1.5)
        node.markClean()
        brightness.value = 0.75
        #expect(node.inputBrightness.value == 0.75)
        #expect(node.isDirty)

        node.material.set("Color Texture Transform", simd_float4x4.textureVerticalFlip)
        node.material.lighting.toggle()
        node.material.setupShader()

        #expect(node.material.get("Brightness", as: FloatParameter.self) === brightness)
        #expect(brightness.value == 0.75)
        let transform = try #require(node.material.get("Color Texture Transform", as: Float4x4Parameter.self))
        #expect(transform.value == .textureVerticalFlip)
        #expect(node.material.parameters.params.count == 8)
        #expect(Set(node.material.parameters.params.map(\.label)).count == 8)
        #expect(node.ports.count == 13)
        #expect(!node.ports.contains { $0.portType == .Transform })
    }

    @Test("Document loading restores values, publishing and connections into material parameters")
    func documentRoundTrip() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let source = DisplacementMaterialNode(context: harness.context)
        let driver = NumberBinaryOperator(context: harness.context)
        graph.addNode(source)
        graph.addNode(driver)
        graph.connect(driver.outputNumber, to: source.inputAmount)
        source.inputAmount.value = 1.25
        source.inputBrightness.value = 1.5
        source.inputMinPointSize.value = 4
        source.inputMaxPointSize.value = 8
        source.inputLumaVsRGBAmount.value = 0.5
        source.inputBrightness.published = true
        source.inputBrightness.publishedName = "Exposure"

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context)
        let restoredGraph = try decoder.decode(Graph.self, from: JSONEncoder().encode(graph))
        let restored = try #require(restoredGraph.nodes.first { $0.id == source.id } as? DisplacementMaterialNode)
        #expect(restoredGraph.droppedPortStateDiagnostics.isEmpty)

        for originalPort in source.ports {
            let restoredPort = try #require(restored.ports.first { $0.id == originalPort.id })
            #expect(restoredPort.published == originalPort.published)
            #expect(restoredPort.publishedName == originalPort.publishedName)
            if let originalParameter = originalPort.parameter as? FloatParameter {
                let restoredParameter = try #require(restoredPort.parameter as? FloatParameter)
                #expect(restoredParameter.value == originalParameter.value)
                #expect(restoredParameter.id == restoredPort.id)
                #expect(restored.material.get(restoredParameter.label, as: FloatParameter.self) === restoredParameter)
            }
        }

        #expect(restored.inputAmount.connections.count == 1)
        let restoredDriver = try #require(restoredGraph.nodes.first { $0.id == driver.id } as? NumberBinaryOperator)
        restoredDriver.outputNumber.send(0.625, force: true)
        #expect(restored.material.get("Amount", as: FloatParameter.self)?.value == 0.625)

        restored.material.setupShader()
        #expect(restored.material.get("Brightness", as: FloatParameter.self)?.value == 1.5)
        #expect(restored.material.get("Min Point Size", as: FloatParameter.self)?.value == 4)
    }
}
