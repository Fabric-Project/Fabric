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

/// Typed text as a value: a number, or an expression over the current value.
@Suite("Numeric field entry")
struct NumericFieldEntryTests
{
    private let en = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    private func parse(_ text: String, current: Double = 72, integral: Bool = false,
                       locale: Locale? = nil) -> Double?
    {
        NumericFieldStepping.parse(text, current: current, integral: integral, locale: locale ?? en)
    }

    @Test("A number is a number, in the locale or with a plain decimal point")
    func numbers()
    {
        #expect(parse("1.5") == 1.5)
        #expect(parse("1,5", locale: de) == 1.5)
        #expect(parse("1.5", locale: de) == 1.5)
        #expect(parse("-10") == -10)
        #expect(parse(" 42 ") == 42)
        #expect(parse("") == nil)
        #expect(parse("abc(") == nil)
    }

    @Test("Typing after the shown value makes an expression of it")
    func expressionOverTheShownValue()
    {
        #expect(parse("72 * 2") == 144)
        #expect(parse("72 / 4 + 1") == 19)
        #expect(parse("(72 + 8) * 2") == 160)
    }

    @Test("Every free name is the current value")
    func freeNamesAreTheCurrentValue()
    {
        #expect(parse("x * 2") == 144)
        #expect(parse("value / 2 + 1") == 37)
        #expect(parse("x * y", current: 3) == 9)
        #expect(parse("abs(v)", current: -5) == 5)
    }

    @Test("The engine's own names keep their meaning")
    func engineNamesAreNotTheCurrentValue()
    {
        let e = try? #require(parse("e * 2"))
        #expect(e.map { abs($0 - 2 * 2.718281828) < 1e-5 } == true)
        #expect(parse("sqr(x)") == nil)
    }

    @Test("An expression reads the locale's decimal separator")
    func expressionInACommaLocale()
    {
        #expect(parse("1,5 * x", current: 2, locale: de) == 3)
    }

    @Test("An integer field rounds the result")
    func integerRounding()
    {
        #expect(parse("x / 4", current: 10, integral: true) == 3)
        #expect(parse("2.5", integral: true) == 3)
        #expect(parse("1e20", integral: true) == nil)
    }
}
