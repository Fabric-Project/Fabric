//
//  InputFieldView.swift
//  v
//
//  Created by Anton Marini on 4/9/25.
//

import SwiftUI
import Satin


/// The inspector's label column: bold, right-aligned, one line, a fixed
/// width so every row's field starts at the same place.
private struct InputFieldLabelModifier: ViewModifier
{
    func body(content: Content) -> some View
    {
        content
            .font(.system(size: 10))
            .fontWeight(.bold)
            .lineLimit(1)
            .frame(width: 90, alignment: .trailing)
            .truncationMode(.tail)
    }
}

struct InputFieldLabelView : View {
    
    let label:String
    
    var body: some View {
        Text(label)
            .modifier(InputFieldLabelModifier())
    }
}

/// A numeric field laid out as the inspector's string field is: the label
/// column, then a field of the parameter width.
private struct InputFieldRowStyle: LabeledContentStyle
{
    func makeBody(configuration: Configuration) -> some View
    {
        HStack(spacing: ParameterConfig.horizontalStackSpacing)
        {
            configuration.label
                .modifier(InputFieldLabelModifier())
            configuration.content
                .font(controlFont)
                .frame(width: ParameterConfig.paramWidth, alignment: .leading)
        }
    }
}

struct InputFieldComponentView : View
{
    let binding:Binding<String>
    let label:String
    
    var body: some View {
        TextField(label, text: binding)
            .lineLimit(1)
            .frame(width: ParameterConfig.paramWidth, alignment: .leading)
            .font(.system(size: 10))
            .textFieldStyle(.roundedBorder)
    }
}


struct InputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<String>

    init(param:StringParameter)
    {
        // The whole value, however much of it the field can show. This read is
        // what an edit is compared and written back against, so shortening it
        // here commits the shortening as soon as a rebuilt field is typed into.
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher)
    }
    
    var body: some View
    {
        HStack(spacing: ParameterConfig.horizontalStackSpacing)
        {
            InputFieldLabelView(label: self.vm.label)
            
            InputFieldComponentView(binding: self.$vm.uiValue, label: self.vm.label )
        }
    }
}

// MARK: - Numeric Input Fields

/// How many decimal places a float field shows; the drag step comes from the
/// parameter's range, not from this.
private let floatFractionDigits = 5

private let controlFont = Font.system(size: CGFloat(ParameterConfig.controlFont))

/// A vector parameter's fields: the parameter's label over one labelled field
/// per component.
private struct ComponentFieldsView<Fields: View>: View
{
    let label: String
    @ViewBuilder let fields: Fields

    var body: some View
    {
        VStack(alignment: .leading, spacing: 7)
        {
            // The heading ends where the fields begin.
            Text(label)
                .modifier(InputFieldLabelModifier())
                .frame(width: 90 + ParameterConfig.horizontalStackSpacing, alignment: .trailing)
            fields
        }
        .font(controlFont)
        .labeledContentStyle(InputFieldRowStyle())
    }
}

struct FloatInputFieldView: View
{
    @Bindable var vm: ParameterObservableModel<Float>
    let step: Float

    init(param:GenericParameter<Float>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.step = ParameterFieldStep.step(for: param, fractionDigits: floatFractionDigits)
    }
    
    var body: some View
    {
        NumericField(vm.label, value: $vm.uiValue, step: step, fractionDigits: floatFractionDigits)
            .font(controlFont)
            .labeledContentStyle(InputFieldRowStyle())
    }
}

struct Float2InputFieldView: View
{
    @Bindable var vm: ParameterObservableModel<simd_float2>
    let steps: [Float]

    init(param:GenericParameter<simd_float2>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.steps = ParameterFieldStep.steps(for: param, fractionDigits: floatFractionDigits)
    }
    
