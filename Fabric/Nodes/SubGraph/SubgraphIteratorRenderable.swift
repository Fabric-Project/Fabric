//
//  SubgraphCustomRenderable.swift
//  Fabric
//
//  Created by Anton Marini on 10/10/25.
//

import Satin
import Metal
import Observation

// PROXY encoder which gives us a hook to Satins internal encoder
// via the Renderable Protocol draw method
// this isnt ideal, as we dont quite match all of the semantics, but we do try.
final class SubgraphIteratorRenderable: Satin.Object, Satin.Renderable
{
    let subGraph:Graph
    var graphContext:GraphExecutionContext? = nil
    var currentCommandBuffer:MTLCommandBuffer? = nil
    var currentRenderPass:MTLRenderPassDescriptor? = nil
    
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
    
    var renderables: [any Satin.Renderable]
    {
        return self.subGraph.renderables
    }

    
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
    
    private var updateCamera:Camera? = nil
    private var updateViewport:simd_float4? = nil
    private var updateIndex:Int?
    
    override func update(renderContext: Context, camera: Camera, viewport: simd_float4, index: Int)
    {
        self.updateCamera = camera
        self.updateViewport = viewport
        self.updateIndex = index
        // We call update inline in draw, which is only so each draw gets the correct latest iterated values on the graph
//        for iteration  in 0..<iterationCount
//        {
//            for r in renderables
//            {
//                r.update(renderContext: renderContext, camera: camera, viewport: viewport, index: index)
//            }
//        }
    }
    
