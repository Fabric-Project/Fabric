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
    public let graph:Graph
    public let renderer:Renderer
    
    override public var sampleCount: Int { self.context.sampleCount }
    override public var colorPixelFormat: MTLPixelFormat { self.context.colorPixelFormat }
    override public var depthPixelFormat: MTLPixelFormat { self.context.depthPixelFormat }
    override public var stencilPixelFormat: MTLPixelFormat { self.context.stencilPixelFormat }
    
    private var lastGraphExecutionTime = Date.timeIntervalSinceReferenceDate
    private var executionCount = 0

    // This is fucking horrible:
    private let defaultCamera = PerspectiveCamera()
    private var cachedCamera:Camera? = nil
    private let sceneProxy = Object() // ?  IBLScene()
    
    private var graphRequiresResize:Bool = false
    private var resizeScaleFactor:Float = 1.0
    
    
    public init(context:Context, graph:Graph)
    {
        self.context = context
        self.graph = graph
        self.renderer = Renderer(context: context, stencilStoreAction: .store, frameBufferOnly:false)
        self.renderer.sortObjects = true
        
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
    
    // MARK: - Execution

    public func disableExecution(graph:Graph)
    {
        let executionContext = self.currentGraphExecutionContext()

        for node in graph.nodes
        {
            node.disableExecution(context: executionContext)
        }
    }
    
    public func enableExecution(graph:Graph)
    {
        let executionContext = self.currentGraphExecutionContext()

        for node in graph.nodes
        {
            node.enableExecution(context: executionContext)
        }
    }
    
    public func startExecution(graph:Graph)
    {
        let executionContext = self.currentGraphExecutionContext()
        
        for node in graph.nodes
        {
            node.startExecution(context: executionContext)
        }
    }
    
    public func stopExecution(graph:Graph)
    {
        let executionContext = self.currentGraphExecutionContext()

        for node in graph.nodes
        {
            node.stopExecution(context: executionContext)
        }
    }

    // MARK: - Execution
    
    public func execute(graph:Graph,
                        executionContext:GraphExecutionContext,
                        renderPassDescriptor: MTLRenderPassDescriptor,
                         commandBuffer:MTLCommandBuffer) -> (objects:[Satin.Object], camera:Satin.Camera?)
    {
        
        defer { self.graphRequiresResize = false }
        
        var nodesWeHaveExecutedThisPass:[Node] = []

        // This is fucking horrible:
        let theseShouldBeProvidersLol = [Node.NodeType.Utility] + Node.NodeType.ObjectType.nodeTypes()
        let providerNodes =  graph.nodes.filter( { theseShouldBeProvidersLol.contains($0.nodeType) } )
        
        let sceneObjectNodes:[any ObjectNodeProtocol] = providerNodes.compactMap({ $0 as? any ObjectNodeProtocol})
        
        // This is fucking horrible:
        let subgraphNodes = graph.nodes.filter( { $0.nodeType == .Subgraph })

        // This is fucking horrible:
        let firstCameraNode = sceneObjectNodes.first(where: { $0.nodeType == .Object(objectType: .Camera)})
        
        // This is fucking horrible:
        let firstCamera = firstCameraNode?.object as? Camera ?? self.cachedCamera ?? self.defaultCamera
            
        if !providerNodes.isEmpty
        {
            let sceneObjects = sceneObjectNodes.compactMap( { $0.object } )

            for renderNode in providerNodes + subgraphNodes
            {
                let _ = processGraph(graph:graph,
                                     node: renderNode,
                                     executionContext:executionContext,
                                     renderPassDescriptor: renderPassDescriptor,
                                     commandBuffer: commandBuffer,
                                     nodesWeHaveExecutedThisPass:&nodesWeHaveExecutedThisPass)
            }
            

            self.cachedCamera = firstCamera
            let renderables = graph.renderables
            
            
//            for node in nodesWeHaveExecutedThisPass
//            {
//                node.markClean()
//            }
            
            return (objects: sceneObjects + renderables, camera:firstCamera)

            
        }
        
//        // We need to handle iterator execution, as it may not have a camera
//        // we just add it to the list of objects we are executing
//        else if let _ = executionContext.iterationInfo,
//                    let cachedCamera
//        {
//            let sceneObjects = sceneObjectNodes.compactMap( { $0.object } )
//
//            
//            for renderNode in sceneObjectNodes + subgraphNodes
//            {
//                let _ = processGraph(graph:graph,
//                                     node: renderNode as! Node,
//                                     executionContext:executionContext,
//                                     renderPassDescriptor: renderPassDescriptor,
//                                     commandBuffer: commandBuffer,
//                                     nodesWeHaveExecutedThisPass:&nodesWeHaveExecutedThisPass)
//            }
//            
//
//            sceneProxy.add(sceneObjects)
//            
//            self.renderer.draw(renderPassDescriptor: renderPassDescriptor,
//                               commandBuffer: commandBuffer,
//                               scene: sceneProxy,
//                               camera: cachedCamera)
//
//
//            nodesWeHaveExecutedThisPass.forEach( { $0.markClean() } )
//
//        }
//        
        
//        for node in nodesWeHaveExecutedThisPass
//        {
//            node.markClean()
//        }
        
        return (objects: [], camera:nil)
        
    }

    private func processGraph(graph:Graph,
                              node: Node,
                              executionContext:GraphExecutionContext,
                              renderPassDescriptor: MTLRenderPassDescriptor,
                              commandBuffer: MTLCommandBuffer,
                              nodesWeHaveExecutedThisPass:inout  [Node]
                              )
    {
        
        // get the connection for
        let inputNodes = node.inputNodes
                
        for inputNode in inputNodes
        {
            processGraph(graph: graph,
                         node: inputNode,
                         executionContext:executionContext,
                         renderPassDescriptor: renderPassDescriptor,
                         commandBuffer: commandBuffer,
                         nodesWeHaveExecutedThisPass: &nodesWeHaveExecutedThisPass,
                         )
        }
        
        if self.graphRequiresResize
        {
            node.resize(size: self.renderer.size, scaleFactor: resizeScaleFactor)
        }
        
        if node.isDirty
        {
//            if !nodesWeHaveExecutedThisPass.contains(node)
//            {
            
                
            
                node.execute(context: executionContext,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer)
                
                
                nodesWeHaveExecutedThisPass.append(node)
                
                node.markClean()
//            }
//            else
//            {
//                print("We already executed this node?, \(node.name) frame: \(self.executionCount)")
//                
//            }
//            node.lastEvaluationTime = executionContext.timing.time
        }
    }
    
    public override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    {
        self.executionCount += 1

        let executionContext = self.currentGraphExecutionContext()
        
        self.sceneProxy.removeAll()
//        self.cachedCamera = nil
        
        let (objects, camera) = self.execute(graph:self.graph,
                     executionContext: executionContext,
                     renderPassDescriptor: renderPassDescriptor,
                     commandBuffer: commandBuffer)
        
//        issue is by the time we hit draw, weve updated the uniforms such that we draw our iterated renderables in the same spot... 
        sceneProxy.add(objects)
        
        self.renderer.draw(renderPassDescriptor: renderPassDescriptor,
                           commandBuffer: commandBuffer,
                           scene: sceneProxy,
                           camera: camera ?? self.defaultCamera)
        
        self.lastGraphExecutionTime = executionContext.timing.time

    }
    
    override public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.renderer.resize(size)
        
        self.graphRequiresResize = true
        self.resizeScaleFactor = scaleFactor
        
    }
    
    private func currentGraphExecutionContext() -> GraphExecutionContext
    {
        let currentRenderTime = Date.timeIntervalSinceReferenceDate
        
        // TODO: This becomes more semantically correct later
        let timing = GraphExecutionTiming(time: currentRenderTime,
                                          deltaTime: currentRenderTime - self.lastGraphExecutionTime,
                                          displayTime: currentRenderTime,
                                          systemTime: currentRenderTime,
                                          frameNumber: self.executionCount)
        
        // weird
        return GraphExecutionContext(graphRenderer: self,
                                     timing: timing,
                                     iterationInfo: nil,
                                     eventInfo: nil)
    }
            
