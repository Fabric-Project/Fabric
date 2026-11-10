import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

@Suite("Streams and Points")
struct StreamsPointsTests
{
    private func port<Value>(_ node: Node, _ name: String, as _: Value.Type) throws -> NodePort<Value>
    {
        try #require(node.findPort(named: name) as NodePort<Value>?)
    }

    private func stream<Element: GPUStreamElement>(_ values: ContiguousArray<Element>, _ harness: GraphExecutionTestHarness) throws -> GPUStream<Element>
    {
        try GPUStream(attribute: try Element.publishStream(values, allocator: harness.context.gpuAllocator).attribute)
    }

    @Test("Points uses each stream's own buffer, with strips from Strip Lengths")
    func streamsBecomePointsWithoutCopying() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = PointsNode(context: harness.context, settings: PointsSettings(
            hasNormals: false, hasColors: true, hasSizes: false, hasTexcoords: false, hasStrips: true,
            customAttributes: [PointsCustomAttribute(name: "heat", components: 1)]))
        #expect(node.ports.map(\.name) == ["Positions", "Colors", "heat", "Strip Starts", "Strip Lengths", "Strips Closed", "Indices", "Points"])

        let positions = try stream(ContiguousArray([simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(2, 0, 0)]), harness)
        let colors = try stream(ContiguousArray([simd_float4(1, 0, 0, 1), simd_float4(0, 1, 0, 1), simd_float4(0, 0, 1, 1)]), harness)
        let heat = try stream(ContiguousArray<Float>([0.1, 0.2, 0.3]), harness)
        node.inputPositions.value = positions
        try port(node, "inputColors", as: GPUStream<simd_float4>.self).value = colors
        try port(node, "inputCustom.heat.1", as: GPUStream<Float>.self).value = heat
        try port(node, "inputStripLengths", as: ContiguousArray<Int>.self).value = [2, 1]
        try harness.execute(node)

