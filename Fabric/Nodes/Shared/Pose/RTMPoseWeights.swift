// RTMPoseWeights.swift
//
// Loads the flat binary blob + JSON manifest produced by export_weights.py
// and hands out MPSGraph constant tensors by name.

import Foundation
import MetalPerformanceShadersGraph

final class RTMPoseWeights
{
    private struct Entry: Decodable
    {
        let offset: Int
        let shape: [Int]
        let dtype: String
    }

    private let manifest: [String: Entry]
    private let data: Data

    init(binaryURL: URL, manifestURL: URL) throws
    {
        self.data = try Data(contentsOf: binaryURL)
        let manifestData = try Data(contentsOf: manifestURL)
        self.manifest = try JSONDecoder().decode([String: Entry].self, from: manifestData)
    }

    /// Raw float32 values for a named tensor, in the same flattened
    /// row-major order PyTorch's .numpy() produced them in.
    func floatArray(named name: String) -> [Float]
    {
        guard let entry = manifest[name] else
        {
            fatalError("RTMPoseWeights: missing tensor '\(name)'")
        }

        let elementCount = entry.shape.reduce(1, *)
        let byteOffset = entry.offset * MemoryLayout<Float>.stride
        let byteCount = elementCount * MemoryLayout<Float>.stride

        var values = [Float](repeating: 0, count: elementCount)
        self.data.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.baseAddress!.advanced(by: byteOffset)
            values.withUnsafeMutableBytes { destination in
                destination.copyMemory(from: UnsafeRawBufferPointer(start: source, count: byteCount))
            }
        }
        return values
    }

    func shape(named name: String) -> [Int]
    {
        guard let entry = manifest[name] else
        {
            fatalError("RTMPoseWeights: missing tensor '\(name)'")
        }
        return entry.shape
    }

    /// Builds an MPSGraph constant tensor directly from the named weight,
    /// in its native PyTorch shape (OIHW for conv weights, [out, in] for
    /// linear weights — callers transpose/reshape as needed per op).
    func constant(_ graph: MPSGraph, named name: String) -> MPSGraphTensor
    {
        let values = self.floatArray(named: name)
        let shape = self.shape(named: name).map { NSNumber(value: $0) }
        return graph.constant(Data(bytes: values, count: values.count * MemoryLayout<Float>.stride), shape: shape, dataType: .float32)
    }
}