    func draw(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool)
    {
        guard let graphContext,
              let updateCamera,
              let updateViewport,
              let updateIndex,
              let currentRenderPass,
              let currentCommandBuffer
        else { return }
        
        for iteration in 0..<iterationCount
        {
            renderEncoderState.renderEncoder.pushDebugGroup("Iterator \(iteration)")
            
            let iterationInfo = GraphIterationInfo(totalIterationCount: iterationCount,
                                                   currentIteration: iteration)
            
            graphContext.iterationInfo = iterationInfo
            
//            self.subGraph.recursiveMarkDirty()

            // tick graph forward one iteration
            let _ = graphContext.graphRenderer?.execute(graph: self.subGraph,
                                                   executionContext: graphContext,
                                                   renderPassDescriptor:currentRenderPass,
                                                   commandBuffer: currentCommandBuffer)
                        
            for r in self.renderables
            {
                // Since each Mesh / Material / Geom has its own set of buffers
                // Each iteration those buffers do not have a unique pointer address
                // This means we need to copy directly into the encoder
                // This is suboptimal!
                // But this works!
                // Fuck!!
                
                // We should be copying uniforms found in the bindUniforms from
                // Material / Geom / Mesh
                
                if let material = r.material,
                   let uniforms = material.uniforms,
                   let shader = material.shader
                {
                    r.material?.updateUniforms()
                    
                    r.material?.onBind =  { encoder in
                        
                        // Copied from Mesh
                        if let vertexUniforms = r.vertexUniforms[renderContext]
                        {
                            let basePtr = vertexUniforms.buffer.contents().advanced(by: vertexUniforms.offset)
                            let length = vertexUniforms.buffer.length - vertexUniforms.offset
                            
                            if shader.vertexWantsVertexUniforms
                            {
                                renderEncoderState.renderEncoder.setVertexBytes(basePtr, length: length, index: VertexBufferIndex.VertexUniforms.rawValue)
                            }
                            
                            if shader.fragmentWantsVertexUniforms
                            {
                                renderEncoderState.renderEncoder.setFragmentBytes(basePtr, length: length, index: FragmentBufferIndex.VertexUniforms.rawValue)
                            }
                        }
                        
                        // Copied from Material
                        if shader.vertexWantsMaterialUniforms
                        {
                            let basePtr = uniforms.buffer.contents().advanced(by: uniforms.offset)
                            let length = uniforms.buffer.length - uniforms.offset
                            renderEncoderState.renderEncoder.setVertexBytes(basePtr, length: length, index: VertexBufferIndex.MaterialUniforms.rawValue)
                        }
                        
                        if !shadow, material.shader?.fragmentWantsMaterialUniforms ?? false
                        {
                            let basePtr = uniforms.buffer.contents().advanced(by: uniforms.offset)
                            let length = uniforms.buffer.length - uniforms.offset
                            renderEncoderState.renderEncoder.setFragmentBytes(basePtr, length: length, index: FragmentBufferIndex.MaterialUniforms.rawValue)
                        }
                        
//                        for index in shader.vertexBufferBindingIsUsed
//                        {
//                            if let uniformBuffer = material.vertexUniformBuffers[index]
//                            {
//                                let basePtr = uniformBuffer.buffer.contents().advanced(by: uniforms.offset)
//                                let length = uniformBuffer.buffer.length - uniforms.offset
//                                renderEncoderState.renderEncoder.setVertexBytes(basePtr, length: length, index: index.rawValue)
//                            }
//                            else if let structBuffer = material.vertexStructBuffers[index]
//                            {
//                                let basePtr = structBuffer.buffer.contents().advanced(by: structBuffer.offset)
//                                let length = structBuffer.buffer.length - structBuffer.offset
//                                renderEncoderState.renderEncoder.setVertexBytes(basePtr, length: length, index: index.rawValue)
//                            }
//                            else if let buffer = material.vertexBuffers[index]
//                            {
//                                let basePtr = buffer.contents()
//                                let length = buffer.length
//                                renderEncoderState.renderEncoder.setVertexBytes(basePtr, length: length, index: index.rawValue)
//                            }
//                        }
//                        
//                        for index in shader.fragmentBufferBindingIsUsed
//                        {
//                            if let uniformBuffer = material.fragmentUniformBuffers[index]
//                            {
//                                let basePtr = uniformBuffer.buffer.contents().advanced(by: uniforms.offset)
//                                let length = uniformBuffer.buffer.length - uniforms.offset
//                                renderEncoderState.renderEncoder.setFragmentBytes(basePtr, length: length, index: index.rawValue)
//                            }
//                            else if let structBuffer = material.fragmentStructBuffers[index]
//                            {
//                                let basePtr = structBuffer.buffer.contents().advanced(by: structBuffer.offset)
//                                let length = structBuffer.buffer.length - structBuffer.offset
//                                renderEncoderState.renderEncoder.setFragmentBytes(basePtr, length: length, index: index.rawValue)
//                            }
//                            else if let buffer = material.fragmentBuffers[index]
//                            {
//                                let basePtr = buffer.contents()
//                                let length = buffer.length
//                                renderEncoderState.renderEncoder.setFragmentBytes(basePtr, length: length, index: index.rawValue)
//                            }
//                        }
//                        
//                        if let pipeline = shader.getPipeline(renderContext: renderContext, shadow: shadow)
//                        {
//                            renderEncoderState.renderEncoder.setRenderPipelineState(pipeline)
//                        }
                    }
                }
                
                r.update(renderContext: renderContext, camera: updateCamera, viewport: updateViewport, index: updateIndex)

                r.preDraw?(renderEncoderState.renderEncoder)
                
                r.draw(renderContext: renderContext, renderEncoderState: renderEncoderState, shadow: shadow)
                
                r.material?.onBind = nil

            }
            
            //
            renderEncoderState.renderEncoder.popDebugGroup()
            
        }
        
        graphContext.iterationInfo = nil

    }
    
    func execute(context: GraphExecutionContext,
                 renderPassDescriptor: MTLRenderPassDescriptor,
                 commandBuffer: any MTLCommandBuffer)
    {

        // execute the graph once, to just ensure meshes / materials have latest values popogated to nodes
//        self.subGraph.recursiveMarkDirty()
        let _ = context.graphRenderer?.execute(graph: self.subGraph,
                                               executionContext: context,
                                               renderPassDescriptor:renderPassDescriptor ,
                                               commandBuffer: commandBuffer)

    }
}
