import Testing
import simd
@testable import Fabric

@Suite("Gradient Noise 3D")
struct GradientNoise3DNodeTests
{
    private let positions: ContiguousArray<simd_float3> = ContiguousArray((0..<500).map { index in
        let angle = Float(index) * 2.399963
        let height = 1 - 2 * (Float(index) + 0.5) / 500
        let ring = (1 - height * height).squareRoot()
        return simd_float3(ring * cos(angle), height, ring * sin(angle)) * 1.7
    })

    private func values(seed: Int = 0, octaves: Int = 4, offset: simd_double3 = .zero, amplitude: Float = 1,
                        at points: ContiguousArray<simd_float3>? = nil) -> ContiguousArray<Float>
    {
        let field = GradientNoise3DNode.makeField(frequency: 1.3, octaves: octaves, persistence: 0.5, lacunarity: 2, seed: seed)
        return GradientNoise3DNode.sample(field, at: points ?? positions, offset: offset, amplitude: amplitude)
    }

    @Test("One value per position, the same for the same seed and different for another")
    func seedIsRepeatable()
    {
        let first = values(seed: 7)
        #expect(first.count == positions.count)
        #expect(first == values(seed: 7))
        #expect(first != values(seed: 8))
    }

    @Test("Values vary, stay within Amplitude, and scale with it")
    func rangeAndAmplitude()
    {
        let unit = values()
        let spread = (unit.max() ?? 0) - (unit.min() ?? 0)
        #expect(spread > 0.3, "Field is not flat")
        #expect(unit.allSatisfy { abs($0) <= 1.05 })
        let doubled = values(amplitude: 2)
        #expect(zip(unit, doubled).allSatisfy { abs($1 - 2 * $0) < 1e-5 })
    }

    @Test("Nearby points give nearby values")
    func fieldIsSmooth()
    {
        let nudged = ContiguousArray(positions.map { $0 + simd_float3(1e-3, -1e-3, 1e-3) })
        let base = values()
        let moved = values(at: nudged)
        #expect(zip(base, moved).allSatisfy { abs($0 - $1) < 0.02 })
    }

    @Test("Drift x Time samples the field at the shifted positions")
    func offsetShiftsField()
    {
        let offset = simd_float3(0.4, -1.1, 2.5)
        let shifted = ContiguousArray(positions.map { $0 + offset })
        // The node adds in Double, the shifted positions in Float.
        #expect(zip(values(offset: simd_double3(offset)), values(at: shifted)).allSatisfy { abs($0 - $1) < 1e-4 })
    }

    @Test("Non-finite and out-of-range positions give 0 and leave the others as they were")
    func unsamplablePositionsGiveZero()
    {
        let points: ContiguousArray<simd_float3> = [
            simd_float3(0.3, 0.2, 0.1),
            simd_float3(.nan, 0, 0),
            simd_float3(0, .infinity, 0),
            simd_float3(0, 0, 1e18),
            simd_float3(-0.4, 0.9, 0.5),
        ]
        let sampled = values(at: points)
        #expect(sampled[1] == 0 && sampled[2] == 0 && sampled[3] == 0)
        #expect(sampled[0] == values(at: [points[0]])[0])
        #expect(sampled[4] == values(at: [points[4]])[0])
        #expect(sampled[0] != 0 && sampled[4] != 0)
    }

    @Test("A non-finite Drift x Time gives 0 everywhere")
    func nonFiniteOffsetGivesZero()
    {
        #expect(values(offset: simd_double3(0, 0, .infinity)).allSatisfy { $0 == 0 })
        #expect(values(offset: simd_double3(.nan, 0, 0)).allSatisfy { $0 == 0 })
    }

    @Test("Non-finite Frequency or Lacunarity gives 0 everywhere")
    func nonFiniteFrequencyGivesZero()
    {
        for (frequency, lacunarity) in [(Float.nan, Float(2)), (.infinity, 2), (1, .infinity), (1, .nan)]
        {
            let field = GradientNoise3DNode.makeField(frequency: frequency, octaves: 4, persistence: 0.5, lacunarity: lacunarity, seed: 0)
            #expect(GradientNoise3DNode.sample(field, at: positions, offset: .zero, amplitude: 1).allSatisfy { $0 == 0 })
        }
    }

    @Test("Octaves outside the slider range clamp to it")
    func octavesClamp()
    {
        #expect(values(octaves: 70) == values(octaves: GradientNoise3DNode.maximumOctaves))
        #expect(values(octaves: -3) == values(octaves: GradientNoise3DNode.minimumOctaves))
    }

    @Test("Executing the node with a NaN position sends 0 for it")
    func nodeHandlesNaN() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = GradientNoise3DNode(context: harness.context)
        node.inputPositions.value = [simd_float3(0.3, 0.2, 0.1), simd_float3(0, .nan, 0)]
        try harness.execute(node)
        let sent = try #require(node.outputValues.value)
        #expect(sent.count == 2 && sent[0] != 0 && sent[1] == 0)
    }

    @Test("Executing the node sends one value per position, then follows Time")
    func nodeSendsValues() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = GradientNoise3DNode(context: harness.context)
        node.inputPositions.value = positions
        try harness.execute(node)
        let atRest = try #require(node.outputValues.value)
        let defaultField = GradientNoise3DNode.makeField(frequency: 1, octaves: 4, persistence: 0.5, lacunarity: 2, seed: 0)
        #expect(atRest == GradientNoise3DNode.sample(defaultField, at: positions, offset: .zero, amplitude: 1))

        node.markClean()
        node.outputValues.value = nil
        try harness.execute(node)
        #expect(node.outputValues.value == nil, "No input changed, so nothing is sent")

        node.inputTime.value = 2
        try harness.execute(node)
        let moved = try #require(node.outputValues.value)
        #expect(moved != atRest)
    }
}