        let points = try #require(node.outputPoints.value)
        #expect(points.position === positions.attribute)
        #expect(points.attribute(.color) === colors.attribute)
        #expect(points.attribute(.custom("heat")) === heat.attribute)
        guard case let .strips(strips) = points.topology else
        {
            Issue.record("Strip Lengths makes strips")
            return
        }
        #expect(strips.map(\.range) == [0 ..< 2, 2 ..< 3])
        #expect(node.deriveStatuses().isEmpty)
    }

    @Test("Points refuses streams of different counts")
    func differentCountsAreAnError() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = PointsNode(context: harness.context, settings: PointsSettings(
            hasNormals: false, hasColors: false, hasSizes: true, hasTexcoords: false, hasStrips: false, customAttributes: []))
        node.inputPositions.value = try stream(ContiguousArray([simd_float3(0, 0, 0), simd_float3(1, 0, 0)]), harness)
        try port(node, "inputSizes", as: GPUStream<Float>.self).value = try stream(ContiguousArray<Float>([1, 2, 3]), harness)
        try harness.execute(node)

        #expect(node.outputPoints.value == nil)
        #expect(node.deriveStatuses().count == 1)
    }

    @Test("Points refuses a Positions stream that covers only part of its buffer")
    func partialPositionsAreAnError() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = PointsNode(context: harness.context)
        let whole = try stream(ContiguousArray([simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(2, 0, 0)]), harness)
        node.inputPositions.value = try GPUStream(attribute: whole.attribute, count: .known(2))
        try harness.execute(node)

        #expect(node.outputPoints.value == nil)
        #expect(node.deriveStatuses().count == 1)
    }

    @Test("A GPU count draws indirectly, and can't be combined with strips")
    func gpuCountDrawsIndirectly() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let arguments = try #require(harness.context.device.makeBuffer(length: 32, options: .storageModeShared))
        let positions = try stream(ContiguousArray([simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(2, 0, 0)]), harness)
        let counted = try GPUStream<simd_float3>(attribute: positions.attribute, count: .gpu(try PointsDrawArguments(buffer: arguments, offset: 16), capacity: 3))

        let node = PointsNode(context: harness.context)
        node.inputPositions.value = counted
        try harness.execute(node)
        let points = try #require(node.outputPoints.value)
        #expect(points.drawArguments?.buffer === arguments)
        #expect(points.drawArguments?.offset == 16)

        let stripped = PointsNode(context: harness.context, settings: PointsSettings(
            hasNormals: false, hasColors: false, hasSizes: false, hasTexcoords: false, hasStrips: true, customAttributes: []))
        stripped.inputPositions.value = counted
        try port(stripped, "inputStripLengths", as: ContiguousArray<Int>.self).value = [3]
        try harness.execute(stripped)
        #expect(stripped.outputPoints.value == nil)
        #expect(stripped.deriveStatuses().count == 1)

        // A different count reference on another stream is a different count.
        let colors = try GPUStream<simd_float4>(attribute: try stream(ContiguousArray(repeating: simd_float4(1, 1, 1, 1), count: 3), harness).attribute,
                                   count: .gpu(try PointsDrawArguments(buffer: arguments, offset: 0), capacity: 3))
        let colored = PointsNode(context: harness.context, settings: PointsSettings(
            hasNormals: false, hasColors: true, hasSizes: false, hasTexcoords: false, hasStrips: false, customAttributes: []))
        colored.inputPositions.value = counted
        try port(colored, "inputColors", as: GPUStream<simd_float4>.self).value = colors
        try harness.execute(colored)
        #expect(colored.outputPoints.value == nil)
    }

    @Test("Points to Streams shares each attribute's buffer and keeps a GPU count")
    func pointsBecomeStreams() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let positions = try PublishedAttribute.publishing(ContiguousArray([simd_float3(0, 0, 0), simd_float3(1, 0, 0)]), scalar: .float32,
                                                          components: 3, allocator: harness.context.gpuAllocator)
        let colors = try PublishedAttribute.publishing(ContiguousArray([simd_float4(1, 0, 0, 1), simd_float4(0, 1, 0, 1)]), scalar: .float32,
                                                       components: 4, allocator: harness.context.gpuAllocator)
        let arguments = try #require(harness.context.device.makeBuffer(length: 16, options: .storageModeShared))
        let points = try Satin.Points(attributes: [(.position, positions), (.color, colors)], topology: .implicit, bounds: .unknown,
                                      drawArguments: try PointsDrawArguments(buffer: arguments, offset: 0))

        let node = PointsToStreamsNode(context: harness.context, settings: PointsSettings(
            hasNormals: true, hasColors: true, hasSizes: false, hasTexcoords: false, hasStrips: false, customAttributes: []))
        node.inputPoints.value = points
        try harness.execute(node)

        let positionStream = try #require(node.outputPositions.value)
        #expect(positionStream.attribute === positions)
        #expect(positionStream.count == .gpu(try PointsDrawArguments(buffer: arguments, offset: 0), capacity: 2))
        #expect(try port(node, "outputColors", as: GPUStream<simd_float4>.self).value?.attribute === colors)
        // The points carry no normals.
        #expect(try port(node, "outputNormals", as: GPUStream<simd_float3>.self).value == nil)
        #expect(node.deriveStatuses().isEmpty)
    }

    @Test("Points to Streams names an attribute whose layout isn't the type set for it")
    func mismatchedCustomAttributeWarns() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let positions = try PublishedAttribute.publishing(ContiguousArray([simd_float3(0, 0, 0)]), scalar: .float32,
                                                          components: 3, allocator: harness.context.gpuAllocator)
        let age = try PublishedAttribute.publishing(ContiguousArray([simd_float3(1, 2, 3)]), scalar: .float32,
                                                    components: 3, allocator: harness.context.gpuAllocator)
        let points = try Satin.Points(attributes: [(.position, positions), (.custom("age"), age)], topology: .implicit, bounds: .unknown)

        let node = PointsToStreamsNode(context: harness.context, settings: PointsSettings(
            hasNormals: false, hasColors: false, hasSizes: false, hasTexcoords: false, hasStrips: false,
            customAttributes: [PointsCustomAttribute(name: "age", components: 2)]))
        node.inputPoints.value = points
        try harness.execute(node)

        #expect(try port(node, "outputCustom.age.2", as: GPUStream<simd_float2>.self).value == nil)
        #expect(node.deriveStatuses().count == 1)
    }

    /// Wires Points to Streams' topology outputs into Points' inputs, by value.
    private func copyTopology(from split: PointsToStreamsNode, to rebuilt: PointsNode) throws
    {
        for name in ["StripStarts", "StripLengths", "Indices"]
        {
            try port(rebuilt, "input" + name, as: ContiguousArray<Int>.self).value = try port(split, "output" + name, as: ContiguousArray<Int>.self).value
        }
        try port(rebuilt, "inputStripsClosed", as: ContiguousArray<Bool>.self).value = try port(split, "outputStripsClosed", as: ContiguousArray<Bool>.self).value
    }

    /// `topology` through Points to Streams and back.
    private func roundTrip(_ topology: PointTopology, pointCount: Int, _ harness: GraphExecutionTestHarness) throws -> PointTopology?
    {
        let positions = ContiguousArray((0 ..< pointCount).map { simd_float3(Float($0), 0, 0) })
        let position = try PublishedAttribute.publishing(positions, scalar: .float32, components: 3, allocator: harness.context.gpuAllocator)
        let original = try Satin.Points(attributes: [(.position, position)], topology: topology, bounds: .unknown)
        let settings = PointsSettings(hasNormals: false, hasColors: false, hasSizes: false, hasTexcoords: false, hasStrips: true, customAttributes: [])

        let split = PointsToStreamsNode(context: harness.context, settings: settings)
        split.inputPoints.value = original
        try harness.execute(split)
        let rebuilt = PointsNode(context: harness.context, settings: settings)
        rebuilt.inputPositions.value = split.outputPositions.value
        try copyTopology(from: split, to: rebuilt)
        try harness.execute(rebuilt)
        #expect(rebuilt.deriveStatuses().isEmpty)
        return rebuilt.outputPoints.value?.topology
    }

    @Test("Strips with gaps and mixed closing, indices, and points in order all come back as they were")
    func topologyRoundTripsExactly() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let strips = ContiguousArray([PointStrip(range: 2 ..< 4, closed: false), PointStrip(range: 5 ..< 9, closed: true)])
        guard case let .strips(stripsBack)? = try roundTrip(.strips(strips), pointCount: 10, harness) else
        {
            Issue.record("Strips come back as strips")
            return
        }
        #expect(stripsBack == strips)

        let indices = ContiguousArray<UInt32>([3, 1, 2, 0])
        guard case let .indexed(indicesBack)? = try roundTrip(.indexed(indices), pointCount: 4, harness) else
        {
            Issue.record("Indices come back as indices")
            return
        }
        #expect(indicesBack == indices)

        guard case .implicit? = try roundTrip(.implicit, pointCount: 4, harness) else
        {
            Issue.record("Points in order come back in order")
            return
        }
    }

    @Test("Points to Streams and back gives the same buffers and strips")
    func roundTripKeepsBuffersAndStrips() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let settings = PointsSettings(hasNormals: false, hasColors: false, hasSizes: true, hasTexcoords: false, hasStrips: true, customAttributes: [])
        let source = PointsNode(context: harness.context, settings: settings)
        source.inputPositions.value = try stream(ContiguousArray<simd_float3>([[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0]]), harness)
        try port(source, "inputSizes", as: GPUStream<Float>.self).value = try stream(ContiguousArray<Float>([1, 2, 3, 4]), harness)
        try port(source, "inputStripLengths", as: ContiguousArray<Int>.self).value = [1, 3]
        try harness.execute(source)
        let original = try #require(source.outputPoints.value)

        let split = PointsToStreamsNode(context: harness.context, settings: settings)
        split.inputPoints.value = original
        try harness.execute(split)

        let rebuilt = PointsNode(context: harness.context, settings: settings)
        rebuilt.inputPositions.value = split.outputPositions.value
        try port(rebuilt, "inputSizes", as: GPUStream<Float>.self).value = try port(split, "outputSizes", as: GPUStream<Float>.self).value
        try copyTopology(from: split, to: rebuilt)
        try harness.execute(rebuilt)

        let points = try #require(rebuilt.outputPoints.value)
        #expect(points.position === original.position)
        #expect(points.attribute(.size) === original.attribute(.size))
        guard case let .strips(strips) = points.topology else
        {
            Issue.record("Strip Lengths makes strips")
            return
        }
        #expect(strips.map(\.range) == [0 ..< 1, 1 ..< 4])
    }
}
