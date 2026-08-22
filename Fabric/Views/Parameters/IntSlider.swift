//
//  Slider.swift
//  v
//
//  Created by Anton Marini on 4/13/24.
//

import SwiftUI
import Satin
import simd

fileprivate struct SimpleIntSlider<T : SignedInteger & CVarArg>: View
{
    let label:String
    @Binding var value:T
    @Binding var min:T
    @Binding var max:T
    
    @State var sliderForegroundColor:Color = .black.opacity(0.25)
    @State var recorderForegroundColor:Color = .orange

    private let sliderHeight = 20.0

    // private let colors = [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple]

    var body: some View
    {
        GeometryReader
        { geometry in
            
            let sliderWidth = Swift.max(geometry.size.width, 1)
            let cornerRadius = 4.0 // min(12, max(3.0, sliderHeight / 5.0) )
            let valueWidth = sliderWidth * CGFloat( remap( Float(self.value), Float(self.min), Float(self.max), 0.0, 1.0) )
            
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
                        
                        Text(String(self.value) )
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .font(.system(size: 10))
                    }
                    .padding()
                    .frame(width: sliderWidth, height: self.sliderHeight)
                }
                .frame(width: sliderWidth, height: self.sliderHeight)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged({ v in
                        let normalizedValue = Swift.min(Swift.max(0.0, Float(v.location.x / sliderWidth )), 1.0)
                        
                        self.value = T(remap(normalizedValue,
                                           0.0,
                                           1.0,
                                           Float(self.min),
                                           Float(self.max)))
                    })
                )
            }
            .cornerRadius(cornerRadius)
        }
    }
}

struct IntSlider: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<Int>
    @Bindable var vmMin: ParameterObservableModel<Int>
    @Bindable var vmMax: ParameterObservableModel<Int>

    init(param: IntParameter)
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
        SimpleIntSlider<Int>(label: self.vm.label, value: self.$vm.uiValue, min: self.$vmMin.uiValue, max: self.$vmMax.uiValue)
    }
}


struct Int2Slider: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_int2>
    @Bindable var vmMin: ParameterObservableModel<simd_int2>
    @Bindable var vmMax: ParameterObservableModel<simd_int2>

    init(param: Int2Parameter)
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
            SimpleIntSlider<Int32>(label: self.vm.label + "X", value: self.$vm.uiValue.x, min: self.$vmMin.uiValue.x, max: self.$vmMax.uiValue.x)
            SimpleIntSlider<Int32>(label: self.vm.label + "Y", value: self.$vm.uiValue.y, min: self.$vmMin.uiValue.y, max: self.$vmMax.uiValue.y)

        }
        .frame(height:50)
    }
}

struct Int3Slider: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_int3>
    @Bindable var vmMin: ParameterObservableModel<simd_int3>
    @Bindable var vmMax: ParameterObservableModel<simd_int3>

    init(param: Int3Parameter)
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
            SimpleIntSlider<Int32>(label: self.vm.label + "X", value: self.$vm.uiValue.x, min: self.$vmMin.uiValue.x, max: self.$vmMax.uiValue.x)
            SimpleIntSlider<Int32>(label: self.vm.label + "Y", value: self.$vm.uiValue.y, min: self.$vmMin.uiValue.y, max: self.$vmMax.uiValue.y)
            SimpleIntSlider<Int32>(label: self.vm.label + "Z", value: self.$vm.uiValue.z, min: self.$vmMin.uiValue.z, max: self.$vmMax.uiValue.z)
        }
        .frame(height:80)
    }
}

struct Int4Slider: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_int4>
    @Bindable var vmMin: ParameterObservableModel<simd_int4>
    @Bindable var vmMax: ParameterObservableModel<simd_int4>

    init(param: Int4Parameter)
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
            SimpleIntSlider<Int32>(label: self.vm.label + "X", value: self.$vm.uiValue.x, min: self.$vmMin.uiValue.x, max: self.$vmMax.uiValue.x)
            SimpleIntSlider<Int32>(label: self.vm.label + "Y", value: self.$vm.uiValue.y, min: self.$vmMin.uiValue.y, max: self.$vmMax.uiValue.y)
            SimpleIntSlider<Int32>(label: self.vm.label + "Z", value: self.$vm.uiValue.z, min: self.$vmMin.uiValue.z, max: self.$vmMax.uiValue.z)
            SimpleIntSlider<Int32>(label: self.vm.label + "W", value: self.$vm.uiValue.w, min: self.$vmMin.uiValue.w, max: self.$vmMax.uiValue.w)
        }
        .frame(height:100)
    }
}
