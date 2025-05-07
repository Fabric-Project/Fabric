//
//  InputFieldView.swift
//  v
//
//  Created by Anton Marini on 4/9/25.
//

import SwiftUI
import Satin

struct InputFieldView: View {
 
    @Bindable var parameter:StringParameter

    init(param:StringParameter)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        TextField(parameter.label, text: $parameter.value)
            .font(.system(size: 10))
            .textFieldStyle(.roundedBorder)
            .lineLimit(1)
            .padding()
        
    }
}

// MARK: - Float Input Fields

struct FloatInputFieldView: View {
 
    @Bindable var parameter:GenericParameter<Float>

    let decimalFormatter: NumberFormatter = {
          let formatter = NumberFormatter()
          formatter.numberStyle = .decimal
          formatter.maximumFractionDigits = 3
          return formatter
      }()
    
    init(param:GenericParameter<Float>)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        TextField(parameter.label, value: $parameter.value, formatter:decimalFormatter)
            .font(.system(size: 10))
            .textFieldStyle(.roundedBorder)
            .lineLimit(1)
            .padding()
        
    }
}

struct Float2InputFieldView: View {
 
    @Bindable var parameter:GenericParameter<simd_float2>

    let decimalFormatter: NumberFormatter = {
          let formatter = NumberFormatter()
          formatter.numberStyle = .decimal
          formatter.maximumFractionDigits = 3
          return formatter
      }()
    
    init(param:GenericParameter<simd_float2>)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5){
            Text(parameter.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(parameter.label + " x" , value: $parameter.value.x, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " y" , value: $parameter.value.y, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
    }
}

struct Float3InputFieldView: View {
 
    @Bindable var parameter:GenericParameter<simd_float3>

    let decimalFormatter: NumberFormatter = {
          let formatter = NumberFormatter()
          formatter.numberStyle = .decimal
          formatter.maximumFractionDigits = 3
          return formatter
      }()
    
    init(param:GenericParameter<simd_float3>)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5){
            Text(parameter.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(parameter.label + " x" , value: $parameter.value.x, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " y" , value: $parameter.value.y, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " z" , value: $parameter.value.z, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
    }
}

struct Float4InputFieldView: View {
 
    @Bindable var parameter:GenericParameter<simd_float4>

    let decimalFormatter: NumberFormatter = {
          let formatter = NumberFormatter()
          formatter.numberStyle = .decimal
          formatter.maximumFractionDigits = 3
          return formatter
      }()
    
    init(param:GenericParameter<simd_float4>)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5){
            Text(parameter.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(parameter.label + " x" , value: $parameter.value.x, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " y" , value: $parameter.value.y, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " z" , value: $parameter.value.z, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " w" , value: $parameter.value.w, formatter:decimalFormatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
    }
}

// MARK: - Int Input Fields

struct IntInputFieldView: View {
 
    @Bindable var parameter:GenericParameter<Int>
    
    let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    init(param:GenericParameter<Int>)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        TextField(parameter.label, value: $parameter.value, formatter:formatter)
            .font(.system(size: 10))
            .textFieldStyle(.roundedBorder)
            .lineLimit(1)
            .padding()
        
    }
}

struct Int2InputFieldView: View {
 
    @Bindable var parameter:GenericParameter<simd_int2>

    let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    init(param:GenericParameter<simd_int2>)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5){
            Text(parameter.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(parameter.label + " x" , value: $parameter.value.x, formatter:formatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " y" , value: $parameter.value.y, formatter:formatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
    }
}

struct Int3InputFieldView: View {
 
    @Bindable var parameter:GenericParameter<simd_int3>

    let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    init(param:GenericParameter<simd_int3>)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5){
            Text(parameter.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(parameter.label + " x" , value: $parameter.value.x, formatter:formatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " y" , value: $parameter.value.y, formatter:formatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " z" , value: $parameter.value.z, formatter:formatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
    }
}

struct Int4InputFieldView: View {
 
    @Bindable var parameter:GenericParameter<simd_int4>

    let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    init(param:GenericParameter<simd_int4>)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        VStack(alignment: .leading, spacing: 5){
            Text(parameter.label)
                .font(.system(size: 10))
                .lineLimit(1)

            TextField(parameter.label + " x" , value: $parameter.value.x, formatter:formatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " y" , value: $parameter.value.y, formatter:formatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " z" , value: $parameter.value.z, formatter:formatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            
            TextField(parameter.label + " w" , value: $parameter.value.w, formatter:formatter)
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
        .padding()
    }
}
