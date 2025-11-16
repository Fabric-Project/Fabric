//
//  Slider.swift
//  v
//
//  Created by Anton Marini on 4/13/24.
//

import SwiftUI
import Satin
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
            let sliderHeight = max(geometry.size.height, 1)
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
                    .frame(width: sliderWidth, height: sliderHeight)
                }
                .frame(width: sliderWidth, height: sliderHeight)

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
