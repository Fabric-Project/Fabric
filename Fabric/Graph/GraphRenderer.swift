//
//  GraphExecution.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Metal
import Satin

// Graph Execution Engine
public class GraphRenderer : ViewRenderer
{
    public let renderEncoder:RenderEncoder

    override public var sampleCount: Int { self.context.sampleCount }
    override public var colorPixelFormat: MTLPixelFormat { self.context.colorPixelFormat }
    override public var depthPixelFormat: MTLPixelFormat { self.context.depthPixelFormat }
    override public var stencilPixelFormat: MTLPixelFormat { self.context.stencilPixelFormat }

    public var executionCount = 0

    public private(set) var lastGraphExecutionTime = CACurrentMediaTime()

    public private(set) var currentExecutionInfo: GraphExecutionInfo = GraphExecutionInfo(
        timing: GraphExecutionTiming(time: 0, deltaTime: 0, displayTime: nil, systemTime: 0, frameNumber: -1)
    )

    public private(set) var currentCamera: Camera? = nil
    private let defaultCamera: PerspectiveCamera
    private let sceneProxy: Object

    // Staging slot for external event injection (e.g. input event handlers).
    // update() drains this into currentExecutionInfo each frame.
    public var pendingEventInfo: GraphEventInfo? = nil

    private var graphRequiresResize: Bool = false
    public private(set) var resizeScaleFactor: Float = 1.0

    // Pre-sorted node list built in update(), consumed in draw()
    private var scheduledNodes: [Node] = []
    private var pendingSceneSync = false

    // One feedback cache per graph/subgraph UUID to handle different execution cadences
    private var feedbackCaches: [UUID: GraphRendererFeedbackCache] = [:]

    public let graph: Graph

    // Texture caches — private is GPU-private, shared allows CPU updates
    let privateTextureCache: GraphRendererTextureCache
    let sharedTextureCache: GraphRendererTextureCache

    // Convenience init for callers that manage the graph lifecycle manually
    // (e.g. DeferredSubgraphNode, exporters). setup()/cleanup() use self.graph,
    // but these callers bypass that path and call lifecycle methods with their own graph directly.
    override public convenience init(context: Context)
    {
        self.init(context: context, graph: Graph(context: context))
    }

    public init(context: Context, graph: Graph)
    {
        self.graph = graph
        self.renderEncoder = RenderEncoder(context: context, stencilStoreAction: .store, frameBufferOnly: false)
        self.renderEncoder.sortObjects = true

        self.sceneProxy = Object(context: context)
        self.defaultCamera = PerspectiveCamera(context: context)
        self.defaultCamera.position = simd_float3(0, 0, 2)
        self.defaultCamera.lookAt(target: .zero)

        self.privateTextureCache = GraphRendererTextureCache(device: context.device)

        var sharedConfig = GraphRendererTextureCache.Configuration()
        sharedConfig.storageMode = .shared
        self.sharedTextureCache = GraphRendererTextureCache(device: context.device, config: sharedConfig)

        super.init(context: context)
    }

    // MARK: - Satin ViewRenderer Lifecycle

    override public func setup() {
        super.setup()
        enableExecution(graph: graph)
        startExecution(graph: graph)
    }

    override public func update() {
        super.update()

        let now = CACurrentMediaTime()
        let delta = now - lastGraphExecutionTime
        lastGraphExecutionTime = now

        let timing = GraphExecutionTiming(
            time: now,
            deltaTime: delta,
            displayTime: now,
            systemTime: now,
            frameNumber: frameIndex
        )
        currentExecutionInfo = GraphExecutionInfo(timing: timing, eventInfo: pendingEventInfo)
        pendingEventInfo = nil

        updateExecutionPlan()
    }

    override public func cleanup() {
        stopExecution(graph: graph)
        disableExecution(graph: graph)
        teardown(graph: graph)
        super.cleanup()
    }

