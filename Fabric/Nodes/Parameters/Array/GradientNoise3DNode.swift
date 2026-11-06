//
//  GradientNoise3DNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal
internal import Noise

public class GradientNoise3DNode : Node
{
    public override class var name: String { "Gradient Noise 3D" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Samples smooth fractal (FBM) 3D gradient noise at each position, giving one value per position within -Amplitude...Amplitude; higher Persistence and more Octaves give a quieter field. The field moves by Drift x Time, so wiring a time source animates it. The same Seed always gives the same field. Positions that are not finite, or too far out to sample, give 0." }

    // Connected inlets bypass the slider range: the FBM traps below the minimum, and its top octave's frequency overflows far above the maximum.
    static let minimumOctaves = 1
    static let maximumOctaves = 8

    // swift-noise floors each scaled coordinate with Int(_:), which traps on non-finite values and past Int's range.
    private static let maximumScaledCoordinate = 1e15

    struct Field
    {
        let noise: FBM<GradientNoise3D>
        // Largest |coordinate| the top octave can scale without passing maximumScaledCoordinate; NaN when the frequencies are not finite.
        let maximumCoordinate: Double
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Points to sample the noise at")),
            ("inputTime", ParameterPort(parameter: FloatParameter("Time", 0.0, .inputfield, "Moves the field by Drift x Time"))),
            ("inputDrift", ParameterPort(parameter: Float3Parameter("Drift", simd_float3(0, 0, 0.5), .inputfield, "Direction and speed the field moves through space, in world units per unit of Time"))),
            ("inputFrequency", ParameterPort(parameter: FloatParameter("Frequency", 1.0, 0.0, 20.0, .slider, "Features per world unit in the first octave (higher = smaller lumps)"))),
            ("inputOctaves", ParameterPort(parameter: IntParameter("Octaves", 4, minimumOctaves, maximumOctaves, .slider, "Layers of finer noise added on top of the first"))),
            ("inputPersistence", ParameterPort(parameter: FloatParameter("Persistence", 0.5, 0.0, 1.0, .slider, "Amplitude of each octave relative to the one before (higher = rougher)"))),
            ("inputLacunarity", ParameterPort(parameter: FloatParameter("Lacunarity", 2.0, 1.0, 4.0, .slider, "Frequency of each octave relative to the one before"))),
            ("inputAmplitude", ParameterPort(parameter: FloatParameter("Amplitude", 1.0, 0.0, 10.0, .slider, "Scales the output values"))),
            ("inputSeed", ParameterPort(parameter: IntParameter("Seed", 0, .inputfield, "Picks a different, repeatable noise field"))),
            ("outputValues", NodePort<ContiguousArray<Float>>(name: "Values", kind: .Outlet, description: "Noise value at each position, in input order")),
        ]
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputTime: ParameterPort<Float> { port(named: "inputTime") }
    public var inputDrift: ParameterPort<simd_float3> { port(named: "inputDrift") }
    public var inputFrequency: ParameterPort<Float> { port(named: "inputFrequency") }
    public var inputOctaves: ParameterPort<Int> { port(named: "inputOctaves") }
    public var inputPersistence: ParameterPort<Float> { port(named: "inputPersistence") }
    public var inputLacunarity: ParameterPort<Float> { port(named: "inputLacunarity") }
    public var inputAmplitude: ParameterPort<Float> { port(named: "inputAmplitude") }
    public var inputSeed: ParameterPort<Int> { port(named: "inputSeed") }
    public var outputValues: NodePort<ContiguousArray<Float>> { port(named: "outputValues") }

    private var field: Field?

    static func makeField(frequency: Float, octaves: Int, persistence: Float, lacunarity: Float, seed: Int) -> Field
    {
        let octaveCount = min(maximumOctaves, max(minimumOctaves, octaves))
        let topOctaveFrequency = abs(Double(frequency)) * pow(abs(Double(lacunarity)), Double(octaveCount - 1))
        let noise = FBM(GradientNoise3D(amplitude: 1.0, frequency: Double(frequency), seed: seed),
                        octaves: octaveCount,
                        persistence: Double(persistence),
                        lacunarity: Double(lacunarity))
        return Field(noise: noise, maximumCoordinate: maximumScaledCoordinate / topOctaveFrequency)
    }

    static func sample(_ field: Field,
                       at positions: ContiguousArray<simd_float3>,
                       offset: simd_double3,
                       amplitude: Float) -> ContiguousArray<Float>
    {
        let limit = field.maximumCoordinate
        var values = ContiguousArray<Float>()
        values.reserveCapacity(positions.count)
        for position in positions
        {
            let point = simd_double3(position) + offset
            // Comparisons with NaN are false, so non-finite points and limits fall through to 0.
            guard abs(point.x) < limit, abs(point.y) < limit, abs(point.z) < limit
            else
            {
                values.append(0)
                continue
            }
            values.append(Float(field.noise.evaluate(point.x, point.y, point.z)) * amplitude)
        }
        return values
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let fieldChanged = self.inputFrequency.valueDidChange
            || self.inputOctaves.valueDidChange
            || self.inputPersistence.valueDidChange
            || self.inputLacunarity.valueDidChange
            || self.inputSeed.valueDidChange

        if fieldChanged || self.field == nil
        {
            self.field = Self.makeField(frequency: self.inputFrequency.value ?? 1.0,
                                        octaves: self.inputOctaves.value ?? 4,
                                        persistence: self.inputPersistence.value ?? 0.5,
                                        lacunarity: self.inputLacunarity.value ?? 2.0,
                                        seed: self.inputSeed.value ?? 0)
        }

        guard fieldChanged
            || self.inputPositions.valueDidChange
            || self.inputTime.valueDidChange
            || self.inputDrift.valueDidChange
            || self.inputAmplitude.valueDidChange,
            let field = self.field
        else { return }

        let positions = self.inputPositions.value ?? []
        let offset = simd_double3(self.inputDrift.value ?? simd_float3(0, 0, 0.5)) * Double(self.inputTime.value ?? 0.0)
        self.outputValues.send(Self.sample(field, at: positions, offset: offset, amplitude: self.inputAmplitude.value ?? 1.0))
    }
}
