//
//  InputFieldView.swift
//  v
//
//  Created by Anton Marini on 4/9/25.
//

import SwiftUI
import Satin

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
        HStack
        {
            Text(vm.label)
                .font(.system(size: 10))
                .lineLimit(1)
            Spacer()
            
            TextField(vm.label, text: $vm.uiValue)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .padding()
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
        decimalFormatter.numberStyle = .decimal
        decimalFormatter.maximumFractionDigits = 5
    }
    
    var body: some View
    {
        HStack
        {
            Text(vm.label)
                .font(.system(size: 10))
                .lineLimit(1)
            
            Spacer()
            
            TextField(vm.label, value: $vm.uiValue, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .padding()
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
        VStack(alignment: .leading, spacing: 5){
            Text(vm.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(vm.label + " x" , value: $vm.uiValue.x, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " y" , value: $vm.uiValue.y, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
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
        VStack(alignment: .leading, spacing: 5){
            Text(vm.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(vm.label + " x" , value: $vm.uiValue.x, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " y" , value: $vm.uiValue.y, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " z" , value: $vm.uiValue.z, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
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
        VStack(alignment: .leading, spacing: 5){
            Text(vm.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(vm.label + " x" , value: $vm.uiValue.x, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " y" , value: $vm.uiValue.y, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " z" , value: $vm.uiValue.z, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " w" , value: $vm.uiValue.w, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
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
        HStack
        {
            Text(vm.label)
                .font(.system(size: 10))
                .lineLimit(1)
            
            Spacer()
            
            TextField(vm.label, value: $vm.uiValue, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .padding()
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
        VStack(alignment: .leading, spacing: 5){
            Text(vm.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(vm.label + " x" , value: $vm.uiValue.x, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " y" , value: $vm.uiValue.y, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
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
        VStack(alignment: .leading, spacing: 5){
            Text(vm.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(vm.label + " x" , value: $vm.uiValue.x, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " y" , value: $vm.uiValue.y, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " z" , value: $vm.uiValue.z, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
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
        VStack(alignment: .leading, spacing: 5){
            Text(vm.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(vm.label + " x" , value: $vm.uiValue.x, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " y" , value: $vm.uiValue.y, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " z" , value: $vm.uiValue.z, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(vm.label + " w" , value: $vm.uiValue.w, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
    }
}