    override public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.renderEncoder.resize(size)
        self.graphRequiresResize = true
        self.resizeScaleFactor = scaleFactor
        self.defaultCamera.aspect = size.width / size.height
        self.defaultCamera.fov = radToDeg( 2.0 * atan( (size.height / size.width) / 2.0 ) )
    }

    // MARK: - Draw

    override public func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    {
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        for node in scheduledNodes {
            if graphRequiresResize {
                node.resize(size: renderEncoder.size, scaleFactor: resizeScaleFactor)
            }

#if DEBUG
            commandBuffer.pushDebugGroup(node.name)
#endif
            node.execute(renderer: self,
                         executionInfo: currentExecutionInfo,
                         renderPassDescriptor: renderPassDescriptor,
                         commandBuffer: commandBuffer)
#if DEBUG
            commandBuffer.popDebugGroup()
#endif
            node.markClean()
        }

        graphRequiresResize = false

        if pendingSceneSync {
            graph.syncNodesToScene()
            pendingSceneSync = false
        }

        renderEncoder.draw(renderPassDescriptor: renderPassDescriptor,
                           commandBuffer: commandBuffer,
                           scene: graph.scene,
                           camera: currentCamera ?? defaultCamera)

        currentCamera = graph.firstCamera ?? defaultCamera
        executionCount += 1
    }

    // MARK: - Graph Analysis (update phase)

    private func updateExecutionPlan() {
        let feedbackCache = self.feedbackCache(for: graph.id)
        feedbackCache.resetCacheFor(executionInfo: currentExecutionInfo)

        pendingSceneSync = graph.shouldUpdateConnections
        graph.shouldUpdateConnections = false

        let nodesWithOutputPorts = graph.nodesWithPublishedOutputs()
        let pullNodes = graph.consumerNodes + nodesWithOutputPorts

        var ordered: [Node] = []
        for pullNode in pullNodes {
            collectExecutionOrder(feedbackCache: feedbackCache, node: pullNode, orderedNodes: &ordered)
        }

        scheduledNodes = ordered
    }

    private func collectExecutionOrder(feedbackCache: GraphRendererFeedbackCache,
                                       node: Node,
                                       orderedNodes: inout [Node])
    {
        switch feedbackCache.processingState(forNode: node) {
        case .processed, .processing:
            return
        case .unprocessed:
            break
        }

        feedbackCache.setProcessingState(.processing, forNode: node, executionInfo: currentExecutionInfo)

        for inputNode in node.inputNodes {
            collectExecutionOrder(feedbackCache: feedbackCache, node: inputNode, orderedNodes: &orderedNodes)
        }

        if node.isDirty || node.nodeExecutionMode == .Consumer || node.nodeExecutionMode == .Provider {
            orderedNodes.append(node)
            feedbackCache.setProcessingState(.processed, forNode: node, executionInfo: currentExecutionInfo)
        }
    }

    // MARK: - On-demand graph evaluation (for exporters and subgraph callers)

    public func executeAndDraw(graph: Graph, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    {
        executeAndDraw(graph: graph, executionInfo: currentExecutionInfo, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    public func executeAndDraw(graph: Graph, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    {
        let needsSceneSync = graph.shouldUpdateConnections
        graph.shouldUpdateConnections = false

        self.execute(graph: graph,
                     executionInfo: executionInfo,
                     renderPassDescriptor: renderPassDescriptor,
                     commandBuffer: commandBuffer)

        if needsSceneSync {
            graph.syncNodesToScene()
        }

        self.renderEncoder.draw(renderPassDescriptor: renderPassDescriptor,
                                commandBuffer: commandBuffer,
                                scene: graph.scene,
                                camera: self.currentCamera ?? self.defaultCamera)

        self.executionCount += 1
    }

    public func execute(graph: Graph,
                        executionInfo: GraphExecutionInfo,
                        renderPassDescriptor: MTLRenderPassDescriptor,
                        commandBuffer: MTLCommandBuffer,
                        clearFlags: Bool = true,
                        forceEvaluationForTheseNodes: [Node] = [])
    {
        let feedbackCache = self.feedbackCache(for: graph.id)
        feedbackCache.resetCacheFor(executionInfo: executionInfo)

        defer {
            if clearFlags {
                self.graphRequiresResize = false
            }
        }

        let nodesWithOutputPorts = graph.nodesWithPublishedOutputs()
        let nodesToPullFrom = graph.consumerNodes + nodesWithOutputPorts + forceEvaluationForTheseNodes
        let firstCamera = graph.firstCamera ?? self.currentCamera ?? self.defaultCamera

        if !nodesToPullFrom.isEmpty {
            var nodesWeHaveProcessedThisPass: [Node] = []
            var nodesWeHaveExecutedThisPass: [Node] = []

            for pullNode in nodesToPullFrom {
                processGraph(graph: graph,
                             graphFeedbackCache: feedbackCache,
                             node: pullNode,
                             executionInfo: executionInfo,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer,
                             nodesWeHaveProcessedThisPass: &nodesWeHaveProcessedThisPass,
                             nodesWeHaveExecutedThisPass: &nodesWeHaveExecutedThisPass,
                             clearFlags: clearFlags)
            }

            self.currentCamera = firstCamera
        }
    }

    private func processGraph(graph: Graph,
                              graphFeedbackCache: GraphRendererFeedbackCache,
                              node: Node,
                              executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor,
                              commandBuffer: MTLCommandBuffer,
                              nodesWeHaveProcessedThisPass: inout [Node],
                              nodesWeHaveExecutedThisPass: inout [Node],
                              clearFlags: Bool = true)
    {
        switch graphFeedbackCache.processingState(forNode: node) {
        case .processed:
            return
        case .processing:
            return
        case .unprocessed:
            break
        }

        graphFeedbackCache.setProcessingState(.processing, forNode: node, executionInfo: executionInfo)

        for inputNode in node.inputNodes {
            processGraph(graph: graph,
                         graphFeedbackCache: graphFeedbackCache,
                         node: inputNode,
                         executionInfo: executionInfo,
                         renderPassDescriptor: renderPassDescriptor,
                         commandBuffer: commandBuffer,
                         nodesWeHaveProcessedThisPass: &nodesWeHaveProcessedThisPass,
                         nodesWeHaveExecutedThisPass: &nodesWeHaveExecutedThisPass,
                         clearFlags: clearFlags)
        }

        if self.graphRequiresResize {
            node.resize(size: self.renderEncoder.size, scaleFactor: resizeScaleFactor)
        }

        if node.isDirty || node.nodeExecutionMode == .Consumer || node.nodeExecutionMode == .Provider {
            if !nodesWeHaveExecutedThisPass.contains(node) {
#if DEBUG
                commandBuffer.pushDebugGroup(node.name)
#endif
                node.execute(renderer: self,
                             executionInfo: executionInfo,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer)
#if DEBUG
                commandBuffer.popDebugGroup()
#endif
                nodesWeHaveExecutedThisPass.append(node)

                if clearFlags {
                    node.markClean()
                }

                graphFeedbackCache.setProcessingState(.processed, forNode: node, executionInfo: executionInfo)
            }
        }
    }

    // MARK: - Graph Execution Lifecycle

    public func enableExecution(graph: Graph)
    {
        for node in graph.nodes {
            node.enableExecution(renderer: self)
        }
    }

    public func startExecution(graph: Graph)
    {
        for node in graph.nodes {
            node.startExecution(renderer: self)
        }
    }

    public func stopExecution(graph: Graph)
    {
        for node in graph.nodes {
            node.stopExecution(renderer: self)
        }
    }

    public func disableExecution(graph: Graph)
    {
        for node in graph.nodes {
            node.disableExecution(renderer: self)
        }
        self.currentCamera = nil
    }

    public func teardown(graph: Graph)
    {
        for node in graph.nodes {
            node.teardown()
        }
    }

    // MARK: - Feedback Cache

    private func feedbackCache(for graphID: UUID) -> GraphRendererFeedbackCache
    {
        if let cache = feedbackCaches[graphID] { return cache }
        let newCache = GraphRendererFeedbackCache(graphID: graphID)
        feedbackCaches[graphID] = newCache
        return newCache
    }

    // MARK: - Execution Helpers

    public func newImage(withWidth width: Int, height: Int) -> FabricImage?
    {
        return self.newImage(withWidth: width, height: height, format: self.colorPixelFormat)
    }

    public func newImage(withWidth width: Int, height: Int, format: MTLPixelFormat) -> FabricImage?
    {
        return self.privateTextureCache.newManagedImage(width: width, height: height, pixelFormat: format)
            ?? self.newImageDirect(withWidth: width, height: height, format: format)
    }

    public func newImage(fromPixelBuffer pixelBuffer: CVPixelBuffer) -> FabricImage?
    {
        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            return self.newImage(fromSurface: surface)
        }
        return newSharedImage(fromPixelBuffer: pixelBuffer)
    }

    // MARK: - Private Image Helpers

    private func newSharedImage(fromPixelBuffer pixelBuffer: CVPixelBuffer) -> FabricImage?
    {
        guard let format = self.metalPixelFormatForOSType(format: CVPixelBufferGetPixelFormatType(pixelBuffer))
        else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let image = self.sharedTextureCache.newManagedImage(width: width, height: height, pixelFormat: format)
        else { return nil }

        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let region = MTLRegionMake3D(0, 0, 0, width, height, 1)
        image.texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddr, bytesPerRow: bpr)
        return image
    }

    private func newImage(fromSurface surface: IOSurface) -> FabricImage?
    {
        let descriptor = self.metalTextureDescriptorForIOSurface(surface: surface)

        if let descriptor,
           let texture = self.device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0)
        {
            IOSurfaceIncrementUseCount(surface)
            return FabricImage.managed(texture: texture) { _ in
                IOSurfaceDecrementUseCount(surface)
            }
        }
        return nil
    }

    private func metalTextureDescriptorForIOSurface(surface: IOSurfaceRef) -> MTLTextureDescriptor?
    {
        let width  = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let format = IOSurfaceGetPixelFormat(surface)
        guard let metalFormat = self.metalPixelFormatForOSType(format: format) else { return nil }
        return self.textureDescriptor(width: width, height: height, format: metalFormat)
    }

    private func metalPixelFormatForOSType(format: OSType) -> MTLPixelFormat?
    {
        switch format {
        case kCVPixelFormatType_32BGRA:
            return .bgra8Unorm
        default:
            return nil
        }
    }

    private func textureDescriptor(width: Int, height: Int, format: MTLPixelFormat) -> MTLTextureDescriptor
    {
        let desc = MTLTextureDescriptor()
        desc.width = width
        desc.height = height
        desc.pixelFormat = format
        desc.textureType = .type2D
        desc.mipmapLevelCount = 1
        desc.sampleCount = 1
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        return desc
    }

    private func newImageDirect(withWidth width: Int, height: Int, format: MTLPixelFormat) -> FabricImage?
    {
        let desc = self.textureDescriptor(width: width, height: height, format: format)
        if let texture = self.device.makeTexture(descriptor: desc) {
            return FabricImage.unmanaged(texture: texture)
        }
        return nil
    }
}
