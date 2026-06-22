//
//  SubgraphNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/22/25.
//

import Foundation
import Satin
import simd
import Metal

public class IteratorNode: SubgraphNode
{
    public override class var name:String { "Iterator" }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeDescription: String { "Execute a Sub Graph n number of times"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputIteratonCount", ParameterPort(parameter: IntParameter("Iterations", 0, 100, 2, .inputfield, "Number of times to execute the subgraph"))),
        ]
    }
    
    // Port Proxy
    public var inputIteratonCount:ParameterPort<Int> { port(named: "inputIteratonCount") }
        
    // Ensure we always render!
    override public var isDirty:Bool { get {  true  } set { } }

    override public var object:Object? {
        nil
    }

    private var preparedForCount: Int = 0
    private var preparedRenderableIdentifiers = Set<ObjectIdentifier>()

    public required init(context: Context)
    {
        super.init(context: context)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }
    
    override public func startExecution(renderer:GraphRenderer)
    {
        renderer.startExecution(graph: self.subGraph)
    }
    
    override public func stopExecution(renderer:GraphRenderer)
    {
        renderer.stopExecution(graph: self.subGraph)
    }

    override public func enableExecution(renderer:GraphRenderer)
    {
        renderer.enableExecution(graph: self.subGraph)
    }
    
    override public func disableExecution(renderer:GraphRenderer)
    {
        renderer.disableExecution(graph: self.subGraph)
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let iterationCount = resolvedIterationCount()
        guard iterationCount > 0 else {
            executionInfo.iterationInfo = nil
            self.forwardPortValues(force:true)
            return
        }

        var subgraphObjects = objectsInSubgraph()
        var renderableChildren = renderables(in: subgraphObjects)
        
        prepareRepeatedEncodingIfNeeded( renderables: renderableChildren,
                                         count: iterationCount)

        for iteration in 0..<iterationCount
        {
            let iterationInfo = GraphIterationInfo(totalIterationCount: iterationCount,
                                                   currentIteration: iteration)
            executionInfo.iterationInfo = iterationInfo

            
            let needsSceneSync = subGraph.shouldUpdateConnections
            subGraph.shouldUpdateConnections = false

            renderer.execute(graph: subGraph,
                             executionInfo: executionInfo,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer,
                             clearFlags: false,
                             forceEvaluationForTheseNodes: subGraph.nodes)

            if needsSceneSync
            {
                subGraph.syncNodesToScene()
            }
            
            subgraphObjects = objectsInSubgraph()
            renderableChildren = renderables(in: subgraphObjects)
            
//            // This resizes buffers if , doesnt encode.
//            prepareRepeatedEncodingIfNeeded(
//                renderables: renderableChildren,
//                count: iterationCount
//            )

            for object in subgraphObjects {
                object.update()
                object.encode(commandBuffer)
            }
        }

        executionInfo.iterationInfo = nil

        let renderablesByLayer = Dictionary(grouping: renderableChildren) {
            $0.renderLayer.rawValue
        }

        for renderLayer in renderablesByLayer.keys.sorted() {
            guard let layerRenderables = renderablesByLayer[renderLayer] else { continue }
            renderer.renderEncoder.scheduleCurrentPassEncoding(
                renderables: layerRenderables
            ) { [weak renderer] renderEncoderState in
                guard let renderEncoder = renderer?.renderEncoder else { return }

                for iteration in 0..<iterationCount {
                    renderEncoderState.renderEncoder.pushDebugGroup("Iterator \(iteration)")
                    renderEncoder.encodeCurrentPass(
                        renderables: layerRenderables,
                        renderEncoderState: renderEncoderState,
                        repeatedIteration: iteration,
                        repeatedCount: iterationCount
                    )
                    renderEncoderState.renderEncoder.popDebugGroup()
                }
            }
        }

        // We need to call this to ensure any published port values also get forwarded.
        self.forwardPortValues(force:true)
    }

    private func objectsInSubgraph() -> [Object] {
        [subGraph.scene] + subGraph.scene.getChildren()
    }

    private func resolvedIterationCount() -> Int {
        for connection in inputIteratonCount.connections where connection.kind == .Outlet {
            if let port = connection as? NodePort<Int>,
               let count = port.value
            {
                return count
            }

            if let boxed = connection.snapshotValue(),
               let count = Int.fromPortValue(boxed)
            {
                return count
            }
        }

        return inputIteratonCount.value ?? 1
    }

    private func renderables(in objects: [Object]) -> [Renderable] {
        objects.compactMap { $0 as? Renderable }
    }

    private func prepareRepeatedEncodingIfNeeded(
        renderables: [Renderable],
        count: Int
    ) {
        let renderableIdentifiers = Set(renderables.map { ObjectIdentifier($0) })
        guard count != preparedForCount ||
            renderableIdentifiers != preparedRenderableIdentifiers
        else { return }

        for renderable in renderables {
            renderable.prepareForRepeatedEncoding(count: count)
        }

        preparedForCount = count
        preparedRenderableIdentifiers = renderableIdentifiers
    }
}
