//
//  InputFieldView.swift
//  v
//
//  Created by Anton Marini on 4/9/25.
//

import SwiftUI
import Satin


struct InputFieldLabelView : View {
    
    let label:String
    
    var body: some View {
        Text(label)
            .font(.system(size: 10))
            .fontWeight(.bold)
            .lineLimit(1)
            .frame(width: 90, alignment: .trailing)
            .truncationMode(.tail)
    }
}

struct InputFieldComponentView : View
{
    let binding:Binding<String>
    let label:String
    
    var body: some View {
        TextField(label, text: binding)
            .font(.system(size: 10))
            .textFieldStyle(.roundedBorder)
            .lineLimit(1)
            .frame(width: ParameterConfig.paramWidth, alignment: .leading)

    }
}

struct FormattedInputFieldComponentView<T> : View
{
    let binding:Binding<T>
    let label:String
    let formatter:Formatter
    
    var body: some View {
        TextField(label, value: binding, formatter:formatter)
            .font(.system(size: 10))
            .textFieldStyle(.roundedBorder)
            .lineLimit(1)
            .frame(width: ParameterConfig.paramWidth, alignment: .leading)

    }
}


struct InputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<String>

    init(param:StringParameter)
    {
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

// MARK: - Float Input Fields

struct FloatInputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }
    
    @Bindable var vm: ParameterObservableModel<Float>
    let decimalFormatter:NumberFormatter
    
    init(param:GenericParameter<Float>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        
        self.decimalFormatter = NumberFormatter()
        self.decimalFormatter.numberStyle = .decimal
        self.decimalFormatter.maximumFractionDigits = 5
        
    }
    
    var body: some View
    {
        HStack(spacing: ParameterConfig.horizontalStackSpacing)
        {
            InputFieldLabelView(label: self.vm.label)
            
            FormattedInputFieldComponentView(binding: self.$vm.uiValue,
                                             label: self.vm.label,
                                             formatter: self.decimalFormatter)
        }
    }
}

struct Float2InputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float2>

    let decimalFormatter:NumberFormatter
    
    init(param:GenericParameter<simd_float2>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .decimal
        decimalFormatter.maximumFractionDigits = 5
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5)
        {
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: self.vm.label)
            }
            .frame(width: ParameterConfig.paramWidth)
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "X")

                FormattedInputFieldComponentView(binding: self.$vm.uiValue.x,
                                                 label: self.vm.label + "X",
                                                 formatter: self.decimalFormatter)
            }
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Y")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.y,
                                                 label: self.vm.label + "Y",
                                                 formatter: self.decimalFormatter)
            }
        }
    }
}

struct Float3InputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float3>

    let decimalFormatter:NumberFormatter
    
    init(param:GenericParameter<simd_float3>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .decimal
        decimalFormatter.maximumFractionDigits = 5
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5)
        {
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: self.vm.label)
            }
            .frame(width: ParameterConfig.paramWidth)

            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "X")

                FormattedInputFieldComponentView(binding: self.$vm.uiValue.x,
                                                 label: self.vm.label + "X",
                                                 formatter: self.decimalFormatter)
            }

            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Y")

                FormattedInputFieldComponentView(binding: self.$vm.uiValue.y,
                                                 label: self.vm.label + "Y",
                                                 formatter: self.decimalFormatter)
            }

            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Z")

                FormattedInputFieldComponentView(binding: self.$vm.uiValue.z,
                                                 label: self.vm.label + "Z",
                                                 formatter: self.decimalFormatter)
            }
        }
    }
}


struct Float4InputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float4>

    let decimalFormatter:NumberFormatter
    
    init(param:GenericParameter<simd_float4>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        self.decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .decimal
        decimalFormatter.maximumFractionDigits = 5
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5)
        {
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: self.vm.label)
            }
            .frame(width: ParameterConfig.paramWidth)

            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "X")
                                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.x,
                                                 label: self.vm.label + "X",
                                                 formatter: self.decimalFormatter)
            }
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Y")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.y,
                                                 label: self.vm.label + "Y",
                                                 formatter: self.decimalFormatter)
            }
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Z")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.z,
                                                 label: self.vm.label + "Z",
                                                 formatter: self.decimalFormatter)
            }
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "W")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.w,
                                                 label: self.vm.label + "W",
                                                 formatter: self.decimalFormatter)
            }
        }
    }
}

// MARK: - Int Input Fields

struct IntInputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<Int>

    let decimalFormatter:NumberFormatter
    
    init(param:GenericParameter<Int>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        
        self.decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .none
        decimalFormatter.allowsFloats = false
        decimalFormatter.maximumFractionDigits = 0
        decimalFormatter.minimum = 0
    }
    
    var body: some View
    {
        VStack(alignment:.leading, spacing: 0)
        {
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: self.vm.label)
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue, label: self.vm.label, formatter: self.decimalFormatter)
            }
        }
    }
}

struct Int2InputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_int2>

    let decimalFormatter:NumberFormatter
    
    init(param:GenericParameter<simd_int2>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        
        self.decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .none
        decimalFormatter.allowsFloats = false
        decimalFormatter.maximumFractionDigits = 0
        decimalFormatter.minimum = 0
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5)
        {
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: self.vm.label)
            }
            .frame(width: ParameterConfig.paramWidth)

            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "X")

                FormattedInputFieldComponentView(binding: self.$vm.uiValue.x,
                                                 label: self.vm.label + "X",
                                                 formatter: self.decimalFormatter)
            }
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Y")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.y,
                                                 label: self.vm.label + "Y",
                                                 formatter: self.decimalFormatter)
            }
        }
    }
}

struct Int3InputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_int3>

    let decimalFormatter:NumberFormatter
    
    init(param:GenericParameter<simd_int3>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        
        self.decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .none
        decimalFormatter.allowsFloats = false
        decimalFormatter.maximumFractionDigits = 0
        decimalFormatter.minimum = 0
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5)
        {
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: self.vm.label)
            }
            .frame(width: ParameterConfig.paramWidth)

            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "X")
                                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.x,
                                                 label: self.vm.label + "X",
                                                 formatter: self.decimalFormatter)
            }

            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Y")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.y,
                                                 label: self.vm.label + "Y",
                                                 formatter: self.decimalFormatter)
            }
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Z")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.z,
                                                 label: self.vm.label + "Z",
                                                 formatter: self.decimalFormatter)
            }
        }
    }
}

struct Int4InputFieldView: View
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_int4>

    let decimalFormatter:NumberFormatter
    
    init(param:GenericParameter<simd_int4>)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        
        self.decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .none
        decimalFormatter.allowsFloats = false
        decimalFormatter.maximumFractionDigits = 0
        decimalFormatter.minimum = 0
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5)
        {
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: self.vm.label)
            }
            .frame(width: ParameterConfig.paramWidth)

            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "X")
                                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.x,
                                                 label: self.vm.label + "X",
                                                 formatter: self.decimalFormatter)
            }
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Y")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.y,
                                                 label: self.vm.label + "Y",
                                                 formatter: self.decimalFormatter)
            }
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "Z")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.z,
                                                 label: self.vm.label + "Z",
                                                 formatter: self.decimalFormatter)
            }
            
            HStack(spacing: ParameterConfig.horizontalStackSpacing)
            {
                InputFieldLabelView(label: "W")
                
                FormattedInputFieldComponentView(binding: self.$vm.uiValue.w,
                                                 label: self.vm.label + "W",
                                                 formatter: self.decimalFormatter)
            }
        }
    }
}
