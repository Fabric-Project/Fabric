//
//  Slider.swift
//  v
//
//  Created by Anton Marini on 4/13/24.
//

import SwiftUI
import Satin
import simd

struct FloatSlider: View, Equatable
{
    static let sliderHeight = 20.0
    
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<Float>
    @Bindable var vmMin: ParameterObservableModel<Float>
    @Bindable var vmMax: ParameterObservableModel<Float>

    @State var sliderForegroundColor:Color = .black.opacity(0.25)
    @State var recorderForegroundColor:Color = .orange
            
//    private let colors = [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple]

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
        GeometryReader
        { geometry in
            
            let sliderWidth = max(geometry.size.width, 1)
            let cornerRadius = 4.0 // min(12, max(3.0, sliderHeight / 5.0) )

            HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 0.0, content:
            {
                ZStack(alignment: .leading)
                {
                    Color.gray
                    //colors.randomElement()
                    
                    Rectangle()
                        .foregroundColor(self.sliderForegroundColor)
                        .frame(width: sliderWidth * CGFloat( remap(self.vm.uiValue,
                                                                   self.vmMin.uiValue,
                                                                   self.vmMax.uiValue,
                                                                   0.0,
                                                                   1.0) ) )
                    HStack
                    {
                        Text(vm.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.system(size: 10))
                        
                        Text(String(format: "%0.2f", vm.uiValue) )
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .font(.system(size: 10))
                    }
                    .padding()
                    .frame(width: sliderWidth, height: Self.sliderHeight)
                }
                .frame(width: sliderWidth, height: Self.sliderHeight)

                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged({ v in
                        let normalizedValue = min(max(0.0, Float(v.location.x / sliderWidth )), 1.0)
                        
                        vm.uiValue = remap(normalizedValue,
                                           0.0,
                                           1.0,
                                           vmMin.uiValue,
                                           vmMax.uiValue)
                    }))
            })
            .cornerRadius(cornerRadius)

        }
    }
}


struct Float2Slider: View, Equatable
{
    static let sliderHeight = 20.0
    
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float2>
    @Bindable var vmMin: ParameterObservableModel<simd_float2>
    @Bindable var vmMax: ParameterObservableModel<simd_float2>

    @State var sliderForegroundColor:Color = .black.opacity(0.25)
    @State var recorderForegroundColor:Color = .orange
            
//    private let colors = [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple]

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
        GeometryReader
        { geometry in
            
            let sliderWidth = max(geometry.size.width, 1)
            let cornerRadius = 4.0 // min(12, max(3.0, sliderHeight / 5.0) )

            VStack
            {
                // X
                HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 0.0, content:
                        {
                    ZStack(alignment: .leading)
                    {
                        Color.gray
                        //colors.randomElement()
                        
                        Rectangle()
                            .foregroundColor(self.sliderForegroundColor)
                            .frame(width: sliderWidth * CGFloat( remap(self.vm.uiValue.x,
                                                                       self.vmMin.uiValue.x,
                                                                       self.vmMax.uiValue.x,
                                                                       0.0,
                                                                       1.0) ) )
                        HStack
                        {
                            Text(vm.label + " X")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 10))
                            
                            Text(String(format: "%0.2f", vm.uiValue.x) )
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .font(.system(size: 10))
                        }
                        .padding()
                        .frame(width: sliderWidth, height: Self.sliderHeight)
                    }
                    .frame(width: sliderWidth, height: Self.sliderHeight)
                    
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged({ v in
                            let normalizedValue = min(max(0.0, Float(v.location.x / sliderWidth )), 1.0)
                            
                            vm.uiValue.x = remap(normalizedValue,
                                               0.0,
                                               1.0,
                                               vmMin.uiValue.x,
                                               vmMax.uiValue.x)
                        }))
                })
                .cornerRadius(cornerRadius)
                
                // Y
                HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 0.0, content:
                        {
                    ZStack(alignment: .leading)
                    {
                        Color.gray
                        //colors.randomElement()
                        
                        Rectangle()
                            .foregroundColor(self.sliderForegroundColor)
                            .frame(width: sliderWidth * CGFloat( remap(self.vm.uiValue.y,
                                                                       self.vmMin.uiValue.y,
                                                                       self.vmMax.uiValue.y,
                                                                       0.0,
                                                                       1.0) ) )
                        HStack
                        {
                            Text(vm.label + " Y")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 10))
                            
                            Text(String(format: "%0.2f", vm.uiValue.y) )
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .font(.system(size: 10))
                        }
                        .padding()
                        .frame(width: sliderWidth, height: Self.sliderHeight)
                    }
                    .frame(width: sliderWidth, height: Self.sliderHeight)
                    
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged({ v in
                            let normalizedValue = min(max(0.0, Float(v.location.x / sliderWidth )), 1.0)
                            
                            vm.uiValue.y = remap(normalizedValue,
                                               0.0,
                                               1.0,
                                               vmMin.uiValue.y,
                                               vmMax.uiValue.y)
                        }))
                })
                .cornerRadius(cornerRadius)
            }
        }
    }
}

