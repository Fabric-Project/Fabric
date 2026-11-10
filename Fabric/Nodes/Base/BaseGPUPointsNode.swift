//
//  BaseGPUPointsNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

/// Base for nodes that publish Points from a compute kernel.
///
/// A subclass registers an `outputPoints` port, gives its kernel's source and function name,
/// reports when its inputs changed, and encodes and publishes in `publish`. The kernel compiles,
/// synchronously, when the node is enabled and when `recompileKernel()` says its source changed,
/// never in `execute`. A kernel that doesn't compile is the node's status, and the node publishes
/// nothing until it changes.
open class BaseGPUPointsNode: Node
{
    override open class var nodeType: Node.NodeType { .Points }

    public var outputPoints: NodePort<Satin.Points> { port(named: "outputPoints") }

    /// The Metal source holding the kernel. Read only to compile it.
    open var kernelSource: String { "" }

    /// The kernel's function name in `kernelSource`.
    open var kernelFunctionName: String { "" }

    /// Whether this execution's inputs ask for new points.
    open func inputsChanged() -> Bool { false }

    /// Encodes the kernel into `commandBuffer` and returns the points it writes, or nil for none.
    open func publish(pipeline: MTLComputePipelineState, executionInfo: GraphExecutionInfo,
                      commandBuffer: MTLCommandBuffer) throws -> Satin.Points?
    {
        nil
    }

    private let kernel = ComputeKernel()
    /// The kernel changed, so the next execution publishes whatever the inputs say.
    private var kernelChanged = true

    /// Compiles the kernel again now, for a subclass whose source changed, if the node is enabled;
    /// a disabled node compiles when it is enabled.
    public func recompileKernel()
    {
        guard executionState != .disabled else { return }
        compileKernel()
    }

    private func compileKernel()
    {
        kernel.compile(source: kernelSource, functionNames: [kernelFunctionName], device: context.device)
        kernelChanged = true
        subtitleSubject.send()
    }

    override open func enableExecution(renderer: GraphRenderer) throws
    {
        compileKernel()
        try super.enableExecution(renderer: renderer)
    }

    override open func disableExecution(renderer: GraphRenderer) throws
    {
        kernel.release()
        try super.disableExecution(renderer: renderer)
    }

    override open func deriveStatuses() -> [NodeStatus] { kernel.failure.map { [NodeStatus.error($0)] } ?? [] }

    /// What the last compile reported, or nil when it compiled or hasn't run.
    public var kernelFailure: String? { kernel.failure }

    override open func execute(renderer: GraphRenderer,
                               executionInfo: GraphExecutionInfo,
                               renderPassDescriptor: MTLRenderPassDescriptor,
                               commandBuffer: MTLCommandBuffer) throws
    {
        let kernelJustChanged = kernelChanged
        kernelChanged = false
        guard kernelJustChanged || inputsChanged() else { return }

        guard let pipeline = kernel.pipelines?.first else
        {
            outputPoints.send(nil, force: true)
            return
        }
        outputPoints.send(try publish(pipeline: pipeline, executionInfo: executionInfo, commandBuffer: commandBuffer), force: true)
    }

    /// Encodes one thread per point, `count` in all.
    public static func dispatchPerPoint(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, count: Int)
    {
        encoder.setComputePipelineState(pipeline)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1))
    }
}
