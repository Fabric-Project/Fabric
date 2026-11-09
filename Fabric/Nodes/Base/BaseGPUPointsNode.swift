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
/// reports when its inputs changed, and encodes and publishes in `publish`. The kernel compiles
/// synchronously the first time it is needed, and again after `invalidateKernel()`. A kernel that
/// doesn't compile is the node's status, and the node publishes nothing until it changes.
open class BaseGPUPointsNode: Node
{
    override open class var nodeType: Node.NodeType { .Points }

    public var outputPoints: NodePort<Satin.Points> { port(named: "outputPoints") }

    /// The Metal source holding the kernel.
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

    private var compiledPipeline: MTLComputePipelineState?
    private var compileFailure: String?
    /// The kernel changed, so the next execution compiles and publishes.
    private var kernelChanged = true

    /// Compiles the kernel again on the next execution, for a subclass whose source changed.
    public func invalidateKernel()
    {
        compiledPipeline = nil
        compileFailure = nil
        kernelChanged = true
    }

    override open func deriveStatuses() -> [NodeStatus] { compileFailure.map { [NodeStatus.error($0)] } ?? [] }

    override open func execute(renderer: GraphRenderer,
                               executionInfo: GraphExecutionInfo,
                               renderPassDescriptor: MTLRenderPassDescriptor,
                               commandBuffer: MTLCommandBuffer) throws
    {
        let kernelJustChanged = kernelChanged
        kernelChanged = false
        guard kernelJustChanged || inputsChanged() else { return }

        if compiledPipeline == nil, compileFailure == nil
        {
            compileKernel()
        }
        guard let compiledPipeline else
        {
            outputPoints.send(nil, force: true)
            return
        }
        outputPoints.send(try publish(pipeline: compiledPipeline, executionInfo: executionInfo, commandBuffer: commandBuffer), force: true)
    }

    private func compileKernel()
    {
        do
        {
            let library = try context.device.makeLibrary(source: kernelSource, options: nil)
            guard let function = library.makeFunction(name: kernelFunctionName) else
            {
                compileFailure = "The kernel \(kernelFunctionName) was not found."
                subtitleSubject.send()
                return
            }
            compiledPipeline = try context.device.makeComputePipelineState(function: function)
        }
        catch
        {
            compileFailure = error.localizedDescription
        }
        subtitleSubject.send()
    }

    /// Encodes one thread per point, `count` in all.
    public static func dispatchPerPoint(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, count: Int)
    {
        encoder.setComputePipelineState(pipeline)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1))
    }
}
