//
//  NumericDragHandle.swift
//  Fabric
//

import SwiftUI

/// The label drag behind `NumericField`, for a caller that lays out its own
/// label beside a field whose label is hidden. The stepping, modifier and
/// commit rules are the field's; `start` gives the value the drag sets out
/// from, after the caller has settled any edit in progress.
struct NumericDragHandle: ViewModifier
{
    let step: Double
    let integral: Bool
    let start: () -> Double
    let write: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    @State private var drag: Drag?

    /// The value a drag has reached, before snapping, and the drag distance
    /// already applied to it. Steps apply to the distance moved since the last
    /// update, so a modifier pressed mid-drag changes the step from there.
    private struct Drag
    {
        var accumulator: Double
        var points: Double
    }

    func body(content: Content) -> some View
    {
        content
            .contentShape(.rect)
            .modifier(DragPointer())
            .gesture(dragGesture)
    }

    private var dragGesture: some Gesture
    {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                let points = gesture.translation.width.rounded()
                let modifiers = NumericFieldStepping.currentModifiers()
                if drag == nil
                {
                    drag = Drag(accumulator: start(), points: points)
                    onEditingChanged(true)
                }
                guard var state = drag else { return }
                let active = NumericFieldStepping.activeStep(base: step, modifiers: modifiers)
                state.accumulator += (points - state.points) * active
                state.points = points
                drag = state

                var next = state.accumulator
                if modifiers.contains(.command)
                {
                    next = NumericFieldStepping.snapped(next, to: active)
                }
                write(NumericFieldStepping.cleaned(next, step: active, integral: integral))
            }
            .onEnded { _ in
                drag = nil
                onEditingChanged(false)
            }
    }
}

/// The left-right resize pointer over the label, where a pointer exists.
private struct DragPointer: ViewModifier
{
    func body(content: Content) -> some View
    {
        #if os(macOS)
        content.pointerStyle(.columnResize)
        #else
        content
        #endif
    }
}

public extension View
{
    /// Makes this view the drag handle for a value, as a `NumericField`'s
    /// label is: a horizontal drag steps the value by `step` per point, Shift
    /// tenfold, Option a tenth, Command snapping to a multiple of the step in
    /// force. For a label laid out apart from its field.
    func numericDragHandle<Value: BinaryFloatingPoint>(value: Binding<Value>,
                                                       step: Value,
                                                       onEditingChanged: @escaping (Bool) -> Void = { _ in }) -> some View
    {
        modifier(NumericDragHandle(step: Double(step),
                                   integral: false,
                                   start: { Double(value.wrappedValue) },
                                   write: { value.wrappedValue = Value($0) },
                                   onEditingChanged: onEditingChanged))
    }

    /// `numericDragHandle` for an integer value; the step is one unless given.
    func integerDragHandle<Value: FixedWidthInteger>(value: Binding<Value>,
                                                     step: Value = 1,
                                                     onEditingChanged: @escaping (Bool) -> Void = { _ in }) -> some View
    {
        modifier(NumericDragHandle(step: Double(step),
                                   integral: true,
                                   start: { Double(value.wrappedValue) },
                                   write: { value.wrappedValue = Value(clamping: Int($0)) },
                                   onEditingChanged: onEditingChanged))
    }
}
