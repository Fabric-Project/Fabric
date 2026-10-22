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

    /// Last frame's iteration count: motion pairs iteration k with last frame's iteration k, so a
    /// change starts every renderable still.
    private var previousIterationCount = 0

    public required init(context: Context)
    {
        super.init(context: context)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }
    
    override var startsAllChildNodes: Bool { true }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        let iterationCount = resolvedIterationCount()
        guard iterationCount > 0 else {
            executionInfo.iterationInfo = nil
            self.forwardPortValues(force:true)
            return
        }

        let subgraphIndex = subGraph.scene.sceneIndex
        if iterationCount != previousIterationCount {
            for renderable in renderables(in: subgraphIndex) {
                renderable.resetMotion()
            }
            previousIterationCount = iterationCount
        }

        // Each iteration is recorded into the frame's submission as it is now: its transforms,
        // uniforms, instances and poses are snapshotted, so the next iteration's changes don't reach it.
        let submission = renderer.frameSubmission(frame: executionInfo.timing)
        let encodingContext = submission.encodingContext(commandBuffer: commandBuffer)

        for iteration in 0..<iterationCount
        {
            let iterationInfo = GraphIterationInfo(totalIterationCount: iterationCount,
                                                   currentIteration: iteration)
            executionInfo.iterationInfo = iterationInfo

            let needsSceneSync = subGraph.consumePendingConnectionSceneSync()

            try renderer.execute(graph: subGraph,
                                 executionInfo: executionInfo,
                                 renderPassDescriptor: renderPassDescriptor,
                                 commandBuffer: commandBuffer,
                                 clearFlags: false,
                                 forceEvaluationForTheseNodes: subGraph.nodes)

            if needsSceneSync
            {
                subGraph.syncNodesToScene()
            }

            // Recording neither updates nor encodes: do both first.
            subGraph.scene.update()
            subGraph.scene.encode(in: encodingContext)
            for entry in subGraph.scene.sceneIndex.entries {
                entry.object.update()
                entry.object.encode(in: encodingContext)
            }
            try submission.record(scene: subGraph.scene)
        }

        executionInfo.iterationInfo = nil

        // We need to call this to ensure any published port values also get forwarded.
        self.forwardPortValues(force:true)
    }

    private func resolvedIterationCount() -> Int {
        for connection in inputIteratonCount.connectedOutlets {
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

    /// The subgraph scene's renderables, its root included, in the scene's order.
    private func renderables(in subgraphIndex: SceneIndex) -> [Renderable] {
        guard let sceneRenderable = subGraph.scene as? Renderable else { return subgraphIndex.renderables }
        return [sceneRenderable] + subgraphIndex.renderables
    }
}
