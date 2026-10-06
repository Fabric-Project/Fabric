//
//  IntegerField.swift
//  Fabric
//

import SwiftUI

/// An integer field whose label drags the value. The stepping and commit
/// rules are `NumericField`'s; the step is one unless given.
public struct IntegerField<Value: FixedWidthInteger>: View
{
    private let title: String
    private let value: Binding<Value>
    private let step: Value
    private let unit: String?
    private let onEditingChanged: (Bool) -> Void

    public init(_ title: String,
                value: Binding<Value>,
                step: Value = 1,
                unit: String? = nil,
                onEditingChanged: @escaping (Bool) -> Void = { _ in })
    {
        self.title = title
        self.value = value
        self.step = step
        self.unit = unit
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View
    {
        NumericFieldCore(title: title,
                         value: Double(value.wrappedValue),
                         step: Double(step),
                         fractionDigits: 0,
                         unit: unit,
                         integral: true,
                         write: { value.wrappedValue = Value(clamping: Int($0)) },
                         onEditingChanged: onEditingChanged)
    }
}
