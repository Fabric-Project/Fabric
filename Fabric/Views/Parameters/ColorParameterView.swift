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
    
    @Bindable var parameter:GenericParameter<simd_float4>
    @State var color:Color = .purple
    
    var body: some View {
        
        ColorPicker(selection: self.$color, supportsOpacity: true) {
            
            LinearGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple]), startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 4.0))
                .overlay(
                    Text(self.parameter.label)
                        .lineLimit(1)
                        .font(.system(size: 10))
                        .padding(.horizontal, 10)
                )
        }
        .onChange(of: self.color) {
            let resolved = self.color.resolve(in: .init())
            
            self.parameter.value = simd_float4(resolved.linearRed, resolved.linearGreen, resolved.linearBlue, resolved.opacity)
        }
        
    }
}

struct Color3ParameterView: View, Equatable
{
    static func == (lhs: Color3ParameterView, rhs: Color3ParameterView) -> Bool
    {
        return lhs.parameter.id == rhs.parameter.id
    }
    
    @Bindable var parameter:GenericParameter<simd_float3>
    @State var color:Color = .purple
    
    var body: some View {
        
        ColorPicker(selection: self.$color, supportsOpacity: false) {
            
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
        .onChange(of: self.color) {
            let resolved = self.color.resolve(in: .init())
            
            self.parameter.value = simd_float3(resolved.linearRed, resolved.linearGreen, resolved.linearBlue)
        }
        
    }
}

