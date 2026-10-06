//
//  NumericFieldStepping.swift
//  Fabric
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The arithmetic behind a numeric field's drag and arrow stepping, apart from
/// the view so it can be tested.
///
/// A field moves by a constant step per point of drag or per arrow press. Shift
/// makes the step ten times larger, Option ten times smaller, and Command snaps
/// the result to a multiple of the step in force. A constant step keeps a drag
/// reversible — out and back lands where it started — and makes the snap
/// predictable, which a step that follows the value's magnitude would not.
enum NumericFieldStepping
{
    static func activeStep(base: Double, modifiers: EventModifiers) -> Double
    {
        var step = base
        if modifiers.contains(.shift) { step *= 10 }
        if modifiers.contains(.option) { step /= 10 }
        return step
    }

    static func snapped(_ value: Double, to step: Double) -> Double
    {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// Drops the binary noise of repeated addition, so three steps of a tenth
    /// read 0.3 and not 0.30000000000000004. Keeps one decimal beyond the
    /// step's own, so a step that is not a power of ten survives whole.
    static func rounded(_ value: Double, toPrecisionOf step: Double) -> Double
    {
        guard step > 0, step.isFinite else { return value }
        let decimals = Swift.max(0, Int((-log10(step)).rounded(.up))) + 1
        let scale = pow(10, Double(decimals))
        return (value * scale).rounded() / scale
    }

    /// A step for a value with a known range: a hundredth of the span, rounded
    /// down to a power of ten, so 0…1 steps by hundredths and 0…1000 by tens.
    /// Without a span the step is the last displayed digit. An integer never
    /// steps below one.
    static func step(forRange min: Double, max: Double, integral: Bool, fractionDigits: Int) -> Double
    {
        let span = max - min
        var step: Double
        if span > 0, span.isFinite
        {
            step = pow(10, floor(log10(span / 100)))
        }
        else
        {
            step = pow(10, -Double(fractionDigits))
        }
        if integral { step = Swift.max(1, step) }
        return step
    }

    /// A value as a drag or arrow step leaves it: whole for an integer,
    /// otherwise free of accumulation noise.
    static func cleaned(_ value: Double, step: Double, integral: Bool) -> Double
    {
        integral ? value.rounded() : rounded(value, toPrecisionOf: step)
    }

    /// The modifier keys down now. Read at each pointer event rather than
    /// captured at a drag's start, so holding Shift partway through a drag
    /// changes the step from there.
    static func currentModifiers() -> EventModifiers
    {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        var modifiers: EventModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
        #else
        return []
        #endif
    }
}
