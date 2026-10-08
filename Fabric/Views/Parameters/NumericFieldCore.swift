//
//  NumericFieldCore.swift
//  Fabric
//

import SwiftUI

/// The field behind `NumericField` and `IntegerField`, working in Double.
///
/// The label is the drag handle: a horizontal drag steps the value, with the
/// pointer and modifier rules of `NumericFieldStepping`. The field itself keeps
/// native text behaviour — click to edit, Return or losing focus to commit,
/// Escape to revert — and takes Up and Down arrows with the same modifiers as
/// the drag.
///
/// Typed text lives in a buffer, synced from the value when the value changes,
/// so a parent re-rendering mid-edit cannot reformat the text under the user.
/// An edit is detected by the buffer diverging from the formatted value rather
/// than by focus, because focus is not reported inside a macOS popover;
/// whatever is pending commits when the field disappears with it.
struct NumericFieldCore: View
{
    let title: String
    let value: Double
    let step: Double
    let fractionDigits: Int
    let unit: String?
    let integral: Bool
    let write: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    @State private var buffer = ""
    @State private var hasEdited = false
    @FocusState private var focused: Bool

    var body: some View
    {
        LabeledContent
        {
            // The title is the field's accessibility label and placeholder; a
            // Form would otherwise show it beside the field as a second label.
            HStack(spacing: 4)
            {
                TextField(title, text: $buffer)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .monospacedDigit()
                    .focused($focused)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.fill.quaternary, in: .rect(cornerRadius: 5))
                    // The plain style draws no focus ring, so the field draws
                    // its own, round its surface.
                    .overlay {
                        if focused
                        {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.accentColor, lineWidth: 2)
                                .padding(-2)
                        }
                    }
                    // Return commits and leaves the field; Escape reverts any edit
                    // pending and leaves it. Both are taken here, so a popover
                    // closes on the Escape after.
                    .onSubmit {
                        commitBuffer()
                        focused = false
                    }
                    .onChange(of: buffer) { _, text in
                        hasEdited = text != formatted(value)
                    }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused
                        {
                            commitBuffer()
                            buffer = formatted(value)
                        }
                    }
                    // A value that changes under an edit in progress wins: the
                    // field is showing stale text whatever wrote it, and a label
                    // laid out apart from its field has no other way to settle an
                    // edit before its drag.
                    .onChange(of: value) { _, newValue in
                        buffer = formatted(newValue)
                    }
                    .onAppear { buffer = formatted(value) }
                    .onDisappear { commitBuffer() }
                    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                        stepValue(by: press.key == .upArrow ? 1 : -1, modifiers: press.modifiers)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        buffer = formatted(value)
                        focused = false
                        return .handled
                    }
                    .accessibilityValue(formatted(value))
                    .accessibilityAdjustableAction { direction in
                        stepValue(by: direction == .increment ? 1 : -1, modifiers: [])
                    }
                if let unit
                {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
        label:
        {
            Text(title)
                .modifier(NumericDragHandle(step: step,
                                            integral: integral,
                                            start: beginDrag,
                                            write: write,
                                            onEditingChanged: onEditingChanged))
        }
    }

    /// A typed edit still pending commits first, so the drag starts from
    /// what the field shows.
    private func beginDrag() -> Double
    {
        focused = false
        let start = (hasEdited ? NumericFieldStepping.parse(buffer, current: value, integral: integral) : nil) ?? value
        commitBuffer()
        return start
    }

    private func stepValue(by direction: Double, modifiers: EventModifiers)
    {
        let active = NumericFieldStepping.activeStep(base: step, modifiers: modifiers)
        let current = (hasEdited ? NumericFieldStepping.parse(buffer, current: value, integral: integral) : nil) ?? value
        var next = current + direction * active
        if modifiers.contains(.command)
        {
            next = NumericFieldStepping.snapped(next, to: active)
        }
        next = NumericFieldStepping.cleaned(next, step: active, integral: integral)
        write(next)
        // The buffer does not follow the value while focused; show the step
        // without waiting for the value to come back round.
        buffer = formatted(next)
        hasEdited = false
    }

    private func commitBuffer()
    {
        guard hasEdited else { return }
        hasEdited = false
        if let parsed = NumericFieldStepping.parse(buffer, current: value, integral: integral)
        {
            write(parsed)
            buffer = formatted(parsed)
        }
        else
        {
            buffer = formatted(value)
        }
    }

    private func formatted(_ value: Double) -> String
    {
        value.formatted(.number.precision(.fractionLength(0...fractionDigits)).grouping(.never))
    }

}
