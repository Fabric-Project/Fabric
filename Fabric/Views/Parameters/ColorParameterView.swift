//
//  ColorParameterView.swift
//  v
//
//  Created by Anton Marini on 11/3/24.
//

import SwiftUI
import Satin
import simd

struct Color4ParameterView: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float4>

    @State var color = Color.white
    
    init(parameter: Float4Parameter)
    {
        
        self.vm = ParameterObservableModel(label: parameter.label,
                                           get: { parameter.value },
                                           set: { parameter.value = $0 },
                                           publisher:parameter.valuePublisher )
    
    }
    
    var body: some View {
        
        let binding = Binding<Color>.init {
            return Color(.sRGBLinear,
                         red: Double( vm.uiValue.x),
                         green: Double(vm.uiValue.y),
                         blue: Double(vm.uiValue.z),
                         opacity: Double(vm.uiValue.w) )
        } set: { color in
            let resolved = color.resolve(in: .init())
            
            vm.uiValue = simd_float4(resolved.linearRed, resolved.linearGreen, resolved.linearBlue, resolved.opacity)
        }
        
        ColorPicker(selection: binding, supportsOpacity: true) {
            
            LinearGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple]), startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 4.0))
                .overlay(
                    Text(vm.label)
                        .lineLimit(1)
                        .font(.system(size: 10))
                        .padding(.horizontal, 10)
                )
        }
    }
}

struct Color3ParameterView: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }
    
    @Bindable var vm: ParameterObservableModel<simd_float3>

    init(parameter: Float3Parameter)
    {
        self.vm = ParameterObservableModel(label: parameter.label,
                                           get: { parameter.value },
                                           set: { parameter.value = $0 },
                                           publisher:parameter.valuePublisher )
    }
    
    var body: some View {
        
        let binding = Binding<Color>.init {
            return Color(.sRGBLinear,
                         red: Double(vm.uiValue.x),
                         green: Double(vm.uiValue.y),
                         blue: Double(vm.uiValue.z)
            )
        } set: { color in
            let resolved = color.resolve(in: .init())
            
            vm.uiValue = simd_float3(resolved.linearRed, resolved.linearGreen, resolved.linearBlue)
        }
        
        ColorPicker(selection: binding, supportsOpacity: false)
        {
            LinearGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple]), startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 4.0))
                .overlay(
                    Text(vm.label)
                        .lineLimit(1)
                        .frame( alignment: .leading)
                        .font(.system(size: 10))
                        .padding(.horizontal, 10)
                )
        }
    }
}

