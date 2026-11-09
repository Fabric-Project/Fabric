import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

@Suite("Points nodes")
struct PointsNodeTests
{
    private func input<Value>(_ node: Node, _ name: String, as _: Value.Type) throws -> NodePort<Value>
    {
        try #require(node.findPort(named: name) as NodePort<Value>?)
    }

    @Test("Settings add each input in order, and the points carry what they were given")
    func settingsShapeTheInputsAndThePoints() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = PointsNode(context: harness.context, settings: PointsSettings(
            hasNormals: false, hasColors: true, hasSizes: true, hasTexcoords: false, hasStrips: true,
            customAttributes: [PointsCustomAttribute(name: "heat", components: 1)]))

        #expect(node.ports.map(\.name) == ["Positions", "Colors", "Sizes", "heat", "Strip Lengths", "Closed", "Points"])

        node.inputPositions.value = [[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0], [4, 0, 0]]
        try input(node, "inputColors", as: ContiguousArray<simd_float4>.self).value = [[1, 0, 0, 1]]
        try input(node, "inputStripLengths", as: ContiguousArray<Int>.self).value = [3, 2]
        try harness.execute(node)

        let points = try #require(node.outputPoints.value)
        #expect(points.count == 5)
        #expect(points.attributes.map { $0.key } == [.position, .color, .size, .custom("heat")])
        #expect(points.slots.map { $0.index } == [.Position, .Color, .PointSize, .Custom0])
        // One color given: it repeats for every point.
        let colors = try #require(points.attribute(.color)).buffer.contents().bindMemory(to: simd_float4.self, capacity: 5)
        #expect(colors[4] == simd_float4(1, 0, 0, 1))
        guard case let .strips(strips) = points.topology else
        {
            Issue.record("Strip Lengths makes strips")
            return
        }
        #expect(strips.map(\.range) == [0 ..< 3, 3 ..< 5])
    }

    @Test("Turning an input off removes its port, and the others keep their ids")
    func removingAnInputKeepsTheOthers() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = PointsNode(context: harness.context)
        node.setSettings(PointsSettings(hasNormals: false, hasColors: true, hasSizes: true, hasTexcoords: false, hasStrips: false,
                                        customAttributes: []))
        let sizesID = try #require(node.findPort(named: "inputSizes") as Fabric.Port?).id

        node.setSettings(PointsSettings(hasNormals: false, hasColors: false, hasSizes: true, hasTexcoords: false, hasStrips: false,
                                        customAttributes: []))
        #expect((node.findPort(named: "inputColors") as Fabric.Port?) == nil)
        #expect((node.findPort(named: "inputSizes") as Fabric.Port?)?.id == sizesID)
    }

    @Test("Unnamed and repeated custom attributes are dropped")
    func customAttributesAreNormalized() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = PointsNode(context: harness.context, settings: PointsSettings(
            hasNormals: false, hasColors: false, hasSizes: false, hasTexcoords: false, hasStrips: false,
            customAttributes: [PointsCustomAttribute(name: " ", components: 1),
                               PointsCustomAttribute(name: "a", components: 9),
                               PointsCustomAttribute(name: "a", components: 2)]))
        #expect((node.settings as? PointsSettings)?.customAttributes == [PointsCustomAttribute(name: "a", components: 4)])
    }

    @Test("Points with sizes draw bigger sprites through Points Geometry")
    func sizedPointsDrawBigger() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        func litPixelCount(sizes: ContiguousArray<Float>?) throws -> Int
        {
            let graph = Graph(context: harness.context)
            let points = PointsNode(context: harness.context, settings: PointsSettings(
                hasNormals: false, hasColors: false, hasSizes: sizes != nil, hasTexcoords: false, hasStrips: false, customAttributes: []))
            points.inputPositions.value = [[-0.5, 0, 0], [0.5, 0, 0]]
            if let sizes { try input(points, "inputSizes", as: ContiguousArray<Float>.self).value = sizes }
            let geometry = PointsGeometryNode(context: harness.context)
            let material = BasicColorMaterialNode(context: harness.context)
            let mesh = MeshNode(context: harness.context)
            for node in [points, geometry, material, mesh] as [Node] { graph.addNode(node) }
            graph.connect(points.outputPoints, to: geometry.inputPoints)
            graph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
            graph.connect(material.outputMaterial, to: mesh.inputMaterial)

            let renderer = harness.graphRenderer(for: graph)
            try renderer.startExecution()
            defer { try? renderer.stopExecution() }
            let texture = try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: true)
            return try litPixels(of: texture, harness)
        }

        let unsized = try litPixelCount(sizes: nil)
        let sized = try litPixelCount(sizes: [8, 8])
        #expect(unsized > 0, "points draw without sizes")
        #expect(sized > unsized * 4, "sizes enlarge each point")
    }

    private func litPixels(of texture: MTLTexture, _ harness: GraphExecutionTestHarness) throws -> Int
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width,
                                                                  height: texture.height, mipmapped: false)
        descriptor.storageMode = .shared
        guard let readback = harness.context.device.makeTexture(descriptor: descriptor),
              let commandBuffer = harness.renderer.commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else { throw GraphExecutionTestFailure("Failed to make the readback texture") }
        blit.copy(from: texture, to: readback)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress
            {
                readback.getBytes(baseAddress, bytesPerRow: texture.width * 4,
                                  from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            }
        }
        // Lit: any pixel unlike the top-left corner, which is background whatever the clear colour.
        let background = Array(bytes[0 ..< 4])
        return stride(from: 0, to: bytes.count, by: 4).filter { Array(bytes[$0 ..< $0 + 4]) != background }.count
    }
}
