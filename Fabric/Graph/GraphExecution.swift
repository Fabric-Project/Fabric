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
class GraphExecutionEngine : MetalViewRenderer
{
    private var lastGraphExecutionTime = Date.timeIntervalSinceReferenceDate

    var context:Context!
    
    let graph:Graph
    
    init(context:Context, graph:Graph)
    {
        self.context = context
        self.graph = graph
        print("Init Graph Execution Engine")
    }
    
    // MARK: - Rendering

    func execute(graph:Graph, atTime time:TimeInterval, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer:MTLCommandBuffer)
    {
        var nodesWeAreExecuting:[Node] = []
        let delta = time - self.lastGraphExecutionTime

        let renderNodes = graph.nodes.filter( { $0.nodeType == .Renderer })
        
        for renderNode in renderNodes
        {
            let _ = processGraph(graph:graph,
                                 node: renderNode,
                                 renderPassDescriptor: renderPassDescriptor,
                                 commandBuffer: commandBuffer,
                                 atTime:time,
                                 nodesWeAreExecuting:&nodesWeAreExecuting)
        }
        
        self.lastGraphExecutionTime = time
    }

    private func processGraph(graph:Graph,
                              node: Node,
                              renderPassDescriptor: MTLRenderPassDescriptor,
                              commandBuffer: MTLCommandBuffer,
                              atTime time:TimeInterval,
                              nodesWeAreExecuting:inout  [Node],
                              pruningNodes:[Node] = [])
    {
        
        // get the connection for
        let inputNodes = node.inputNodes()
                
        for node in inputNodes
        {
            processGraph(graph: graph,
                         node: node,
                         renderPassDescriptor: renderPassDescriptor,
                         commandBuffer: commandBuffer,
                         atTime: time,
                         nodesWeAreExecuting: &nodesWeAreExecuting,
                         pruningNodes:inputNodes)
        }
        
        if node.isDirty
        {
            node.evaluate(atTime: time, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
            
            node.isDirty = false

            node.lastEvaluationTime = time
        }
    }
    
    override  func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    {
        self.execute(graph:self.graph,
                     atTime: Date.timeIntervalSinceReferenceDate,
                     renderPassDescriptor: renderPassDescriptor,
                     commandBuffer: commandBuffer)
    }
    
    override public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.graph.nodes.forEach { $0.resize(size: size, scaleFactor: scaleFactor)}
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

