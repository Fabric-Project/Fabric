// main.swift
//
// Validates RTMPoseMPSGraph against the PyTorch reference dumped by
// dump_reference_io.py. Standalone — not part of the Fabric app/build.
//
// Build & run:
//   swiftc -O RTMPoseWeights.swift RTMPoseMPSGraph.swift main.swift -o rtmpose_validate \
//     -framework MetalPerformanceShadersGraph -framework Metal
//   ./rtmpose_validate RTMPoseHandMedium_weights.bin RTMPoseHandMedium_weights.json \
//     reference_io_input.bin reference_io_simcc_x.bin reference_io_simcc_y.bin

import Foundation
import Metal

guard CommandLine.arguments.count > 6 else
{
    print("usage: rtmpose_validate weights.bin weights.json input.bin reference_backbone.bin reference_simcc_x.bin reference_simcc_y.bin")
    exit(1)
}

let weightsBinaryURL = URL(fileURLWithPath: CommandLine.arguments[1])
let weightsManifestURL = URL(fileURLWithPath: CommandLine.arguments[2])
let inputURL = URL(fileURLWithPath: CommandLine.arguments[3])
let referenceBackboneURL = URL(fileURLWithPath: CommandLine.arguments[4])
let referenceSimccXURL = URL(fileURLWithPath: CommandLine.arguments[5])
let referenceSimccYURL = URL(fileURLWithPath: CommandLine.arguments[6])

func loadFloatArray(_ url: URL) throws -> [Float]
{
    let data = try Data(contentsOf: url)
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

func maxAbsDifference(_ a: [Float], _ b: [Float]) -> Float
{
    guard a.count == b.count else
    {
        print("SHAPE MISMATCH: \(a.count) vs \(b.count) elements")
        return .infinity
    }
    return zip(a, b).map { abs($0 - $1) }.max() ?? 0
}

guard let device = MTLCreateSystemDefaultDevice() else
{
    print("No Metal device available")
    exit(1)
}

let inputPixels = try loadFloatArray(inputURL)
let referenceBackbone = try loadFloatArray(referenceBackboneURL)
let referenceSimccX = try loadFloatArray(referenceSimccXURL)
let referenceSimccY = try loadFloatArray(referenceSimccYURL)

print("Loaded input (\(inputPixels.count) values), reference backbone (\(referenceBackbone.count)), simcc_x (\(referenceSimccX.count)), simcc_y (\(referenceSimccY.count))")

let model = try RTMPoseMPSGraph(weightsBinaryURL: weightsBinaryURL, weightsManifestURL: weightsManifestURL, metalDevice: device)

// Per-stage bisection: dump_backbone_stages.py's stages_stem.bin,
// stages_stage1.bin .. stages_stage4.bin, if present alongside the other
// reference files (same directory as reference_backbone.bin).
let stageNames = ["stem", "stage1", "stage2", "stage3", "stage4"]
let stagesDirectory = referenceBackboneURL.deletingLastPathComponent()
var foundAnyStageFile = false

for (stageIndex, stageName) in stageNames.enumerated()
{
    let stageURL = stagesDirectory.appendingPathComponent("stages_\(stageName).bin")
    guard let referenceStage = try? loadFloatArray(stageURL) else { continue }
    foundAnyStageFile = true

    let ourStage = model.runBackboneStage(pixels: inputPixels, stageIndex: stageIndex)
    let diff = maxAbsDifference(ourStage, referenceStage)
    let status = diff < 1e-2 ? "✅" : "❌"
    print("\(status) \(stageName): max abs diff \(diff) (\(ourStage.count) values)")
    if diff >= 1e-2
    {
        print("   ours[0..3]:", Array(ourStage.prefix(3)))
        print("   ref[0..3]: ", Array(referenceStage.prefix(3)))
        print("   (first mismatch — stopping bisection here, everything after this stage is expected to also mismatch)")
        break
    }
}

if foundAnyStageFile == false
{
    let ourBackbone = model.runBackboneOnly(pixels: inputPixels)
    let backboneDiff = maxAbsDifference(ourBackbone, referenceBackbone)
    print("\nbackbone (768x8x8 feature map) max abs diff vs PyTorch reference: \(backboneDiff)")
    if backboneDiff < 1e-2
    {
        print("✅ backbone MATCHES — bug is in the head")
    }
    else
    {
        print("❌ backbone DOES NOT MATCH — bug is in CSPNeXt, not the head")
        print("ours[0..5]:", Array(ourBackbone.prefix(5)))
        print("ref[0..5]: ", Array(referenceBackbone.prefix(5)))
    }
}

// Warmup (excludes one-time graph compilation from the timing below).
_ = model.run(pixels: inputPixels)

let start = CFAbsoluteTimeGetCurrent()
let iterationCount = 200
var result: (simccX: [Float], simccY: [Float]) = ([], [])
for _ in 0..<iterationCount
{
    result = model.run(pixels: inputPixels)
}
let elapsed = CFAbsoluteTimeGetCurrent() - start
let averageMilliseconds = (elapsed / Double(iterationCount)) * 1000

let simccXDiff = maxAbsDifference(result.simccX, referenceSimccX)
let simccYDiff = maxAbsDifference(result.simccY, referenceSimccY)

print("")
print("simcc_x max abs diff vs PyTorch reference: \(simccXDiff)")
print("simcc_y max abs diff vs PyTorch reference: \(simccYDiff)")
print("average inference time: \(String(format: "%.4f", averageMilliseconds)) ms over \(iterationCount) runs")

if simccXDiff < 1e-2 && simccYDiff < 1e-2
{
    print("\n✅ MATCHES reference within tolerance")
}
else
{
    print("\n❌ DOES NOT MATCH reference — architecture/weight-mapping bug somewhere above")
    print("simcc_x[0..5] ours:", Array(result.simccX.prefix(5)))
    print("simcc_x[0..5] ref: ", Array(referenceSimccX.prefix(5)))
}
