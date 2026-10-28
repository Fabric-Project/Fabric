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
///
/// A field that writes while typing writes each keystroke that parses, so
/// the value follows the text; Return and loss of focus then only settle
/// the text, and Escape writes back the value from before the entry.
struct NumericFieldCore: View
{
    let title: String
    let value: Double
    let step: Double
    let fractionDigits: Int
    let unit: String?
    let integral: Bool
    let writesWhileTyping: Bool
    let write: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    @State private var buffer = ""
    @State private var hasEdited = false
    /// The text the field last put in the buffer itself, until the user
    /// types over it; a buffer change that matches it is not typing.
    @State private var textShownByField: String?
    /// The value a typed entry that writes while typing set out from, while
    /// one is in progress: the base of its expressions and what Escape restores.
    @State private var typedEntryStart: Double?
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
                        guard text != textShownByField else { return }
                        textShownByField = nil
                        if writesWhileTyping
                        {
                            writeTypedText(text)
                        }
                    }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused
                        {
                            commitBuffer()
                            show(formatted(value))
                        }
                    }
                    // A value that changes under an edit in progress wins: the
                    // field is showing stale text whatever wrote it, and a label
                    // laid out apart from its field has no other way to settle an
                    // edit before its drag. The field's own write coming back
                    // round leaves the text being typed alone.
                    .onChange(of: value) { _, newValue in
                        if typedEntryStart != nil,
                           let typed = parsed(buffer),
                           formatted(typed) == formatted(newValue)
                        {
                            return
                        }
                        show(formatted(newValue))
                    }
                    .onAppear { show(formatted(value)) }
                    .onDisappear { commitBuffer() }
                    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                        stepValue(by: press.key == .upArrow ? 1 : -1, modifiers: press.modifiers)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        revertBuffer()
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
        let start = (hasEdited ? parsed(buffer) : nil) ?? value
        commitBuffer()
        return start
    }

    private func stepValue(by direction: Double, modifiers: EventModifiers)
    {
        let active = NumericFieldStepping.keyStep(base: step, modifiers: modifiers, integral: integral)
        let current = (hasEdited ? parsed(buffer) : nil) ?? value
        var next = current + direction * active
        if modifiers.contains(.command)
        {
            next = NumericFieldStepping.snapped(next, to: active)
        }
        next = NumericFieldStepping.cleaned(next, step: active, integral: integral)
        // A typed entry in progress is already written; the step ends it.
        typedEntryStart = nil
        write(next)
        // The buffer does not follow the value while focused; show the step
        // without waiting for the value to come back round.
        show(formatted(next))
        hasEdited = false
    }

    /// Writes typed text that parses, opening the typed entry at its first
    /// write. Text that does not parse, such as an expression half typed,
    /// leaves the value at the last text that did.
    private func writeTypedText(_ text: String)
    {
        guard let typed = parsed(text) else { return }
        if typedEntryStart == nil
        {
            typedEntryStart = value
        }
        write(typed)
    }

    private func commitBuffer()
    {
        defer { typedEntryStart = nil }
        guard hasEdited else { return }
        hasEdited = false
        if let typed = parsed(buffer)
        {
            write(typed)
            show(formatted(typed))
        }
        else
        {
            show(formatted(value))
        }
    }

    /// Escape restores the value from before the typed entry. A field that
    /// writes while typing has already written the entry's keystrokes, so it
    /// writes that value back rather than only discarding the text.
    private func revertBuffer()
    {
        let original = typedEntryStart ?? value
        if typedEntryStart != nil
        {
            write(original)
        }
        typedEntryStart = nil
        hasEdited = false
        show(formatted(original))
    }

    /// Typed text as a value. An expression's free names are the value from
    /// before the typed entry, not one the entry has already written.
    private func parsed(_ text: String) -> Double?
    {
        NumericFieldStepping.parse(text, current: typedEntryStart ?? value, integral: integral, unit: unit)
    }

    private func show(_ text: String)
    {
        textShownByField = text
        buffer = text
    }

    private func formatted(_ value: Double) -> String
    {
        value.formatted(.number.precision(.fractionLength(0...fractionDigits)).grouping(.never))
    }

}
