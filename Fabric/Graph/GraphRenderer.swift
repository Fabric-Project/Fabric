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
public class GraphRenderer : MetalViewRenderer
{
    public private(set) var context:Context!
    public let renderer:Renderer
    
    override public var sampleCount: Int { self.context.sampleCount }
    override public var colorPixelFormat: MTLPixelFormat { self.context.colorPixelFormat }
    override public var depthPixelFormat: MTLPixelFormat { self.context.depthPixelFormat }
    override public var stencilPixelFormat: MTLPixelFormat { self.context.stencilPixelFormat }

    public var executionCount = 0
    
    private var lastGraphExecutionTime = Date.timeIntervalSinceReferenceDate

    // This is fucking horrible:
    private let defaultCamera = PerspectiveCamera()
    private var cachedCamera:Camera? = nil
    private let sceneProxy = Object() // ?  IBLScene()
    
    private var graphRequiresResize:Bool = false
    var resizeScaleFactor:Float = 1.0

    // CACHING

    // TODO: in theory we can remove the dirty semantics from node?
    private enum NodeProcessingState
    {
        case unprocessed
        case processing
        case processed
    }

    private var nodeProcessingStateCache: [UUID: NodeProcessingState] = [:]
        
    private struct PortCacheKey: Hashable
    {
        let portID: UUID
        let frameNumber: Int
    }

    private var lastCachePruneFrameNumber: Int = -1
    private var previousFrameCache: [PortCacheKey: PortValue] = [:]

    
    public init(context:Context)
    {
        self.context = context
        self.renderer = Renderer(context: context, stencilStoreAction: .store, frameBufferOnly:false)
        self.renderer.sortObjects = true
        
        self.defaultCamera.position = simd_float3(0, 0, 2)
        self.defaultCamera.lookAt(target: .zero)
                
        super.init()
        
        self.setup()
//        self.renderer.colorTextureStorageMode = .private
//        self.renderer.colorMultisampleTextureStorageMode = .private
//        
//        self.renderer.depthTextureStorageMode = .private
//        self.renderer.depthMultisampleTextureStorageMode = .private
//        
//        self.renderer.stencilTextureStorageMode = .private
//        self.renderer.stencilMultisampleTextureStorageMode = .private
        
        print("Init Graph Execution Engine")
    }
    
    // MARK: - Execution Helpers
    public func newImage(withWidth width:Int, height:Int) -> FabricImage?
    {
        return self.newImage(withWidth: width, height: height, format: self.colorPixelFormat)
    }
    
    public func newImage(withWidth width:Int, height:Int, format:MTLPixelFormat) -> FabricImage?
    {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.pixelFormat = format
        textureDescriptor.textureType = .type2D
        textureDescriptor.mipmapLevelCount = 1
        textureDescriptor.sampleCount = 1
        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        if let texture = self.device.makeTexture(descriptor: textureDescriptor)
        {
            return FabricImage(texture: texture)
        }
        
        return nil
    }
    
    // MARK: - Execution

    public func disableExecution(graph:Graph, executionContext:GraphExecutionContext)
    {
        for node in graph.nodes
        {
            node.disableExecution(context: executionContext)
        }
    }
    
    public func enableExecution(graph:Graph, executionContext:GraphExecutionContext)
    {
        for node in graph.nodes
        {
            node.enableExecution(context: executionContext)
        }
    }
    
    public func startExecution(graph:Graph, executionContext:GraphExecutionContext)
    {
        for node in graph.nodes
        {
            node.startExecution(context: executionContext)
        }
    }
    
    public func stopExecution(graph:Graph, executionContext:GraphExecutionContext)
    {
        for node in graph.nodes
        {
            node.stopExecution(context: executionContext)
        }
    }

    public func teardown(graph:Graph)
    {
        for node in graph.nodes
        {
            node.teardown()
        }
    }
    
    // MARK: - Execution
    
