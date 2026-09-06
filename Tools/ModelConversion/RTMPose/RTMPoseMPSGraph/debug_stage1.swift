// debug_stage1.swift
//
// Traces the exact same sub-steps as dump_stage1_internals.py, starting
// from the stem's output, to localize which specific op inside stage1
// diverges from PyTorch.
//
// Build & run (separate binary from rtmpose_validate — has its own main):
//   swiftc -O RTMPoseWeights.swift RTMPoseMPSGraph.swift debug_stage1.swift -o debug_stage1 \
//     -framework MetalPerformanceShadersGraph -framework Metal
//   ./debug_stage1 RTMPoseHandMedium_weights.bin RTMPoseHandMedium_weights.json stages_stem.bin stage1_trace

import Foundation
import Metal
import MetalPerformanceShadersGraph

guard CommandLine.arguments.count > 4 else
{
    print("usage: debug_stage1 weights.bin weights.json stem_output.bin reference_prefix")
    exit(1)
}

let weightsBinaryURL = URL(fileURLWithPath: CommandLine.arguments[1])
let weightsManifestURL = URL(fileURLWithPath: CommandLine.arguments[2])
let stemInputURL = URL(fileURLWithPath: CommandLine.arguments[3])
let referencePrefix = CommandLine.arguments[4]

func loadFloatArray(_ url: URL) throws -> [Float]
{
    let data = try Data(contentsOf: url)
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

func maxAbsDifference(_ a: [Float], _ b: [Float]) -> Float
{
    guard a.count == b.count else { print("SHAPE MISMATCH: \(a.count) vs \(b.count)"); return .infinity }
    return zip(a, b).map { abs($0 - $1) }.max() ?? 0
}

guard let device = MTLCreateSystemDefaultDevice() else { print("No Metal device"); exit(1) }
let mpsDevice = MPSGraphDevice(mtlDevice: device)
let weights = try RTMPoseWeights(binaryURL: weightsBinaryURL, manifestURL: weightsManifestURL)
let graph = MPSGraph()

let stemInput = graph.placeholder(shape: [1, 48, 128, 128], dataType: .float32, name: "stemOutput")

let downsample = RTMPoseMPSGraph.convModule(graph: graph, weights: weights, x: stemInput, exportName: "backbone.stage1.downsample", stride: 2)
let mainConv = RTMPoseMPSGraph.convModule(graph: graph, weights: weights, x: downsample, exportName: "backbone.stage1.csp.main_conv", stride: 1)
let shortConv = RTMPoseMPSGraph.convModule(graph: graph, weights: weights, x: downsample, exportName: "backbone.stage1.csp.short_conv", stride: 1)
let block0 = RTMPoseMPSGraph.cspNeXtBlock(graph: graph, weights: weights, x: mainConv, exportPrefix: "backbone.stage1.csp.block0", addIdentity: true)
let block1 = RTMPoseMPSGraph.cspNeXtBlock(graph: graph, weights: weights, x: block0, exportPrefix: "backbone.stage1.csp.block1", addIdentity: true)
let concat = graph.concatTensors([block1, shortConv], dimension: 1, name: nil)
let attention = RTMPoseMPSGraph.channelAttention(graph: graph, weights: weights, x: concat, exportPrefix: "backbone.stage1.csp.attention")
let finalConv = RTMPoseMPSGraph.convModule(graph: graph, weights: weights, x: attention, exportName: "backbone.stage1.csp.final_conv", stride: 1)

let namedTensors: [(String, MPSGraphTensor)] = [
    ("downsample", downsample),
    ("main_conv", mainConv),
    ("short_conv", shortConv),
    ("block0", block0),
    ("block1", block1),
    ("concat", concat),
    ("attention", attention),
    ("final_conv", finalConv),
]

let stemPixels = try loadFloatArray(stemInputURL)
let inputData = MPSGraphTensorData(device: mpsDevice, data: Data(bytes: stemPixels, count: stemPixels.count * MemoryLayout<Float>.stride), shape: stemInput.shape!, dataType: .float32)

let results = graph.run(feeds: [stemInput: inputData], targetTensors: namedTensors.map(\.1), targetOperations: nil)

for (name, tensor) in namedTensors
{
    let count = tensor.shape!.map(\.intValue).reduce(1, *)
    var ours = [Float](repeating: 0, count: count)
    results[tensor]!.mpsndarray().readBytes(&ours, strideBytes: nil)

    guard let reference = try? loadFloatArray(URL(fileURLWithPath: "\(referencePrefix)_\(name).bin")) else
    {
        print("(no reference file for \(name), skipping)")
        continue
    }

    let diff = maxAbsDifference(ours, reference)
    let status = diff < 1e-2 ? "✅" : "❌"
    print("\(status) \(name): max abs diff \(diff)")
    if diff >= 1e-2
    {
        print("   ours[0..3]:", Array(ours.prefix(3)))
        print("   ref[0..3]: ", Array(reference.prefix(3)))
    }
}
