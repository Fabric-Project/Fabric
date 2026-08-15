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
    private let traceEditorExecution = false

    override public var sampleCount: Int { self.context.sampleCount }
    override public var colorPixelFormat: MTLPixelFormat { self.context.colorPixelFormat }
    override public var depthPixelFormat: MTLPixelFormat { self.context.depthPixelFormat }
    override public var stencilPixelFormat: MTLPixelFormat { self.context.stencilPixelFormat }

    public var executionCount = 0
    public private(set) var executionTrace: GraphExecutionTrace?

    public private(set) var lastGraphExecutionTime = CACurrentMediaTime()
    private var graphExecutionStartTime = CACurrentMediaTime()

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

    private var executionPlanCaches: [ObjectIdentifier: GraphExecutionPlanCache] = [:]
    private var traceExecutionIndex = 0
    private var graphExecutionTraceStack: [GraphExecutionTraceFrameBuilder] = []
    private var nodeExecutionTraceStack: [NodeExecutionTraceBuilder] = []

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
        self.renderEncoder = RenderEncoder(
            context: context,
            clearColor: .zero,
            depthStoreAction: .store,
            stencilStoreAction: .dontCare,
            frameBufferOnly: false
        )
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

    override public func setup() throws {
        try super.setup()

        let now = CACurrentMediaTime()
        self.graphExecutionStartTime = now
        self.lastGraphExecutionTime = now

        try enableExecution(graph: graph)
        try startExecution(graph: graph, trace: traceEditorExecution)
    }

    override public func update() throws {
        try super.update()
        
        let now = CACurrentMediaTime()
        let delta = now - lastGraphExecutionTime
        lastGraphExecutionTime = now
        
        let timing = GraphExecutionTiming(
            time: now - self.graphExecutionStartTime,
            deltaTime: delta,
            displayTime: now - self.graphExecutionStartTime,
            systemTime: Date.timeIntervalSinceReferenceDate,
            frameNumber: frameIndex
        )
        currentExecutionInfo = GraphExecutionInfo(timing: timing, eventInfo: pendingEventInfo)
        pendingEventInfo = nil
        
    }

    /// Set the execution info without reading the wall clock. Tests call this
    /// directly to drive the update/draw path with deterministic timing.
    func planFrame(executionInfo: GraphExecutionInfo) {
        currentExecutionInfo = executionInfo
    }

    override public func cleanup() throws {
        let traceURL = URL(fileURLWithPath: "/private/tmp")
            .appending(path: "fabric-graph-execution-trace-\(graph.id).json")
        try stopExecution(graph: graph, saveTraceTo: traceEditorExecution ? traceURL : nil)
        try disableExecution(graph: graph)
        teardown(graph: graph)
        try super.cleanup()
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

    override public func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        try executeAndDraw(graph: graph,
                           executionInfo: currentExecutionInfo,
                           renderPassDescriptor: renderPassDescriptor,
                           commandBuffer: commandBuffer)
    }

    // MARK: - On-demand graph evaluation (for exporters and subgraph callers)

    public func executeAndDraw(graph: Graph, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        try executeAndDraw(graph: graph, executionInfo: currentExecutionInfo, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    public func executeAndDraw(graph: Graph, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        let clearColor = self.renderEncoder.clearColor
        let colorLoadAction = self.renderEncoder.colorLoadAction
        let depthLoadAction = self.renderEncoder.depthLoadAction
        let stencilLoadAction = self.renderEncoder.stencilLoadAction
        defer {
            self.renderEncoder.clearColor = clearColor
            self.renderEncoder.colorLoadAction = colorLoadAction
            self.renderEncoder.depthLoadAction = depthLoadAction
            self.renderEncoder.stencilLoadAction = stencilLoadAction
        }

        let needsSceneSync = graph.consumePendingConnectionSceneSync()

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

        defer {
            if clearFlags {
                self.graphRequiresResize = false
            }
        }

        self.currentCamera = graph.firstCamera ?? self.currentCamera ?? self.defaultCamera

        var capturedError: (any Error)?
        var scheduledNodes = nodesInExecutionOrder(for: graph)

        if !forceEvaluationForTheseNodes.isEmpty {
            let alreadyScheduledNodeIDs = Set(scheduledNodes.map(\.id))
            scheduledNodes.append(contentsOf: executionPlanExtension(forcing: forceEvaluationForTheseNodes,
                                                                     alreadyScheduledNodeIDs: alreadyScheduledNodeIDs))
        }

        let graphTraceFrame = beginGraphExecutionTrace()

        for (orderIndex, node) in scheduledNodes.enumerated() {
            guard capturedError == nil else { break }

            if self.graphRequiresResize {
                node.resize(size: self.renderEncoder.size, scaleFactor: self.resizeScaleFactor)
            }

            let nodeTrace = beginNodeExecutionTrace(node: node, orderIndex: orderIndex)

            guard node.isDirty || node.nodeExecutionMode == .Consumer || node.nodeExecutionMode == .Provider else {
                endNodeExecutionTrace(nodeTrace, result: .skippedClean)
                continue
            }

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

            endNodeExecutionTrace(nodeTrace, result: capturedError == nil ? .executed : .error)

            if clearFlags {
                node.markClean()
            }
        }

        endGraphExecutionTrace(graphTraceFrame)

        if let capturedError
        {
            throw capturedError
        }
    }

    private struct GraphExecutionPlanCache
    {
        var graphID: UUID
        var connectionTopologyGeneration: Int
        var executionTopologyGeneration: Int
        var nodesInExecutionOrder: [Node]
    }

    private enum GraphExecutionPlanningState
    {
        case processing
        case processed
        case keepAliveWalked
        case declined
    }

    private func nodesInExecutionOrder(for graph: Graph) -> [Node]
    {
        let graphIdentifier = ObjectIdentifier(graph)

        if let cached = executionPlanCaches[graphIdentifier],
           cached.graphID == graph.id,
           cached.connectionTopologyGeneration == graph.connectionTopologyGeneration,
           cached.executionTopologyGeneration == graph.executionTopologyGeneration
        {
            return cached.nodesInExecutionOrder
        }

        let nodesInExecutionOrder = buildNodesInExecutionOrder(for: graph)
        executionPlanCaches[graphIdentifier] = GraphExecutionPlanCache(
            graphID: graph.id,
            connectionTopologyGeneration: graph.connectionTopologyGeneration,
            executionTopologyGeneration: graph.executionTopologyGeneration,
            nodesInExecutionOrder: nodesInExecutionOrder
        )

        return nodesInExecutionOrder
    }

    private func buildNodesInExecutionOrder(for graph: Graph) -> [Node]
    {
        var ordered: [Node] = []
        ordered.reserveCapacity(graph.nodes.count)

        var processingStates: [UUID: GraphExecutionPlanningState] = [:]

        for root in executionRoots(for: graph)
        {
            pullNodeForExecutionPlan(node: root.node,
                                     requestedOutputPort: root.requestedOutputPort,
                                     processingStates: &processingStates,
                                     orderedNodes: &ordered)
        }

        return ordered
    }

    /// Extends the cached execution plan for callers that force extra nodes to run
    /// (Iterator forces its whole subgraph). Each forced node is pulled exactly as
    /// buildNodesInExecutionOrder pulls its roots, so forced nodes and any
    /// unscheduled upstream dependencies are appended in dependency order rather
    /// than caller array order. Forced nodes whose pull declines them are still
    /// appended at the end — the caller asked for them to run.
    private func executionPlanExtension(forcing forcedNodes: [Node], alreadyScheduledNodeIDs: Set<UUID>) -> [Node]
    {
        var processingStates: [UUID: GraphExecutionPlanningState] = [:]
        processingStates.reserveCapacity(alreadyScheduledNodeIDs.count + forcedNodes.count)

        for scheduledNodeID in alreadyScheduledNodeIDs {
            processingStates[scheduledNodeID] = .processed
        }

        var ordered: [Node] = []

        for forcedNode in forcedNodes {
            pullNodeForExecutionPlan(node: forcedNode,
                                     requestedOutputPort: nil,
                                     processingStates: &processingStates,
                                     orderedNodes: &ordered)
        }

        for forcedNode in forcedNodes where processingStates[forcedNode.id] != .processed {
            ordered.append(forcedNode)
        }

        return ordered
    }

    private func executionRoots(for graph: Graph) -> [(node: Node, requestedOutputPort: Port?)]
    {
        var roots: [(node: Node, requestedOutputPort: Port?)] = graph.nodes
            .filter { $0.nodeExecutionMode == .Consumer }
            .map { ($0, nil) }

        for outputPort in graph.publishedOutputPorts()
        {
            guard let node = outputPort.node else { continue }
            roots.append((node, outputPort))
        }

        return roots
    }

    @discardableResult
    private func pullNodeForExecutionPlan(node: Node,
                                          requestedOutputPort: Port?,
                                          processingStates: inout [UUID: GraphExecutionPlanningState],
                                          orderedNodes: inout [Node]) -> Bool
    {
        switch node.respondToPull(requestedOutputPort: requestedOutputPort)
        {
        case .declined(let keepAlivePorts):
            if processingStates[node.id] == nil
            {
                processingStates[node.id] = .keepAliveWalked
                for inputPort in keepAlivePorts
                {
                    pullInletConnectionsForExecutionPlan(inputPort,
                                                         processingStates: &processingStates,
                                                         orderedNodes: &orderedNodes)
                }
            }
            return false

        case .evaluate(let pullingPorts):
            switch processingStates[node.id]
            {
            case .processed, .processing:
                return true
            case .declined:
                return false
            case .keepAliveWalked, nil:
                break
            }

            processingStates[node.id] = .processing

            var attemptedPullCount = 0
            var activePullCount = 0

            for inputPort in pullingPorts
            {
                let pulled = pullInletConnectionsForExecutionPlan(inputPort,
                                                                  processingStates: &processingStates,
                                                                  orderedNodes: &orderedNodes)
                attemptedPullCount += pulled.attempted
                activePullCount += pulled.active
            }

            if attemptedPullCount > 0 && activePullCount == 0
            {
                processingStates[node.id] = .declined
                return false
            }

            orderedNodes.append(node)
            processingStates[node.id] = .processed
            return true
        }
    }

    @discardableResult
    private func pullInletConnectionsForExecutionPlan(_ inputPort: Port,
                                                      processingStates: inout [UUID: GraphExecutionPlanningState],
                                                      orderedNodes: inout [Node]) -> (attempted: Int, active: Int)
    {
        var attempted = 0
        var active = 0

        for outletPort in inputPort.connectedOutletsForActiveConnections
        {
            guard let node = outletPort.node else { continue }

            attempted += 1
            if pullNodeForExecutionPlan(node: node,
                                        requestedOutputPort: outletPort,
                                        processingStates: &processingStates,
                                        orderedNodes: &orderedNodes)
            {
                active += 1
            }
        }

        return (attempted, active)
    }

    private func resetTextureCaches(for executionInfo: GraphExecutionInfo)
    {
        self.privateTextureCache.resetCacheFor(executionContext: executionInfo)
        self.sharedTextureCache.resetCacheFor(executionContext: executionInfo)
    }

    // MARK: - Execution Trace

    private func beginGraphExecutionTrace() -> GraphExecutionTraceFrameBuilder?
    {
        guard executionTrace != nil else { return nil }

        let builder = GraphExecutionTraceFrameBuilder(executionIndex: traceExecutionIndex,
                                                      startedAt: CACurrentMediaTime())
        traceExecutionIndex += 1
        graphExecutionTraceStack.append(builder)
        return builder
    }

    private func endGraphExecutionTrace(_ builder: GraphExecutionTraceFrameBuilder?)
    {
        guard let builder else { return }

        if graphExecutionTraceStack.last === builder {
            graphExecutionTraceStack.removeLast()
        }
        else {
            graphExecutionTraceStack.removeAll { $0 === builder }
        }

        let execution = builder.makeExecution(endedAt: CACurrentMediaTime())

        if let nodeBuilder = nodeExecutionTraceStack.last {
            nodeBuilder.childExecutions.append(execution)
        }
        else {
            executionTrace?.executions.append(execution)
        }
    }

    private func beginNodeExecutionTrace(node: Node, orderIndex: Int) -> NodeExecutionTraceBuilder?
    {
        guard executionTrace != nil,
              graphExecutionTraceStack.isEmpty == false
        else { return nil }

        let builder = NodeExecutionTraceBuilder(node: node,
                                                orderIndex: orderIndex,
                                                startedAt: CACurrentMediaTime())
        nodeExecutionTraceStack.append(builder)
        return builder
    }

    private func endNodeExecutionTrace(_ builder: NodeExecutionTraceBuilder?, result: NodeExecutionResult)
    {
        guard let builder else { return }

        if nodeExecutionTraceStack.last === builder {
            nodeExecutionTraceStack.removeLast()
        }
        else {
            nodeExecutionTraceStack.removeAll { $0 === builder }
        }

        let nodeExecution = builder.makeNodeExecution(endedAt: CACurrentMediaTime(),
                                                      result: result)
        graphExecutionTraceStack.last?.nodeExecutions.append(nodeExecution)
    }

    // MARK: - Graph Execution Lifecycle

    public func enableExecution(graph: Graph) throws
    {
        for node in graph.nodes {
            try node.enableExecution(renderer: self)
        }
    }

    public func startExecution(graph: Graph, trace: Bool = false) throws
    {
        if trace {
            self.executionTrace = GraphExecutionTrace(graphID: graph.id)
            self.traceExecutionIndex = 0
            self.graphExecutionTraceStack.removeAll(keepingCapacity: true)
            self.nodeExecutionTraceStack.removeAll(keepingCapacity: true)
        }
        else if graph.id == self.graph.id {
            self.executionTrace = nil
            self.traceExecutionIndex = 0
            self.graphExecutionTraceStack.removeAll(keepingCapacity: true)
            self.nodeExecutionTraceStack.removeAll(keepingCapacity: true)
        }

        for node in graph.nodes {
            try node.startExecution(renderer: self)
        }
    }

    public func stopExecution(graph: Graph, saveTraceTo url: URL? = nil) throws
    {
        for node in graph.nodes {
            try node.stopExecution(renderer: self)
        }

        if let url {
            try saveExecutionTrace(to: url)
        }
    }

    public func saveExecutionTrace(to url: URL) throws
    {
        guard let executionTrace else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(executionTrace)
        try data.write(to: url)
        print("Saved graph execution trace: \(url.path)")
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
