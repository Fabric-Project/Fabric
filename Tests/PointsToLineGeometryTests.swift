import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

/// Points to Line Geometry's two tessellators, CPU and GPU: a best-effort match, compared by what
/// they draw rather than by their triangles, which differ.
@Suite("Points to Line Geometry")
struct PointsToLineGeometryTests
{
    /// The pixels a zigzag of CPU-built points strokes into with `tessellator`, after `configure`.
    private func render(tessellator: String, harness: GraphExecutionTestHarness,
                        configure: (PointsToLineGeometryNode) -> Void = { _ in }) throws -> [Bool]
    {
        let graph = Graph(context: harness.context)
        let points = PointsNode(context: harness.context)
        let positions = ContiguousArray<simd_float3>([[-0.8, -0.3, 0], [-0.3, 0.4, 0], [0.2, -0.4, 0], [0.8, 0.3, 0]])
        points.inputPositions.value = try GPUStream(attribute: try simd_float3.publishStream(positions, allocator: harness.context.gpuAllocator).attribute)
        let line = PointsToLineGeometryNode(context: harness.context)
        line.inputTessellator.value = tessellator
        line.inputWidth.value = 0.12
        configure(line)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)
        mesh.inputCullingMode.value = "None"
        for node in [points, line, material, mesh] as [Node] { graph.addNode(node) }
        graph.connect(points.outputPoints, to: line.inputPoints)
        graph.connect(line.outputGeometry, to: mesh.inputGeometry)
        graph.connect(material.outputMaterial, to: mesh.inputMaterial)

        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        let texture = try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: true)
        #expect(line.status == nil, "\(tessellator): \(String(describing: line.status))")
        return try litPixels(texture, harness)
    }

    /// How much two pictures differ: pixels lit in one and not the other, over pixels lit in either.
    private func mismatch(_ a: [Bool], _ b: [Bool]) -> Double
    {
        let either = zip(a, b).filter { $0 || $1 }.count
        let one = zip(a, b).filter { $0 != $1 }.count
        return either == 0 ? 0 : Double(one) / Double(either)
    }

    @Test("CPU and GPU draw near the same line", arguments: ["plain", "dashed", "trimmed", "square caps and miters"])
    func tessellatorsMatch(variant: String) throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 128, renderHeight: 128) else { return }
        let configure: (PointsToLineGeometryNode) -> Void = { line in
            switch variant
            {
            case "dashed":
                line.inputDashLength.value = 0.15
                line.inputGapLength.value = 0.1
            case "trimmed":
                line.inputTrimStart.value = 0.2
                line.inputTrimEnd.value = 0.7
            case "square caps and miters":
                line.inputCap.value = "Square"
                line.inputJoin.value = "Miter"
            default:
                break
            }
        }
        let cpu = try render(tessellator: PointsToLineGeometryNode.tessellatorCPU, harness: harness, configure: configure)
        let gpu = try render(tessellator: PointsToLineGeometryNode.tessellatorGPU, harness: harness, configure: configure)
        #expect(cpu.contains(true) && gpu.contains(true), "\(variant): both draw")
        // Edges rasterize differently where the triangles differ, so allow a little.
        #expect(mismatch(cpu, gpu) < 0.1, "\(variant): \(mismatch(cpu, gpu))\n\(differenceMap(cpu, gpu, width: 128))")
    }

    /// The two pictures at a quarter size, one character per 4×4 block: # both, C only the CPU's,
    /// G only the GPU's, . neither.
    private func differenceMap(_ cpu: [Bool], _ gpu: [Bool], width: Int) -> String
    {
        let height = cpu.count / width
        var rows: [String] = []
        for blockY in stride(from: 0, to: height, by: 4)
        {
            var row = ""
            for blockX in stride(from: 0, to: width, by: 4)
            {
                var cpuLit = false
                var gpuLit = false
                for y in blockY ..< min(blockY + 4, height)
                {
                    for x in blockX ..< min(blockX + 4, width)
                    {
                        cpuLit = cpuLit || cpu[y * width + x]
                        gpuLit = gpuLit || gpu[y * width + x]
                    }
                }
                row.append(cpuLit && gpuLit ? "#" : cpuLit ? "C" : gpuLit ? "G" : ".")
            }
            rows.append(row)
        }
        return rows.joined(separator: "\n")
    }

    @Test("The CPU tessellator can't stroke points written on the GPU, and says so")
    func cpuRefusesGPUPoints() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let compute = PointsComputeNode(context: harness.context)
        compute.inputCount.value = 16
        let line = PointsToLineGeometryNode(context: harness.context)
        line.inputTessellator.value = PointsToLineGeometryNode.tessellatorCPU

        let commandBuffer = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        for node in [compute, line] as [Node]
        {
            try node.enableExecution(renderer: harness.renderer)
            try node.execute(renderer: harness.renderer, executionInfo: harness.makeExecutionInfo(),
                             renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)
            if node === compute { line.inputPoints.value = compute.outputPoints.value }
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        #expect(line.outputGeometry.value == nil)
        if case .error = line.status {} else { Issue.record("The refusal is the node's status") }
    }

    @Test("Asking the GPU tessellator for pieces warns that only the CPU one makes them")
    func gpuPiecesWarn() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let line = PointsToLineGeometryNode(context: harness.context)
        line.inputPieces.value = StrokeGeometryNode.piecesStrokes
        line.inputPoints.value = try Satin.Points(positions: [[0, 0, 0], [1, 0, 0]], allocator: harness.context.gpuAllocator)
        try line.enableExecution(renderer: harness.renderer)
        let commandBuffer = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        try line.execute(renderer: harness.renderer, executionInfo: harness.makeExecutionInfo(),
                         renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if case .warning = line.status {} else { Issue.record("Pieces on the GPU warn") }
    }

    private func litPixels(_ texture: MTLTexture, _ harness: GraphExecutionTestHarness) throws -> [Bool]
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
        let background = Array(bytes[0 ..< 4])
        return stride(from: 0, to: bytes.count, by: 4).map { Array(bytes[$0 ..< $0 + 4]) != background }
    }
}
