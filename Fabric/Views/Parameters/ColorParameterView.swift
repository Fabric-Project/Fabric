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
    
    init(parameter: Float4Parameter, port: NodePort<simd_float4>? = nil)
    {
        
        self.vm = ParameterObservableModel(control: ControlValue(parameter: parameter, port: port),
                                           publisher: parameter.valuePublisher)
    
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
        
        HStack(spacing: ParameterConfig.horizontalStackSpacing)
        {
            InputFieldLabelView(label: vm.label )

            ColorPicker(selection: binding, supportsOpacity: true) {
            }
            .labelsHidden()
            .frame(width: ParameterConfig.paramWidth, alignment: .leading)
        }
    }
}

struct Color3ParameterView: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }
    
    @Bindable var vm: ParameterObservableModel<simd_float3>

    init(parameter: Float3Parameter, port: NodePort<simd_float3>? = nil)
    {
        self.vm = ParameterObservableModel(control: ControlValue(parameter: parameter, port: port),
                                           publisher: parameter.valuePublisher)
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
        
        HStack(spacing: ParameterConfig.horizontalStackSpacing)
        {
            InputFieldLabelView(label: vm.label )

            ColorPicker(selection: binding, supportsOpacity: false) {
            }
            .labelsHidden()
            .frame(width: ParameterConfig.paramWidth, alignment: .leading)
        }
    }
}