    public func execute(graph:Graph,
                        executionContext:GraphExecutionContext,
                        renderPassDescriptor: MTLRenderPassDescriptor,
                        commandBuffer:MTLCommandBuffer,
                        clearFlags:Bool = true,
                        forceEvaluationForTheseNodes:[Node] = [ ]
        )
    {
        // Clear execution state
        self.nodeProcessingStateCache = [:]
        
        let currentFrame = executionContext.timing.frameNumber
        let previousFrame = currentFrame - 1

        if self.lastCachePruneFrameNumber != currentFrame
        {
            self.previousFrameCache = previousFrameCache.filter { $0.key.frameNumber == previousFrame }
            self.lastCachePruneFrameNumber = currentFrame
        }
        
        defer {
            if clearFlags
            {
                self.graphRequiresResize = false
            }
        }
        
        // Processing means we recursed though the `processGraph` call
        var nodesWeHaveProcessedThisPass:[Node] = []
        
        // Executed means `processGraph` called `execute` on the node sucessfully
        var nodesWeHaveExecutedThisPass:[Node] = []

        // We have one condition which is tricky
        // We may be executing a graph that is a subgraph which has ZERO providers and ZERO consumers
        // But it may have published output ports
        // So we also need to check for nodes which have published output ports
        let nodesWithOutputPorts = graph.nodesWithPublishedOutputs()
        
        // This is fucking horrible:
        let nodesToPullFrom = graph.consumerNodes + nodesWithOutputPorts + forceEvaluationForTheseNodes
         
        // This is fucking horrible:
        let firstCamera = graph.firstCamera ?? self.cachedCamera ?? self.defaultCamera
        
        if !nodesToPullFrom.isEmpty
        {
            for pullNode in nodesToPullFrom
            {
                let _ = processGraph(graph:graph,
                                     node: pullNode,
                                     executionContext:executionContext,
                                     renderPassDescriptor: renderPassDescriptor,
                                     commandBuffer: commandBuffer,
                                     nodesWeHaveProcessedThisPass:&nodesWeHaveProcessedThisPass,
                                     nodesWeHaveExecutedThisPass:&nodesWeHaveExecutedThisPass,
                                     clearFlags: clearFlags)
            }
            
            self.cachedCamera = firstCamera
        }
    }

    private func processGraph(graph:Graph,
                              node: Node,
                              executionContext:GraphExecutionContext,
                              renderPassDescriptor: MTLRenderPassDescriptor,
                              commandBuffer: MTLCommandBuffer,
                              nodesWeHaveProcessedThisPass:inout [Node],
                              nodesWeHaveExecutedThisPass:inout [Node],
                              clearFlags:Bool = true)
    {
        
        switch nodeProcessingStateCache[node.id, default: .unprocessed]
        {
          case .processed:
              // Already executed, return
              return
          case .processing:
              // cycle detected — for temporal feedback, do NOT recurse.
              return
          case .unprocessed:
              break
          }
        
        self.nodeProcessingStateCache[node.id] = .processing
        
        // get the connection for
        let inputNodes = node.inputNodes
        
        self.nodeProcessingStateCache[node.id] = .processing

        let previousFrameNumber = executionContext.timing.frameNumber - 1

        // Inject cached previous-frame values for back-edges (upstream node is currently .processing)
        for inlet in node.inputPorts()
        {
            // In Fabric, inlets typically have at most 1 connection; if more, decide policy.
            guard let upstreamOutlet = inlet.connections.first(where: { $0.kind == .Outlet }) else { continue }
            guard let upstreamNode = upstreamOutlet.node else { continue }

            if nodeProcessingStateCache[upstreamNode.id, default: .unprocessed] == .processing
            {
                let key = PortCacheKey(portID: upstreamOutlet.id, frameNumber: previousFrameNumber)
                let cached = previousFrameCache[key] // PortValue?

                // This is the critical part: make the inlet read last frame instead of recursing
                inlet.setBoxedValue(cached)
            }
        }

                
        for inputNode in inputNodes
        {
            // If we have a feedback loop, and we already processed the node, skip it
//            if !nodesWeHaveProcessedThisPass.contains(inputNode)
//            {
////                 We add before we recurse, otherwise we can recurse infinitely
//                nodesWeHaveProcessedThisPass.append(inputNode)

                processGraph(graph: graph,
                             node: inputNode,
                             executionContext:executionContext,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer,
                             nodesWeHaveProcessedThisPass: &nodesWeHaveProcessedThisPass,
                             nodesWeHaveExecutedThisPass: &nodesWeHaveExecutedThisPass,
                )
                

//            }
        }
        
        if self.graphRequiresResize
        {
            node.resize(size: self.renderer.size, scaleFactor: resizeScaleFactor)
        }
        
//        if node.isDirty || node.nodeExecutionMode == .Consumer || node.nodeExecutionMode == .Provider
//        {
//            // This ensures if a node always is marked as dirty (like some nodes) we only execute once per pass
//            if !nodesWeHaveExecutedThisPass.contains(node)
//            {
        
#if DEBUG
                commandBuffer.pushDebugGroup(node.name)
#endif
                node.execute(context: executionContext,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer)
                
#if DEBUG
                commandBuffer.popDebugGroup()
#endif
        
                nodesWeHaveExecutedThisPass.append(node)
                
                if clearFlags
                {
                    node.markClean()
                }
//            }
//            else
//            {
//                print("We already executed this node?, \(node.name) frame: \(self.executionCount)")
//                
//            }
//            node.lastEvaluationTime = executionContext.timing.time
//        }
        
        self.nodeProcessingStateCache[node.id] = .processed
        
        for outlet in node.outputPorts()
        {
            if !outlet.connections.isEmpty
            {
                let key = PortCacheKey(portID: outlet.id, frameNumber: executionContext.timing.frameNumber)

                if let boxed = outlet.boxedValue()
                {
                    previousFrameCache[key] = boxed
                }
                else
                {
                    previousFrameCache.removeValue(forKey: key)
                }
            }
        }
    }
    