    var body: some View
    {
        ComponentFieldsView(label: vm.label)
        {
            NumericField("X", value: $vm.uiValue.x, step: steps[0], fractionDigits: floatFractionDigits)
            NumericField("Y", value: $vm.uiValue.y, step: steps[1], fractionDigits: floatFractionDigits)
        }
    }
}

struct Float3InputFieldView: View
{
    @Bindable var vm: ParameterObservableModel<simd_float3>
    let steps: [Float]

    init(param:GenericParameter<simd_float3>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.steps = ParameterFieldStep.steps(for: param, fractionDigits: floatFractionDigits)
    }
    
    var body: some View
    {
        ComponentFieldsView(label: vm.label)
        {
            NumericField("X", value: $vm.uiValue.x, step: steps[0], fractionDigits: floatFractionDigits)
            NumericField("Y", value: $vm.uiValue.y, step: steps[1], fractionDigits: floatFractionDigits)
            NumericField("Z", value: $vm.uiValue.z, step: steps[2], fractionDigits: floatFractionDigits)
        }
    }
}

struct Float4InputFieldView: View
{
    @Bindable var vm: ParameterObservableModel<simd_float4>
    let steps: [Float]

    init(param:GenericParameter<simd_float4>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.steps = ParameterFieldStep.steps(for: param, fractionDigits: floatFractionDigits)
    }
    
    var body: some View
    {
        ComponentFieldsView(label: vm.label)
        {
            NumericField("X", value: $vm.uiValue.x, step: steps[0], fractionDigits: floatFractionDigits)
            NumericField("Y", value: $vm.uiValue.y, step: steps[1], fractionDigits: floatFractionDigits)
            NumericField("Z", value: $vm.uiValue.z, step: steps[2], fractionDigits: floatFractionDigits)
            NumericField("W", value: $vm.uiValue.w, step: steps[3], fractionDigits: floatFractionDigits)
        }
    }
}

struct IntInputFieldView: View
{
    @Bindable var vm: ParameterObservableModel<Int>
    let step: Int

    init(param:GenericParameter<Int>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.step = ParameterFieldStep.step(for: param)
    }
    
    var body: some View
    {
        IntegerField(vm.label, value: $vm.uiValue, step: step)
            .font(controlFont)
            .labeledContentStyle(InputFieldRowStyle())
    }
}

struct Int2InputFieldView: View
{
    @Bindable var vm: ParameterObservableModel<simd_int2>
    let steps: [Int32]

    init(param:GenericParameter<simd_int2>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.steps = ParameterFieldStep.steps(for: param)
    }
    
    var body: some View
    {
        ComponentFieldsView(label: vm.label)
        {
            IntegerField("X", value: $vm.uiValue.x, step: steps[0])
            IntegerField("Y", value: $vm.uiValue.y, step: steps[1])
        }
    }
}

struct Int3InputFieldView: View
{
    @Bindable var vm: ParameterObservableModel<simd_int3>
    let steps: [Int32]

    init(param:GenericParameter<simd_int3>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.steps = ParameterFieldStep.steps(for: param)
    }
    
    var body: some View
    {
        ComponentFieldsView(label: vm.label)
        {
            IntegerField("X", value: $vm.uiValue.x, step: steps[0])
            IntegerField("Y", value: $vm.uiValue.y, step: steps[1])
            IntegerField("Z", value: $vm.uiValue.z, step: steps[2])
        }
    }
}

struct Int4InputFieldView: View
{
    @Bindable var vm: ParameterObservableModel<simd_int4>
    let steps: [Int32]

    init(param:GenericParameter<simd_int4>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.steps = ParameterFieldStep.steps(for: param)
    }
    
    var body: some View
    {
        ComponentFieldsView(label: vm.label)
        {
            IntegerField("X", value: $vm.uiValue.x, step: steps[0])
            IntegerField("Y", value: $vm.uiValue.y, step: steps[1])
            IntegerField("Z", value: $vm.uiValue.z, step: steps[2])
            IntegerField("W", value: $vm.uiValue.w, step: steps[3])
        }
    }
}
