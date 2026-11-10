//
//  ComputeKernel.swift
//  Fabric
//

import Foundation
import Metal

/// Compute kernels compiled from one source, synchronously, by `compile`, which a node calls when it
/// is enabled or its source changes, never from `execute`. Execution reads `pipelines`. A source that
/// doesn't compile leaves `failure` until the next compile.
final class ComputeKernel
{
    /// The compiled kernels in `compile`'s `functionNames` order; nil before a compile, or when it failed.
    private(set) var pipelines: [MTLComputePipelineState]?
    private(set) var failure: String?

    /// Compiles `functionNames` from `source`, replacing what was compiled before.
    func compile(source: String, functionNames: [String], device: MTLDevice)
    {
        pipelines = nil
        failure = nil
        do
        {
            let library = try device.makeLibrary(source: source, options: nil)
            var compiled: [MTLComputePipelineState] = []
            for functionName in functionNames
            {
                guard let function = library.makeFunction(name: functionName) else
                {
                    failure = "The kernel \(functionName) was not found."
                    return
                }
                compiled.append(try device.makeComputePipelineState(function: function))
            }
            pipelines = compiled
        }
        catch
        {
            failure = error.localizedDescription
        }
    }

    /// Drops the compiled kernels, for a node that is disabled.
    func release()
    {
        pipelines = nil
        failure = nil
    }
}
