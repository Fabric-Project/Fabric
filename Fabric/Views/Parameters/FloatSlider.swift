//
//  Slider.swift
//  v
//
//  Created by Anton Marini on 4/13/24.
//

import SwiftUI
import Satin
import simd

fileprivate struct SimpleFloatSlider: View
{
    let label:String
    @Binding var value:Float
    @Binding var min:Float
    @Binding var max:Float
    
    @State var sliderForegroundColor:Color = .black.opacity(0.25)
    @State var recorderForegroundColor:Color = .orange

    static let sliderHeight = 20.0

    // private let colors = [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple]

    var body: some View
    {
        GeometryReader
        { geometry in
            
            let sliderWidth = Swift.max(geometry.size.width, 1)
            let cornerRadius = 4.0 // min(12, max(3.0, sliderHeight / 5.0) )
            let valueWidth = sliderWidth * CGFloat( remap(self.value, self.min, self.max, 0.0, 1.0) )
            
            HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 0.0)
            {
                ZStack(alignment: .leading)
                {
                    Color.gray
                    //colors.randomElement()
                    
                    Rectangle()
                        .foregroundColor(self.sliderForegroundColor)
                        .frame(width:valueWidth)
                    
                    HStack
                    {
                        Text(self.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.system(size: 10))
                        
                        Text(String(format: "%0.2f", self.value) )
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .font(.system(size: 10))
                    }
                    .padding()
                    .frame(width: sliderWidth, height: Self.sliderHeight)
                }
                .frame(width: sliderWidth, height: Self.sliderHeight)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged({ v in
                        let normalizedValue = Swift.min(Swift.max(0.0, Float(v.location.x / sliderWidth )), 1.0)
                        
                        self.value = remap(normalizedValue,
                                           0.0,
                                           1.0,
                                           self.min,
                                           self.max)
                    })
                )
            }
            .cornerRadius(cornerRadius)
        }
    }
}

struct FloatSlider: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<Float>
    @Bindable var vmMin: ParameterObservableModel<Float>
    @Bindable var vmMax: ParameterObservableModel<Float>

    init(param: FloatParameter)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        
        self.vmMin = ParameterObservableModel(label: param.label,
                                              get: { param.min },
                                              set: { param.min = $0 },
                                              publisher:param.minValuePublisher )
        
        self.vmMax = ParameterObservableModel(label: param.label,
                                              get: { param.max },
                                              set: { param.max = $0 },
                                              publisher:param.maxValuePublisher )
    }
    
    var body: some View
    {
        SimpleFloatSlider(label: self.vm.label, value: self.$vm.uiValue, min: self.$vmMin.uiValue, max: self.$vmMax.uiValue)
    }
}


struct Float2Slider: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float2>
    @Bindable var vmMin: ParameterObservableModel<simd_float2>
    @Bindable var vmMax: ParameterObservableModel<simd_float2>

    init(param: Float2Parameter)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        
        self.vmMin = ParameterObservableModel(label: param.label,
                                              get: { param.min },
                                              set: { param.min = $0 },
                                              publisher:param.minValuePublisher )
        
        self.vmMax = ParameterObservableModel(label: param.label,
                                              get: { param.max },
                                              set: { param.max = $0 },
                                              publisher:param.maxValuePublisher )
    }
    
    var body: some View
    {
       
        VStack
        {
            SimpleFloatSlider(label: self.vm.label + "X", value: self.$vm.uiValue.x, min: self.$vmMin.uiValue.x, max: self.$vmMax.uiValue.x)
            SimpleFloatSlider(label: self.vm.label + "Y", value: self.$vm.uiValue.y, min: self.$vmMin.uiValue.y, max: self.$vmMax.uiValue.y)

        }
        .frame(height:50)
    }
}

struct Float3Slider: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float3>
    @Bindable var vmMin: ParameterObservableModel<simd_float3>
    @Bindable var vmMax: ParameterObservableModel<simd_float3>

    init(param: Float3Parameter)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        
        self.vmMin = ParameterObservableModel(label: param.label,
                                              get: { param.min },
                                              set: { param.min = $0 },
                                              publisher:param.minValuePublisher )
        
        self.vmMax = ParameterObservableModel(label: param.label,
                                              get: { param.max },
                                              set: { param.max = $0 },
                                              publisher:param.maxValuePublisher )
    }
    
    var body: some View
    {
        VStack
        {
            SimpleFloatSlider(label: self.vm.label + "X", value: self.$vm.uiValue.x, min: self.$vmMin.uiValue.x, max: self.$vmMax.uiValue.x)
            SimpleFloatSlider(label: self.vm.label + "Y", value: self.$vm.uiValue.y, min: self.$vmMin.uiValue.y, max: self.$vmMax.uiValue.y)
            SimpleFloatSlider(label: self.vm.label + "Z", value: self.$vm.uiValue.z, min: self.$vmMin.uiValue.z, max: self.$vmMax.uiValue.z)
        }
        .frame(height:80)
    }
}

struct Float4Slider: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float4>
    @Bindable var vmMin: ParameterObservableModel<simd_float4>
    @Bindable var vmMax: ParameterObservableModel<simd_float4>

    init(param: Float4Parameter)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
        
        self.vmMin = ParameterObservableModel(label: param.label,
                                              get: { param.min },
                                              set: { param.min = $0 },
                                              publisher:param.minValuePublisher )
        
        self.vmMax = ParameterObservableModel(label: param.label,
                                              get: { param.max },
                                              set: { param.max = $0 },
                                              publisher:param.maxValuePublisher )
    }
    
    var body: some View
    {
        VStack
        {
            SimpleFloatSlider(label: self.vm.label + "X", value: self.$vm.uiValue.x, min: self.$vmMin.uiValue.x, max: self.$vmMax.uiValue.x)
            SimpleFloatSlider(label: self.vm.label + "Y", value: self.$vm.uiValue.y, min: self.$vmMin.uiValue.y, max: self.$vmMax.uiValue.y)
            SimpleFloatSlider(label: self.vm.label + "Z", value: self.$vm.uiValue.z, min: self.$vmMin.uiValue.z, max: self.$vmMax.uiValue.z)
            SimpleFloatSlider(label: self.vm.label + "W", value: self.$vm.uiValue.w, min: self.$vmMin.uiValue.w, max: self.$vmMax.uiValue.w)
        }
        .frame(height:100)
    }
}
