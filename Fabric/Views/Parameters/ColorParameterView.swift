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
    static func == (lhs: Color4ParameterView, rhs: Color4ParameterView) -> Bool
    {
        return lhs.parameter.id == rhs.parameter.id
    }
    
    @Bindable var parameter:Float4Parameter
    
    var body: some View {
        
        let binding = Binding<Color>.init {
            return Color(.sRGBLinear,
                  red: Double(self.parameter.value.x),
                  green: Double(self.parameter.value.y),
                  blue: Double(self.parameter.value.z),
                  opacity: Double(self.parameter.value.w) )
        } set: { color in
            let resolved = color.resolve(in: .init())
            
            self.parameter.value = simd_float4(resolved.linearRed, resolved.linearGreen, resolved.linearBlue, resolved.opacity)
        }
        
        ColorPicker(selection: binding, supportsOpacity: true) {
            
            LinearGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple]), startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 4.0))
                .overlay(
                    Text(self.parameter.label)
                        .lineLimit(1)
                        .font(.system(size: 10))
                        .padding(.horizontal, 10)
                )
        }
    }
}

struct Color3ParameterView: View, Equatable
{
    static func == (lhs: Color3ParameterView, rhs: Color3ParameterView) -> Bool
    {
        return lhs.parameter.id == rhs.parameter.id
    }
    
    @Bindable var parameter:Float3Parameter
    
    var body: some View {
        
        let binding = Binding<Color>.init {
            return Color(.sRGBLinear,
                         red: Double(self.parameter.value.x),
                         green: Double(self.parameter.value.y),
                         blue: Double(self.parameter.value.z)
            )
        } set: { color in
            let resolved = color.resolve(in: .init())
            
            self.parameter.value = simd_float3(resolved.linearRed, resolved.linearGreen, resolved.linearBlue)
        }
        
        ColorPicker(selection: binding, supportsOpacity: false)
        {
            LinearGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple]), startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 4.0))
                .overlay(
                    Text(self.parameter.label)
                        .lineLimit(1)
                        .frame( alignment: .leading)
                        .font(.system(size: 10))
                        .padding(.horizontal, 10)
                )
            
        }
        
        
    }
}