struct Float3Slider: View, Equatable
{
    static let sliderHeight = 20.0
    
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float3>
    @Bindable var vmMin: ParameterObservableModel<simd_float3>
    @Bindable var vmMax: ParameterObservableModel<simd_float3>

    @State var sliderForegroundColor:Color = .black.opacity(0.25)
    @State var recorderForegroundColor:Color = .orange
            
//    private let colors = [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple]

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
        GeometryReader
        { geometry in
            
            let sliderWidth = max(geometry.size.width, 1)
            let cornerRadius = 4.0 // min(12, max(3.0, sliderHeight / 5.0) )

            VStack
            {
                // X
                HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 0.0, content:
                        {
                    ZStack(alignment: .leading)
                    {
                        Color.gray
                        //colors.randomElement()
                        
                        Rectangle()
                            .foregroundColor(self.sliderForegroundColor)
                            .frame(width: sliderWidth * CGFloat( remap(self.vm.uiValue.x,
                                                                       self.vmMin.uiValue.x,
                                                                       self.vmMax.uiValue.x,
                                                                       0.0,
                                                                       1.0) ) )
                        HStack
                        {
                            Text(vm.label + " X")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 10))
                            
                            Text(String(format: "%0.2f", vm.uiValue.x) )
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .font(.system(size: 10))
                        }
                        .padding()
                        .frame(width: sliderWidth, height: Self.sliderHeight)
                    }
                    .frame(width: sliderWidth, height: Self.sliderHeight)
                    
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged({ v in
                            let normalizedValue = min(max(0.0, Float(v.location.x / sliderWidth )), 1.0)
                            
                            vm.uiValue.x = remap(normalizedValue,
                                               0.0,
                                               1.0,
                                               vmMin.uiValue.x,
                                               vmMax.uiValue.x)
                        }))
                })
                .cornerRadius(cornerRadius)
                .frame(width: sliderWidth, height: Self.sliderHeight)

                // Y
                HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 0.0, content:
                        {
                    ZStack(alignment: .leading)
                    {
                        Color.gray
                        //colors.randomElement()
                        
                        Rectangle()
                            .foregroundColor(self.sliderForegroundColor)
                            .frame(width: sliderWidth * CGFloat( remap(self.vm.uiValue.y,
                                                                       self.vmMin.uiValue.y,
                                                                       self.vmMax.uiValue.y,
                                                                       0.0,
                                                                       1.0) ) )
                        HStack
                        {
                            Text(vm.label + " Y")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 10))
                            
                            Text(String(format: "%0.2f", vm.uiValue.y) )
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .font(.system(size: 10))
                        }
                        .padding()
                        .frame(width: sliderWidth, height: Self.sliderHeight)
                    }
                    .frame(width: sliderWidth, height: Self.sliderHeight)
                    
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged({ v in
                            let normalizedValue = min(max(0.0, Float(v.location.x / sliderWidth )), 1.0)
                            
                            vm.uiValue.y = remap(normalizedValue,
                                               0.0,
                                               1.0,
                                               vmMin.uiValue.y,
                                               vmMax.uiValue.y)
                        }))
                })
                .cornerRadius(cornerRadius)
                .frame(width: sliderWidth, height: Self.sliderHeight)

                // Z
                HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 0.0, content:
                        {
                    ZStack(alignment: .leading)
                    {
                        Color.gray
                        //colors.randomElement()
                        
                        Rectangle()
                            .foregroundColor(self.sliderForegroundColor)
                            .frame(width: sliderWidth * CGFloat( remap(self.vm.uiValue.z,
                                                                       self.vmMin.uiValue.z,
                                                                       self.vmMax.uiValue.z,
                                                                       0.0,
                                                                       1.0) ) )
                        HStack
                        {
                            Text(vm.label + " Z")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 10))
                            
                            Text(String(format: "%0.2f", vm.uiValue.z) )
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .font(.system(size: 10))
                        }
                        .padding()
                        .frame(width: sliderWidth, height: Self.sliderHeight)
                    }
                    .frame(width: sliderWidth, height: Self.sliderHeight)
                    
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged({ v in
                            let normalizedValue = min(max(0.0, Float(v.location.x / sliderWidth )), 1.0)
                            
                            vm.uiValue.z = remap(normalizedValue,
                                               0.0,
                                               1.0,
                                               vmMin.uiValue.z,
                                               vmMax.uiValue.z)
                        }))
                })
                .cornerRadius(cornerRadius)
                .frame(width: sliderWidth, height: Self.sliderHeight)
            }
        }
        .frame(height:80)
    }
    
}
