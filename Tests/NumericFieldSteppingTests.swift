import Testing
import Foundation
import simd
@testable import Fabric
import Satin

/// The arithmetic a numeric field's label drag and arrow keys run on.
@Suite("Numeric field stepping")
struct NumericFieldSteppingTests
{
    @Test("Shift coarsens the step tenfold, Option refines it, together they cancel")
    func modifiersScaleTheStep()
    {
        #expect(NumericFieldStepping.activeStep(base: 0.1, modifiers: []) == 0.1)
        #expect(NumericFieldStepping.activeStep(base: 0.1, modifiers: .shift) == 1.0)
        #expect(NumericFieldStepping.activeStep(base: 0.1, modifiers: .option) == 0.01)
        #expect(NumericFieldStepping.activeStep(base: 0.1, modifiers: [.shift, .option]) == 0.1)
        #expect(NumericFieldStepping.activeStep(base: 0.1, modifiers: .command) == 0.1)
    }

    @Test("Snapping lands on a multiple of the step in force")
    func snappingUsesTheActiveStep()
    {
        #expect(NumericFieldStepping.snapped(37, to: 10) == 40)
        #expect(NumericFieldStepping.snapped(0.37, to: 0.1) == 0.4)
        #expect(NumericFieldStepping.snapped(-0.37, to: 0.1) == -0.4)
        #expect(NumericFieldStepping.snapped(12.5, to: 0) == 12.5)
    }

    @Test("Three steps of a tenth read three tenths")
    func accumulationNoiseIsDropped()
    {
        var value = 0.0
        for _ in 0..<3 { value += 0.1 }
        #expect(value != 0.3)
        #expect(NumericFieldStepping.rounded(value, toPrecisionOf: 0.1) == 0.3)
        #expect(NumericFieldStepping.rounded(0.25 + 0.25, toPrecisionOf: 0.25) == 0.5)
        #expect(NumericFieldStepping.rounded(30.000000001, toPrecisionOf: 10) == 30)
    }

    @Test("A range steps by a hundredth of its span, rounded down to a power of ten")
    func stepFollowsTheRange()
    {
        #expect(NumericFieldStepping.step(forRange: 0, max: 1, integral: false, fractionDigits: 3) == 0.01)
        #expect(NumericFieldStepping.step(forRange: 0, max: 1000, integral: false, fractionDigits: 3) == 10)
        #expect(NumericFieldStepping.step(forRange: -180, max: 180, integral: false, fractionDigits: 3) == 1)
        #expect(NumericFieldStepping.step(forRange: 0, max: 16384, integral: true, fractionDigits: 0) == 100)
    }

    @Test("Without a range the last displayed digit steps; an integer never below one")
    func stepWithoutARange()
    {
        #expect(NumericFieldStepping.step(forRange: 0, max: 0, integral: false, fractionDigits: 3) == 0.001)
        #expect(NumericFieldStepping.step(forRange: 5, max: 1, integral: false, fractionDigits: 2) == 0.01)
        #expect(NumericFieldStepping.step(forRange: 0, max: 1, integral: true, fractionDigits: 0) == 1)
        #expect(NumericFieldStepping.step(forRange: 0, max: 0, integral: true, fractionDigits: 0) == 1)
    }
}

/// The step a parameter's field is given, from the parameter's range.
@Suite("Parameter field step")
struct ParameterFieldStepTests
{
    @Test("A float made without a range carries Satin's 0…1 and steps by hundredths")
    func unrangedFloatStepsByHundredths()
    {
        let param = FloatParameter("Seek Time", -1.0, .inputfield, "")
        #expect(ParameterFieldStep.step(for: param, fractionDigits: 3) == 0.01)
    }

    @Test("A ranged integer steps by its range, never below one")
    func rangedIntegerStepsByItsRange()
    {
        #expect(ParameterFieldStep.step(for: IntParameter("Crop X", 0, 0, 16384, .inputfield, "")) == 100)
        #expect(ParameterFieldStep.step(for: IntParameter("Count", 3, .inputfield, "")) == 1)
    }

    @Test("A vector steps each component by that component's range")
    func vectorStepsPerComponent()
    {
        let param = Float2Parameter("Size", simd_float2(1, 1), simd_float2(0, 0), simd_float2(1, 4096), .inputfield, "")
        #expect(ParameterFieldStep.steps(for: param, fractionDigits: 3) == [0.01, 10])

        let ints = Int2Parameter("Grid", simd_int2(1, 1), .inputfield, "")
        #expect(ParameterFieldStep.steps(for: ints) == [1, 1])
    }
}
