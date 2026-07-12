import Testing
import Foundation
import simd
@testable import Fabric
import MathExpressionEngine

/// The pure marshalling layer between the MathExpressionEngine value model and
/// Fabric's port model. No Metal device needed — these are value conversions.
@Suite struct EnginePortMarshallingTests
{
    // MARK: - ValueType -> PortType

    @Test func valueTypeMapsToPortType()
    {
        #expect(EnginePortMarshalling.portType(for: .float) == .Float)
        #expect(EnginePortMarshalling.portType(for: .vec2) == .Vector2)
        #expect(EnginePortMarshalling.portType(for: .vec3) == .Vector3)
        #expect(EnginePortMarshalling.portType(for: .vec4) == .Vector4)
        #expect(EnginePortMarshalling.portType(for: .transform) == .Transform)
        #expect(EnginePortMarshalling.portType(for: .quat) == .Quaternion)
        #expect(EnginePortMarshalling.portType(for: .array(.transform)) == .Array(portType: .Transform))
        #expect(EnginePortMarshalling.portType(for: .array(.vec3)) == .Array(portType: .Vector3))
    }

    // MARK: - EngineValue <-> PortValue round-trips

    /// Boxing an engine value and unboxing it back at the same declared type is
    /// the identity — exercised across every scalar/vector/matrix/quat case and
    /// an array, including the transform/quat host-boundary constructors.
    private func assertRoundTrips(_ value: EngineValue, as type: ValueType, sourceLocation: SourceLocation = #_sourceLocation)
    {
        let boxed = EnginePortMarshalling.portValue(for: value)
        let back = EnginePortMarshalling.engineValue(from: boxed, as: type)
        #expect(back == value, "round-trip mismatch for \(type)", sourceLocation: sourceLocation)
    }

    @Test func scalarAndVectorRoundTrips()
    {
        assertRoundTrips(.float(3.5), as: .float)
        assertRoundTrips(.vec2(SIMD2(1, 2)), as: .vec2)
        assertRoundTrips(.vec3(SIMD3(1, 2, 3)), as: .vec3)
        assertRoundTrips(.vec4(SIMD4(1, 2, 3, 4)), as: .vec4)
    }

    @Test func transformRoundTrip()
    {
        let m = Mat4(columns: (SIMD4(1, 2, 3, 4), SIMD4(5, 6, 7, 8),
                               SIMD4(9, 10, 11, 12), SIMD4(13, 14, 15, 16)))
        assertRoundTrips(.transform(m), as: .transform)

        // And the boxed form is really a simd_float4x4 with matching columns.
        if case .Transform(let host) = EnginePortMarshalling.portValue(for: .transform(m))
        {
            #expect(host.columns.0 == SIMD4<Float>(1, 2, 3, 4))
            #expect(host.columns.3 == SIMD4<Float>(13, 14, 15, 16))
        }
        else { Issue.record("expected .Transform box") }
    }

    @Test func quatRoundTrip()
    {
        let q = Quat(components: SIMD4(0.1, 0.2, 0.3, 0.9))
        assertRoundTrips(.quat(q), as: .quat)

        if case .Quaternion(let host) = EnginePortMarshalling.portValue(for: .quat(q))
        {
            #expect(host.vector == SIMD4<Float>(0.1, 0.2, 0.3, 0.9))   // (ix, iy, iz, r) == (x, y, z, w)
        }
        else { Issue.record("expected .Quaternion box") }
    }

    @Test func arrayRoundTrip()
    {
        let arr = EngineValue.array([.vec3(SIMD3(0, 0, 0)), .vec3(SIMD3(1, 2, 3))])
        assertRoundTrips(arr, as: .array(.vec3))
    }

    @Test func numericWideningIntoFloat()
    {
        #expect(EnginePortMarshalling.engineValue(from: .Int(7), as: .float) == .float(7))
        #expect(EnginePortMarshalling.engineValue(from: .Bool(true), as: .float) == .float(1))
        // A type the declared port can't accept yields nil (input "not ready").
        #expect(EnginePortMarshalling.engineValue(from: .Float(1), as: .vec3) == nil)
    }

    // MARK: - Finiteness scrubbing

    @Test func finitenessDetection()
    {
        #expect(EnginePortMarshalling.isFinite(.float(1)))
        #expect(!EnginePortMarshalling.isFinite(.float(.nan)))
        #expect(!EnginePortMarshalling.isFinite(.vec3(SIMD3(1, .infinity, 3))))
        #expect(EnginePortMarshalling.isFinite(.array([.float(1), .float(2)])))
        #expect(!EnginePortMarshalling.isFinite(.array([.float(1), .float(.nan)])))
    }

    // MARK: - Degenerate default parity (engine level, device-free)

    /// The default expression must yield exactly two float inputs (x, y in
    /// order) and one float output, evaluating to sin(x) + y^2 — identical to
    /// the previous scalar node.
    @Test func defaultExpressionInterfaceAndValues() throws
    {
        let result = compile(MathExpressionNode.defaultExpression)
        #expect(result.isValid, "diagnostics: \(result.diagnostics)")

        #expect(result.interface.inputs.map(\.name) == ["x", "y"])
        #expect(result.interface.inputs.allSatisfy { $0.type == .float })
        #expect(result.interface.outputs.count == 1)
        #expect(result.interface.outputs.first?.type == .float)

        for x: Float in [-2, -0.5, 0, 1, 3] {
            for y: Float in [-2, 0, 1.5, 4] {
                let expected = sin(x) + y * y
                let got = try result.evaluate(["x": x, "y": y])
                #expect(abs(got - expected) < 1e-5, "x=\(x) y=\(y): got \(got), expected \(expected)")
            }
        }
    }
}
