//
//  NumericField.swift
//  Fabric
//

import SwiftUI

/// A floating-point field whose label drags the value.
///
/// `step` is the change per point of drag or per arrow press, in the value's
/// own unit: a pixel field steps by one, a normalised one by a hundredth. Shift
/// makes the step ten times larger, Option ten times smaller, and Command
/// snaps to a multiple of the step in force. `fractionDigits` is the most the
/// field shows; trailing zeros are dropped. `unit` is shown after the field.
///
/// The value is written live through a drag, bracketed by `onEditingChanged`
/// as on `Slider`, so a caller can register one undo per drag. Typed entry
/// writes once, on Return or loss of focus.
public struct NumericField<Value: BinaryFloatingPoint>: View
{
    private let title: String
    private let value: Binding<Value>
    private let step: Value
    private let fractionDigits: Int
    private let unit: String?
    private let onEditingChanged: (Bool) -> Void

    public init(_ title: String,
                value: Binding<Value>,
                step: Value,
                fractionDigits: Int = 2,
                unit: String? = nil,
                onEditingChanged: @escaping (Bool) -> Void = { _ in })
    {
        self.title = title
        self.value = value
        self.step = step
        self.fractionDigits = fractionDigits
        self.unit = unit
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View
    {
        NumericFieldCore(title: title,
                         value: Double(value.wrappedValue),
                         step: Double(step),
                         fractionDigits: fractionDigits,
                         unit: unit,
                         integral: false,
                         write: { value.wrappedValue = Value($0) },
                         onEditingChanged: onEditingChanged)
    }
}
