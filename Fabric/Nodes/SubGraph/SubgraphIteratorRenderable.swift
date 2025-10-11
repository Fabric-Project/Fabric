//
//  SubgraphCustomRenderable.swift
//  Fabric
//
//  Created by Anton Marini on 10/10/25.
//

import Satin
import Metal

// PROXY encoder which gives us a hook to Satins internal encoder
// via the Renderable Protocol draw method
// this isnt ideal, as we dont quite match all of the semantics, but we do try.
final class SubgraphIteratorRenderable: Satin.Object, Satin.Renderable
{
    let subGraph:Graph
    var graphContext:GraphExecutionContext? = nil
    
    init(subGraph:Graph, iterationCount: Int)
    {
        
        self.subGraph = subGraph
        self.iterationCount = iterationCount
//        self.vertexUniforms = vertexUniforms
        self.vertexUniforms = [:]
        
        super.init()
    }
    
    required init(from decoder: any Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }
    
    var renderables: [any Satin.Renderable]  {
        self.subGraph.renderables
    } // children resolved once per frame
   
    var iterationCount: Int

    //  Satin.Renderable
    
    var opaque: Bool {
        self.renderables.reduce(false) { partialResult, aRenderable in
            return partialResult || aRenderable.opaque
        }
    }
    
    var doubleSided: Bool {
        self.renderables.reduce(false) { partialResult, aRenderable in
            return partialResult || aRenderable.doubleSided
        }
    }
    
    var renderOrder: Int { 0 }
    
    var renderPass: Int { 0 }
    
    var lighting: Bool {
       self.renderables.reduce(false) { partialResult, aRenderable in
            return partialResult || aRenderable.lighting
        }
    }
    
    var receiveShadow: Bool {
       self.renderables.reduce(false) { partialResult, aRenderable in
            return partialResult || aRenderable.receiveShadow
        }
    }
    
    var castShadow: Bool {
        self.renderables.reduce(false) { partialResult, aRenderable in
            return partialResult || aRenderable.castShadow
        }
    }
    
    var cullMode: MTLCullMode { .back }
    
    var windingOrder: MTLWinding { .counterClockwise }
    
    var triangleFillMode: MTLTriangleFillMode { .fill }
    
    var vertexUniforms: [Satin.Context : Satin.VertexUniformBuffer]
    
    func isDrawable(renderContext: Satin.Context, shadow: Bool) -> Bool {
        self.renderables.reduce(false) { partialResult, aRenderable in
            return partialResult || aRenderable.isDrawable(renderContext: renderContext, shadow: shadow)
        }
    }
    
    var material: Satin.Material? = nil
    
    var materials: [Satin.Material] = []
    
    var preDraw: ((any MTLRenderCommandEncoder) -> Void)? = nil
    
//    let computeNodes: [any NodeProtocol]          // non-renderables to eval each iter
//    let publishIter: (Int) -> Void            // closure to set index/progress ports
    
    
    override func update(renderContext: Context, camera: Camera, viewport: simd_float4, index: Int)
    {
        for iteration  in 0..<iterationCount
        {
            for r in renderables
            {
                r.update(renderContext: renderContext, camera: camera, viewport: viewport, index: index)
            }
        }
    }
    
    func draw(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool)
    {
        for iteration in 0..<iterationCount
        {
            for r in renderables
            {
                r.preDraw?(renderEncoderState.renderEncoder)
                r.draw(renderContext: renderContext, renderEncoderState: renderEncoderState, shadow: shadow)
            }
        }
    }
    
    func execute(context: GraphExecutionContext,
                 renderPassDescriptor: MTLRenderPassDescriptor,
                 commandBuffer: any MTLCommandBuffer)
    {
        for iteration  in 0..<iterationCount
        {
            let iterationInfo = GraphIterationInfo(totalIterationCount: iterationCount,
                                                   currentIteration: iteration)
            
            context.iterationInfo = iterationInfo
            
            // this is so dumb
            let _ = context.graphRenderer?.execute(graph: self.subGraph,
                                                   executionContext: context,
                                                   renderPassDescriptor:renderPassDescriptor ,
                                                   commandBuffer: commandBuffer)
            
            // ??
            self.subGraph.recursiveMarkDirty()
            // Encode child draws (same encoder)
            
        }
    }
}
