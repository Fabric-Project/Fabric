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
    public private(set) var lastRuntimeError: (any FabricErrorProtocol)?

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
        do
        {
            try enableExecution(graph: graph)
            try startExecution(graph: graph)
        }
        catch
        {
            handleRuntimeError(error)
        }
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
        do
        {
            try stopExecution(graph: graph)
            try disableExecution(graph: graph)
        }
        catch
        {
            handleRuntimeError(error)
        }
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

        let feedbackCache = self.feedbackCache(for: graph.id)

        for node in scheduledNodes {
            if graphRequiresResize {
                node.resize(size: renderEncoder.size, scaleFactor: resizeScaleFactor)
            }

#if DEBUG
            commandBuffer.pushDebugGroup(node.name)
#endif
            do
            {
                try node.execute(renderer: self,
                                 executionInfo: currentExecutionInfo,
                                 renderPassDescriptor: renderPassDescriptor,
                                 commandBuffer: commandBuffer)
            }
            catch
            {
                handleRuntimeError(error)
            }
#if DEBUG
            commandBuffer.popDebugGroup()
#endif
            node.markClean()
            feedbackCache.cacheProcessedNode(node, executionInfo: currentExecutionInfo)
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
        self.resetTextureCaches(for: currentExecutionInfo)

        let feedbackCache = self.feedbackCache(for: graph.id)
        feedbackCache.resetCacheFor(executionInfo: currentExecutionInfo)

        pendingSceneSync = graph.consumePendingConnectionSceneSync()
        if pendingSceneSync {
            feedbackCache.invalidateTopologyCaches()
        }

        var ordered: [Node] = []
        ordered.reserveCapacity(graph.nodes.count)

        for root in evaluationRoots(for: graph) {
            pullNode(feedbackCache: feedbackCache,
                     node: root.node,
                     requestedOutputPort: root.requestedOutputPort,
                     executionInfo: currentExecutionInfo,
                     cacheProcessedOutputs: false,
                     onTraverse: nil) { ordered.append($0) }
        }

        scheduledNodes = ordered
    }

    // MARK: - Pull traversal (shared by planning and on-demand execution)

    /// Where evaluation pulls start: every consumer node, every published output
    /// port's node (pulled for that specific port), and any explicitly forced
    /// nodes.
    private func evaluationRoots(for graph: Graph,
                                 forcing forcedNodes: [Node] = []) -> [(node: Node, requestedOutputPort: Port?)]
    {
        var roots: [(node: Node, requestedOutputPort: Port?)] = graph.consumerNodes.map { ($0, nil) }

        for outputPort in graph.publishedOutputPorts() {
            guard let node = outputPort.node else { continue }
            roots.append((node, outputPort))
        }

        roots += forcedNodes.map { ($0, nil) }

        return roots
    }

    /// Single recursive pull behind both execution paths: the per-frame planning
    /// pass visits by appending to the schedule (executed later in draw()), the
    /// on-demand path visits by executing the node immediately. `onTraverse`
    /// fires for every node the pull reaches whether or not it runs this pass
    /// (the on-demand path applies pending resizes there); `visit` fires when
    /// the node should run. Returns false when this pull contributes nothing
    /// fresh downstream — the node declined the requested output port (its
    /// keep-alive control inputs are still pulled, at most once per pass, so it
    /// can select a different route later), or sat out the pass because every
    /// one of its own upstream pulls declined.
    @discardableResult
    private func pullNode(feedbackCache: GraphRendererFeedbackCache,
                          node: Node,
                          requestedOutputPort: Port?,
                          executionInfo: GraphExecutionInfo,
                          cacheProcessedOutputs: Bool,
                          onTraverse: ((Node) -> Void)?,
                          visit: (Node) -> Void) -> Bool
    {
        switch node.respondToPull(requestedOutputPort: requestedOutputPort) {
        case .declined(let keepAlivePorts):
            // Unselected route: nothing flows downstream from this pull, but
            // the node's control inputs (Index, map) must keep updating or it
            // could never select a different route — a Gate whose selected
            // output has no consumer would starve its own Index chain, the
            // class fixed for Matrix Switch in e776d909. The node names those
            // inputs as keepAlive; walk them once per pass, marked by
            // .keepAliveWalked, which also terminates control chains that
            // cycle back into another unselected output of this node.
            if feedbackCache.processingState(forNode: node) == .unprocessed {
                feedbackCache.setProcessingState(.keepAliveWalked,
                                                 forNode: node,
                                                 executionInfo: executionInfo)
                for inputPort in keepAlivePorts {
                    pullUpstreamNodes(of: inputPort,
                                      feedbackCache: feedbackCache,
                                      executionInfo: executionInfo,
                                      cacheProcessedOutputs: cacheProcessedOutputs,
                                      onTraverse: onTraverse,
                                      visit: visit)
                }
            }
            return false

        case .evaluate(let pullingPorts):
            switch feedbackCache.processingState(forNode: node) {
            case .processed, .processing:
                return true
            case .declined:
                return false
            case .unprocessed, .keepAliveWalked:
                break
            }

            feedbackCache.setProcessingState(.processing,
                                             forNode: node,
                                             activeInputPorts: pullingPorts,
                                             executionInfo: executionInfo)

            var attemptedPullCount = 0
            var activePullCount = 0

            for inputPort in pullingPorts {
                let pulled = pullUpstreamNodes(of: inputPort,
                                               feedbackCache: feedbackCache,
                                               executionInfo: executionInfo,
                                               cacheProcessedOutputs: cacheProcessedOutputs,
                                               onTraverse: onTraverse,
                                               visit: visit)
                attemptedPullCount += pulled.attempted
                activePullCount += pulled.active
            }

            // A connected node sits out the pass only when every upstream pull
            // declined; that freeze propagates to its own consumers. One live inlet
            // keeps the node running — declined inlets simply hold their last value.
            if attemptedPullCount > 0 && activePullCount == 0 {
                feedbackCache.setProcessingState(.declined,
                                                 forNode: node,
                                                 executionInfo: executionInfo)
                return false
            }

            onTraverse?(node)

            if node.isDirty || node.nodeExecutionMode == .Consumer || node.nodeExecutionMode == .Provider {
                visit(node)
                feedbackCache.setProcessingState(.processed,
                                                 forNode: node,
                                                 executionInfo: executionInfo,
                                                 cacheProcessedOutputs: cacheProcessedOutputs)
            }

            return true
        }
    }

    /// Pulls the node behind every upstream outlet connected to `inputPort`.
    @discardableResult
    private func pullUpstreamNodes(of inputPort: Port,
                                   feedbackCache: GraphRendererFeedbackCache,
                                   executionInfo: GraphExecutionInfo,
                                   cacheProcessedOutputs: Bool,
                                   onTraverse: ((Node) -> Void)?,
                                   visit: (Node) -> Void) -> (attempted: Int, active: Int)
    {
        var attempted = 0
        var active = 0

        for upstreamOutputPort in inputPort.connections where upstreamOutputPort.kind == .Outlet {
            guard let upstreamNode = upstreamOutputPort.node else { continue }

            attempted += 1

            if pullNode(feedbackCache: feedbackCache,
                        node: upstreamNode,
                        requestedOutputPort: upstreamOutputPort,
                        executionInfo: executionInfo,
                        cacheProcessedOutputs: cacheProcessedOutputs,
                        onTraverse: onTraverse,
                        visit: visit) {
                active += 1
            }
        }

        return (attempted, active)
    }

    // MARK: - On-demand graph evaluation (for exporters and subgraph callers)

    public func executeAndDraw(graph: Graph, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        try executeAndDraw(graph: graph, executionInfo: currentExecutionInfo, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    public func executeAndDraw(graph: Graph, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        let needsSceneSync = graph.consumePendingConnectionSceneSync()
        if needsSceneSync {
            invalidateFeedbackTopologyCaches(for: graph)
        }

        try self.execute(graph: graph,
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
                        forceEvaluationForTheseNodes: [Node] = []) throws
    {
        self.resetTextureCaches(for: executionInfo)

        let feedbackCache = self.feedbackCache(for: graph.id)
        feedbackCache.resetCacheFor(executionInfo: executionInfo)

        defer {
            if clearFlags {
                self.graphRequiresResize = false
            }
        }

        let firstCamera = graph.firstCamera ?? self.currentCamera ?? self.defaultCamera

        let applyPendingResize: (Node) -> Void = { node in
            if self.graphRequiresResize {
                node.resize(size: self.renderEncoder.size, scaleFactor: self.resizeScaleFactor)
            }
        }

        var capturedError: (any Error)?

        let executeNode: (Node) -> Void = { node in
            guard capturedError == nil else { return }
#if DEBUG
            commandBuffer.pushDebugGroup(node.name)
#endif
            do
            {
                try node.execute(renderer: self,
                                 executionInfo: executionInfo,
                                 renderPassDescriptor: renderPassDescriptor,
                                 commandBuffer: commandBuffer)
            }
            catch
            {
                capturedError = error
            }
#if DEBUG
            commandBuffer.popDebugGroup()
#endif

            if clearFlags {
                node.markClean()
            }
        }

        let roots = evaluationRoots(for: graph, forcing: forceEvaluationForTheseNodes)

        for root in roots {
            pullNode(feedbackCache: feedbackCache,
                     node: root.node,
                     requestedOutputPort: root.requestedOutputPort,
                     executionInfo: executionInfo,
                     cacheProcessedOutputs: true,
                     onTraverse: applyPendingResize,
                     visit: executeNode)
        }

        if !roots.isEmpty {
            self.currentCamera = firstCamera
        }

        if let capturedError
        {
            throw capturedError
        }
    }

    private func resetTextureCaches(for executionInfo: GraphExecutionInfo)
    {
        self.privateTextureCache.resetCacheFor(executionContext: executionInfo)
        self.sharedTextureCache.resetCacheFor(executionContext: executionInfo)
    }

    // MARK: - Graph Execution Lifecycle

    public func enableExecution(graph: Graph) throws
    {
        for node in graph.nodes {
            try node.enableExecution(renderer: self)
        }
    }

    public func startExecution(graph: Graph) throws
    {
        for node in graph.nodes {
            try node.startExecution(renderer: self)
        }
    }

    public func stopExecution(graph: Graph) throws
    {
        for node in graph.nodes {
            try node.stopExecution(renderer: self)
        }
    }

    public func disableExecution(graph: Graph) throws
    {
        for node in graph.nodes {
            try node.disableExecution(renderer: self)
        }
        self.currentCamera = nil
    }

    public func teardown(graph: Graph)
    {
        for node in graph.nodes {
            node.teardown()
        }
    }

    private func handleRuntimeError(_ error: any Error)
    {
        if let fabricError = error as? any FabricErrorProtocol
        {
            self.lastRuntimeError = fabricError
        }
        else
        {
            self.lastRuntimeError = FabricError(.execution(.failed),
                                                severity: .recoverable,
                                                message: error.localizedDescription,
                                                underlyingError: error)
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

    func invalidateFeedbackTopologyCaches(for graph: Graph)
    {
        feedbackCache(for: graph.id).invalidateTopologyCaches()
    }

    // MARK: - Execution Helpers

    public func newImage(withWidth width: Int, height: Int) throws -> FabricImage
    {
        return try self.newImage(withWidth: width, height: height, format: self.colorPixelFormat)
    }

    public func newImage(withWidth width: Int, height: Int, format: MTLPixelFormat) throws -> FabricImage
    {
        if let image = self.privateTextureCache.newManagedImage(width: width, height: height, pixelFormat: format)
            ?? self.newImageDirect(withWidth: width, height: height, format: format)
        {
            return image
        }

        throw FabricError(.execution(.outOfMemory),
                          severity: .recoverable,
                          message: "Could not allocate image: \(width)x\(height), \(format)")
    }

    public func newImage(withWidth width: Int,
                         height: Int,
                         format: MTLPixelFormat,
                         mipmapped: Bool) throws -> FabricImage
    {
        guard mipmapped else {
            return try newImage(withWidth: width, height: height, format: format)
        }

        if let image = privateTextureCache.newManagedImage(width: width,
                                                           height: height,
                                                           pixelFormat: format,
                                                           mipmapped: true)
            ?? newImageDirect(withWidth: width, height: height, format: format, mipmapped: true)
        {
            return image
        }

        throw FabricError(.execution(.outOfMemory),
                          severity: .recoverable,
                          message: "Could not allocate mipmapped image: \(width)x\(height), \(format)")
    }

    public func newImage(fromPixelBuffer pixelBuffer: CVPixelBuffer) throws -> FabricImage
    {
        let image: FabricImage
        
        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        {
             image = try self.newImage(fromSurface: surface)
        }
        else
        {
            image = try newSharedImage(fromPixelBuffer: pixelBuffer)
        }
        
        image.isFlipped = CVImageBufferIsFlipped(pixelBuffer)
        
        return image
    }

    // MARK: - Private Image Helpers

    private func newSharedImage(fromPixelBuffer pixelBuffer: CVPixelBuffer) throws -> FabricImage
    {
        guard let format = self.metalPixelFormatForOSType(format: CVPixelBufferGetPixelFormatType(pixelBuffer))
        else {
            throw FabricError(.general(.unsupported),
                              severity: .recoverable,
                              message: "Unsupported pixel buffer format: \(CVPixelBufferGetPixelFormatType(pixelBuffer))")
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let image = self.sharedTextureCache.newManagedImage(width: width, height: height, pixelFormat: format)
        else {
            throw FabricError(.execution(.outOfMemory),
                              severity: .recoverable,
                              message: "Could not allocate shared image from pixel buffer: \(width)x\(height), \(format)")
        }

        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw FabricError(.execution(.failed),
                              severity: .recoverable,
                              message: "Could not read pixel buffer base address")
        }

        let region = MTLRegionMake3D(0, 0, 0, width, height, 1)
        image.texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddr, bytesPerRow: bpr)
        
        
        return image
    }

    private func newImage(fromSurface surface: IOSurface) throws -> FabricImage
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

        throw FabricError(.execution(.outOfMemory),
                          severity: .recoverable,
                          message: "Could not allocate image from IOSurface")
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
        // 8-bit packed RGBA
        case kCVPixelFormatType_32BGRA:         return .bgra8Unorm
        case kCVPixelFormatType_32RGBA:         return .rgba8Unorm

        // 10-bit HDR
        case kCVPixelFormatType_ARGB2101010LEPacked: return .bgr10a2Unorm

        // 16-bit half-float
        case kCVPixelFormatType_64RGBAHalf:     return .rgba16Float

        // 32-bit float
        case kCVPixelFormatType_128RGBAFloat:   return .rgba32Float

        // Single-component
        case kCVPixelFormatType_OneComponent8:       return .r8Unorm
        case kCVPixelFormatType_OneComponent16Half:  return .r16Float
        case kCVPixelFormatType_OneComponent32Float: return .r32Float

        // Two-component (e.g. optical flow: X in R, Y in G)
        case kCVPixelFormatType_TwoComponent8:       return .rg8Unorm
        case kCVPixelFormatType_TwoComponent16Half:  return .rg16Float
        case kCVPixelFormatType_TwoComponent32Float: return .rg32Float

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

    private func newImageDirect(withWidth width: Int,
                                height: Int,
                                format: MTLPixelFormat,
                                mipmapped: Bool) -> FabricImage?
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: mipmapped)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        return FabricImage.unmanaged(texture: texture)
    }
}
