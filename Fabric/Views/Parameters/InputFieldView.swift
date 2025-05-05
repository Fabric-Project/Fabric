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
