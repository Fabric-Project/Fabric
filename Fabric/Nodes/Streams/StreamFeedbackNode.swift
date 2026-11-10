//
//  StreamFeedbackNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin

/// Last frame's stream: the loop that keeps state from frame to frame. Wire a stream computed from
/// this node's output back into its Stream input. It runs before the nodes that feed it, since it
/// never pulls its Stream input, so it sends what that input received last frame, which no one
/// writes again because a published stream never changes. With nothing received yet, or while
/// Reset is on, it sends Initial instead. Inside an Iterator each iteration keeps its own loop, so
/// one iteration's particles never feed another's.
public final class StreamFeedbackNode: StrategyNode
{
    override public class var name: String { "Stream Feedback" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Sends last frame's Stream, to keep state from frame to frame: wire a stream computed from this output back into Stream. Sends Initial on the first frame and while Reset is on. Choose the element type in Settings." }

    override public class var strategyOptions: [any NodeStrategyOption] { PortType.streamElementTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputReset", ParameterPort(parameter: BoolParameter("Reset", false, .button, "Sends Initial instead of last frame's Stream"))),
        ]
    }

    public var inputReset: ParameterPort<Bool> { port(named: "inputReset") }

    public var elementType: PortType { strategyOption(as: PortType.self) ?? .Float }

    // Resolved when the element type changes, so execution and pulls look up nothing.
    private var resolvedInput: (any GPUStreamPort)?
    private var resolvedInitial: (any GPUStreamPort)?
    private var resolvedOutput: (any GPUStreamPort)?
    /// Every inlet but Stream: what each pass pulls before this node runs.
    private var pulledPorts: [Port] = []

    /// Each iteration's last received stream, indexed by the enclosing Iterator's current iteration,
    /// or 0 outside one. Only the innermost Iterator's index is known, so nested Iterators share.
    private var history = ContiguousArray<AnyGPUStream?>()
    /// The iteration this node last ran for: what its Stream input received since belongs to it.
    private var lastIteration: Int?
    /// Stream as it was when this node last ran, so a stream is credited to one iteration only.
    private var lastSeenInput: AnyGPUStream?

    override public func rebuildPorts(forStrategy strategy: (any NodeStrategyOption)?)
    {
        super.rebuildPorts(forStrategy: strategy)
        // Streams of the old element type can't be sent on the new ports.
        history.removeAll()
        lastIteration = nil
        lastSeenInput = nil
        guard let elementType = strategy as? PortType else { return }

        let streamType = PortType.Stream(elementType: elementType)
        addOrReplaceDynamicPortPreservingIdentity(name: "inputStream", displayName: "Stream", portType: streamType,
                                                  kind: .Inlet, description: "The stream to send next frame")
        addOrReplaceDynamicPortPreservingIdentity(name: "inputInitial", displayName: "Initial", portType: streamType,
                                                  kind: .Inlet, description: "Sent on the first frame and while Reset is on")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputStream", displayName: "Stream", portType: streamType,
                                                  kind: .Outlet, description: "Last frame's Stream, or Initial")

        let portOrder = ["inputStream", "inputInitial", "inputReset", "outputStream"]
        let reordered: [Port] = portOrder.compactMap { name in let port: Port? = findPort(named: name); return port }
        if reordered.count == self.ports.count { reorderPorts(reordered) }

        let input: Port? = findPort(named: "inputStream")
        let initial: Port? = findPort(named: "inputInitial")
        let output: Port? = findPort(named: "outputStream")
        let reset: Port? = findPort(named: "inputReset")
        resolvedInput = input as? any GPUStreamPort
        resolvedInitial = initial as? any GPUStreamPort
        resolvedOutput = output as? any GPUStreamPort
        pulledPorts = [initial, reset].compactMap { $0 }
    }

    /// Never pulls Stream: what feeds it is computed from this node's output, so it runs after.
    override public func respondToPull(requestedOutputPort: Port?) -> PullResponse
    {
        .evaluate(pulling: pulledPorts)
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        guard let output = resolvedOutput else { return }

        // Stream holds what the loop computed after this node last ran, for the iteration it ran
        // for, unless nothing has arrived since.
        let received = resolvedInput?.currentStream
        if let lastIteration, received != lastSeenInput
        {
            while history.count <= lastIteration { history.append(nil) }
            history[lastIteration] = received
        }
        lastSeenInput = received

        let iteration = executionInfo.iterationInfo?.currentIteration ?? 0
        lastIteration = iteration

        let previous = (inputReset.value ?? false) || iteration >= history.count ? nil : history[iteration]
        guard let stream = previous ?? resolvedInitial?.currentStream else
        {
            output.clearStream()
            return
        }
        try output.sendStream(attribute: stream.attribute, count: stream.count)
    }
}
