import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// Shared failure type for the graph-execution-oriented test suites (Graph Execution, Routing
/// Nodes, Consolidated Numeric Nodes, Dictionary Ports, Graph Export Renderer). Each suite used
/// to carry its own near-identical private `Error` struct for this; this replaces all five.
struct GraphExecutionTestFailure: Error, CustomStringConvertible
{
    let description: String

    init(_ description: String)
    {
        self.description = description
    }
}

/// Shared Metal device/Context/GraphRenderer bring-up for the graph-execution test suites.
///
/// Five suites previously each carried their own near-identical copy of this harness, and the
/// copies had quietly drifted: different default render sizes (320x180 vs 64x64), inconsistent
/// commandBuffer.error checking (some suites checked it, Consolidated Numeric Nodes silently
/// ignored it, Dictionary Ports never committed a command buffer at all). This consolidates the
/// setup while preserving each suite's original behavior via explicit parameters rather than
/// papering over the differences.
struct GraphExecutionTestHarness
{
    let context: Context
    let renderer: GraphRenderer
    let renderWidth: Int
    let renderHeight: Int

    init?(renderWidth: Int = 320, renderHeight: Int = 180)
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        self.context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
        self.renderer = GraphRenderer(context: self.context)
        self.renderWidth = renderWidth
        self.renderHeight = renderHeight
        self.renderer.resize(
            size: (width: Float(renderWidth), height: Float(renderHeight)),
            scaleFactor: 1.0
        )
    }

    // MARK: - Execution info

    func makeExecutionContext(
        time: TimeInterval,
        deltaTime: TimeInterval,
        systemTime: TimeInterval? = nil,
        frameNumber: Int
    ) -> GraphExecutionInfo
    {
        GraphExecutionInfo(
            timing: GraphExecutionTiming(
                time: time,
                deltaTime: deltaTime,
                displayTime: time,
                systemTime: systemTime ?? time,
                frameNumber: frameNumber
            ),
            iterationInfo: nil,
            eventInfo: nil
        )
    }

    func makeExecutionInfo(frameNumber: Int = 0) -> GraphExecutionInfo
    {
        makeExecutionContext(time: TimeInterval(frameNumber), deltaTime: 0, frameNumber: frameNumber)
    }

    // MARK: - Texture helpers

    func makeTexture(
        width: Int? = nil,
        height: Int? = nil,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws -> MTLTexture
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width ?? renderWidth,
            height: height ?? renderHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]

        guard let texture = context.device.makeTexture(descriptor: descriptor) else {
            throw GraphExecutionTestFailure("Failed to create test texture")
        }

        return texture
    }

    func makeImage(
        width: Int? = nil,
        height: Int? = nil,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws -> FabricImage
    {
        FabricImage.unmanaged(texture: try makeTexture(width: width, height: height, pixelFormat: pixelFormat))
    }

    // MARK: - Graph execution

    /// Runs one render pass over `graph` into a fresh renderWidth x renderHeight color texture.
    /// `checkCommandBufferError` mirrors what each original per-suite harness did: most suites
    /// surfaced a failed commandBuffer as a thrown error, but Consolidated Numeric Nodes never
    /// checked it — that suite's tolerance of GPU flakes is preserved via the parameter rather
    /// than silently tightened.
    @discardableResult
    func execute(
        graph: Graph,
        executionInfo: GraphExecutionInfo,
        drawScene: Bool = false,
        checkCommandBufferError: Bool = true
    ) throws -> MTLTexture
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.colorPixelFormat,
            width: renderWidth,
            height: renderHeight,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = context.device.makeTexture(descriptor: descriptor) else {
            throw GraphExecutionTestFailure("Failed to create color render target")
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            throw GraphExecutionTestFailure("Failed to create command buffer")
        }

        if drawScene {
            renderer.executeAndDraw(
                graph: graph,
                executionInfo: executionInfo,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer
            )
        } else {
            renderer.execute(
                graph: graph,
                executionInfo: executionInfo,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer
            )
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if checkCommandBufferError, let error = commandBuffer.error {
            throw error
        }

        return texture
    }

    /// Convenience matching `GraphExecutionTests`' original `render(graph:executionInfo:drawScene:)`.
    func render(graph: Graph, executionInfo: GraphExecutionInfo, drawScene: Bool = true) throws
    {
        _ = try execute(graph: graph, executionInfo: executionInfo, drawScene: drawScene, checkCommandBufferError: true)
    }

    /// Convenience matching `RoutingNodeExecutionTests`' (and, with `checkCommandBufferError: false`,
    /// `ConsolidatedNumericNodeTests`') original `execute(_:frameNumber:)` / `execute(_:executionInfo:)`.
    @discardableResult
    func execute(_ graph: Graph, frameNumber: Int = 0, checkCommandBufferError: Bool = true) throws -> MTLTexture
    {
        try execute(
            graph: graph,
            executionInfo: makeExecutionInfo(frameNumber: frameNumber),
            drawScene: false,
            checkCommandBufferError: checkCommandBufferError
        )
    }

    /// Runs a single node's `execute` directly against a fresh, uncommitted command buffer —
    /// matching `DictionaryPortTests`' original harness, which exercises node logic in isolation
    /// rather than through the renderer's graph traversal.
    func execute(_ node: Node) throws
    {
        let descriptor = MTLRenderPassDescriptor()
        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            throw GraphExecutionTestFailure("Failed to create command buffer")
        }

        node.execute(
            renderer: renderer,
            executionInfo: makeExecutionContext(time: 0, deltaTime: 0, frameNumber: 0),
            renderPassDescriptor: descriptor,
            commandBuffer: commandBuffer
        )
    }
}