    public func executeAndDraw(graph:Graph, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    {
        let executionContext = self.currentGraphExecutionContext()

        self.executeAndDraw(graph: graph, executionContext: executionContext, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }
    
    public func executeAndDraw(graph:Graph, executionContext:GraphExecutionContext, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    {
        self.cachedCamera = nil
        
        // Snapshot and clear the "connections changed" flag up front
        let needsSceneSync = graph.shouldUpdateConnections
        graph.shouldUpdateConnections = false

        self.execute(graph:graph,
                     executionContext: executionContext,
                     renderPassDescriptor: renderPassDescriptor,
                     commandBuffer: commandBuffer)
        
        if needsSceneSync
        {
            // #Fix 103 -
            // We run this **after** execution, since connection, and then execution may create new objects (see Mesh for example)
            // Only **after** execution are those objects instantiated.
            graph.syncNodesToScene()
        }
                
        self.renderer.draw(renderPassDescriptor: renderPassDescriptor,
                           commandBuffer: commandBuffer,
                           scene: graph.scene,
                           camera: self.cachedCamera ?? self.defaultCamera)
        
        self.lastGraphExecutionTime = executionContext.timing.time
        self.executionCount += 1
    }

    
    public override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    {
        fatalError("use execute(graph:renderPassDescriptor:commandBuffer:) instead.")
    }
    
    override public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.renderer.resize(size)
        
        self.graphRequiresResize = true
        self.resizeScaleFactor = scaleFactor
        
        self.defaultCamera.aspect = size.width / size.height
        
        self.defaultCamera.fov = radToDeg( 2.0 * atan(  (size.height / size.width) / 2.0 ) )
    }
    
    private func currentGraphExecutionContext() -> GraphExecutionContext
    {
        let currentRenderTime = Date.timeIntervalSinceReferenceDate
        
        // TODO: This becomes more semantically correct later
        let timing = GraphExecutionTiming(time: currentRenderTime,
                                          deltaTime: currentRenderTime - self.lastGraphExecutionTime,
                                          displayTime: currentRenderTime,
                                          systemTime: currentRenderTime,
                                          frameNumber: self.frameIndex)
        
        // weird
        return GraphExecutionContext(graphRenderer: self,
                                     timing: timing,
                                     iterationInfo: nil,
                                     eventInfo: nil)
    }
}

