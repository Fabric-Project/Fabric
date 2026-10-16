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

    @State private var drag: NumericFieldStepping.Drag?

    func body(content: Content) -> some View
    {
        content
            .contentShape(.rect)
            .modifier(DragPointer())
            .gesture(dragGesture)
    }

    private var dragGesture: some Gesture
    {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                if drag == nil
                {
                    drag = NumericFieldStepping.Drag(start: start(), step: step, integral: integral)
                    onEditingChanged(true)
                }
                if let next = drag?.move(to: gesture.translation.width.rounded(),
                                         modifiers: NumericFieldStepping.currentModifiers())
                {
                    write(next)
                }
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
                                   write: { value.wrappedValue = NumericFieldStepping.integer($0) },
                                   onEditingChanged: onEditingChanged))
    }
}