//            if let inputFrame = self.frameCache.cachedFrame(fromNode: source, atTime: time)
//            {
//                inputFrames.append(inputFrame)
//            }
//            else
//            {
//                if let _ = nodesWeAreExecuting.firstIndex(of: source)
//                {
//                    // Check if the node has already been processed in the current frame
//                    if let cachedFrame = self.frameCache.cachedFrame(fromNode: source, atTime: self.lastGraphExecutionTime)
//                    {
//                        inputFrames.append(cachedFrame)
//                    }
//                    else
//                    {
//                        print("feedback loop cache miss")
//                    }
//                }
//                else
//                {
//                    if let inputFrame = processGraph(graph: graph,
//                                                     node: source,
//                                                     withCommandBuffer:withCommandBuffer,
//                                                     atTime: time,
//                                                     nodesWeAreExecuting: &nodesWeAreExecuting,
//                                                     pruningConnections:connections)
//                    {
//                        self.frameCache.cacheFrame(frame: inputFrame,
//                                                   fromNode: source,
//                                                   atTime: time)
//                        
//                        inputFrames.append(inputFrame)
//                    }
//                }
//            }
            
//        }
//
//        node.preProcess(atTime:time)
//
//        if let outputFrame = node.process(inputFrames: inputFrames,
//                                          onCommandBuffer: withCommandBuffer,
//                                          atTime: time)
//        {
//            self.frameCache.cacheFrame(frame: outputFrame,
//                                       fromNode: node,
//                                       atTime: time)
//            return outputFrame
//        }
//        
//        return nil
//    }
}

