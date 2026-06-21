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
final class SubgraphIteratorRenderable: Satin.Renderable
{
    var subGraph:Graph? = nil
    {
        didSet
        {
            if let oldScene = oldValue?.scene {
                self.remove(oldScene)
            }

            // Do not parent the subgraph scene under this proxy. Satin's RenderEncoder
            // recursively collects visible descendants, which would draw iterator child
            // meshes once outside this loop with the final iteration's values.
            preparedForCount = 0  // force re-prepare when subgraph changes
        }
    }

    var graphRenderer:GraphRenderer? = nil
    var graphExecutionInfo:GraphExecutionInfo? = nil
    var currentCommandBuffer:MTLCommandBuffer? = nil
    var currentRenderPass:MTLRenderPassDescriptor? = nil

    init(context:Context, iterationCount: Int)
    {
        self.iterationCount = iterationCount

        super.init(context:context)

        self.doubleSided = false
        self.renderOrder = 0
        self.receiveShadow = false
        self.castShadow = false
        self.cullMode = .back
        self.windingOrder = .counterClockwise
        self.triangleFillMode = .fill
        // A material is required so Satin's shouldRender() passes and draw() is called.
        // This material is not used for drawing in any way.
        self.material = BasicColorMaterial(context: context)
    }

    required init(from decoder: any Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    var iterationCount: Int {
        didSet {
            if iterationCount != oldValue {
                preparedForCount = 0  // force re-prepare on next draw
            }
        }
    }

    private var updateCamera:Camera? = nil
    private var updateViewport:simd_float4? = nil
    private var updateIndex:Int?

    // Tracks the last count we called prepareForRepeatedEncoding with, per renderable identity.
    private var preparedForCount: Int = 0
    private var preparedRenderableCount: Int = 0

    override func isDrawable(renderContext: Satin.Context, shadow: Bool) -> Bool {
        true
    }

    override func update(renderContext: Context, camera: Camera, viewport: simd_float4, index: Int)
    {
        // Store camera/viewport so each per-iteration draw can use them.
        self.updateCamera = camera
        self.updateViewport = viewport
        self.updateIndex = index
    }

    override func draw(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool)
    {
        guard let subGraph,
              let updateCamera,
              let updateViewport,
              let updateIndex
        else { return }

        if subGraph.shouldUpdateConnections {
            subGraph.syncNodesToScene()
            subGraph.shouldUpdateConnections = false
        }

        let subgraphObjects = [subGraph.scene] + subGraph.scene.getChildren()
        let renderableChildren = subgraphObjects
            .compactMap { $0 as? Renderable }
            .filter(\.isVisible)
            .sorted { $0.renderOrder < $1.renderOrder }

        for iteration in 0..<iterationCount
        {
            renderEncoderState.renderEncoder.pushDebugGroup("Iterator \(iteration)")

            for renderable in renderableChildren {
                renderable.selectRepeatedEncodingSlot(iteration: iteration, count: iterationCount)

                if renderable.vertexUniforms[renderContext.id] == nil {
                    renderable.vertexUniforms[renderContext.id] = VertexUniformBuffer(
                        context: renderContext.with(iterationsPerFrame: iterationCount)
                    )
                }

                renderable.update(renderContext: renderContext,
                                  camera: updateCamera,
                                  viewport: updateViewport,
                                  index: updateIndex)

                guard renderable.isDrawable(renderContext: renderContext, shadow: shadow) else { continue }

                renderable.preDraw?(renderEncoderState.renderEncoder)

                renderEncoderState.windingOrder = renderable.windingOrder
                renderEncoderState.triangleFillMode = renderable.triangleFillMode

                if renderable.doubleSided, renderable.cullMode == .none, renderable.opaque == false {
                    renderEncoderState.cullMode = .front
                    renderable.draw(renderContext: renderContext, renderEncoderState: renderEncoderState, shadow: shadow)

                    renderEncoderState.cullMode = .back
                    renderable.draw(renderContext: renderContext, renderEncoderState: renderEncoderState, shadow: shadow)
                }
                else {
                    renderEncoderState.cullMode = renderable.cullMode
                    renderable.draw(renderContext: renderContext, renderEncoderState: renderEncoderState, shadow: shadow)
                }
            }
            

            renderEncoderState.renderEncoder.popDebugGroup()
        }
    }

    func startExecution(renderer:GraphRenderer)
    {
        guard let subGraph else { return }
        renderer.startExecution(graph: subGraph)
    }

    func stopExecution(renderer:GraphRenderer)
    {
        guard let subGraph else { return }
        renderer.stopExecution(graph: subGraph)
    }

    func enableExecution(renderer:GraphRenderer)
    {
        guard let subGraph else { return }
        renderer.enableExecution(graph: subGraph)
    }

    func disableExecution(renderer:GraphRenderer)
    {
        guard let subGraph else { return }
        renderer.disableExecution(graph: subGraph)
    }

    public func execute(renderer:GraphRenderer,
                        executionInfo:GraphExecutionInfo,
                        renderPassDescriptor: MTLRenderPassDescriptor,
                        commandBuffer: MTLCommandBuffer)
    {
        guard let subGraph else { return }

        if subGraph.shouldUpdateConnections {
            subGraph.syncNodesToScene()
            subGraph.shouldUpdateConnections = false
        }

        for iteration in 0..<iterationCount {
            let iterationInfo = GraphIterationInfo(totalIterationCount: iterationCount,
                                                   currentIteration: iteration)
            executionInfo.iterationInfo = iterationInfo

            renderer.execute(graph: subGraph,
                             executionInfo: executionInfo,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer,
                             clearFlags: false,
                             forceEvaluationForTheseNodes: subGraph.nodes)

            if subGraph.shouldUpdateConnections {
                subGraph.syncNodesToScene()
                subGraph.shouldUpdateConnections = false
            }

            let subgraphObjects = [subGraph.scene] + subGraph.scene.getChildren()
            let renderableChildren = subgraphObjects.compactMap { $0 as? Renderable }

            if iterationCount != preparedForCount || renderableChildren.count != preparedRenderableCount {
                for renderable in renderableChildren {
                    renderable.prepareForRepeatedEncoding(count: iterationCount)
                }
                preparedForCount = iterationCount
                preparedRenderableCount = renderableChildren.count
            }

            for object in subgraphObjects {
                object.update()
                object.encode(commandBuffer)
            }
        }

        executionInfo.iterationInfo = nil
    }
}
