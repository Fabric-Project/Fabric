//
//  DebugBox.swift
//  v
//
//  Created by Anton Marini on 4/15/24.
//

import SwiftUI
import Satin
import simd

struct XYPad: View, Equatable {
    
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<simd_float2>
    @Bindable var vmMin: ParameterObservableModel<simd_float2>
    @Bindable var vmMax: ParameterObservableModel<simd_float2>


    init(param:Float2Parameter)
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
    
    var body: some View {
        
        GeometryReader
        { geometry in
            
            let circleDiameter = 10.0
            let width = geometry.size.width// - circleDiameter
            let height = geometry.size.height// - circleDiameter
            let cornerRadius = 4.0 // min(12, max(3.0, sliderHeight / 5.0) )

            ZStack
            {
                Color.gray
                    
                Circle()
                    .frame(width: circleDiameter, height: circleDiameter)
                    
                    .position(x:  CGFloat(remap(self.vm.uiValue.x,
                                                self.vmMin.uiValue.x,
                                                self.vmMax.uiValue.x,
                                                0.0,
                                                1.0)) * width,
                              y:  CGFloat(remap(self.vm.uiValue.y,
                                                self.vmMin.uiValue.y,
                                                self.vmMax.uiValue.y,
                                                1.0,
                                                0.0)) * height)
                    .foregroundColor(.orange)
                

                Text(self.vm.label)
                    .font(.system(size: 10))

            }
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius)
            )
//            .overlay {
//                RoundedRectangle(cornerRadius: cornerRadius)
//                    .stroke(.orange, lineWidth: 2.0)
//            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged({ v in
                    let normalizedValueX = min(max(0.0, Float(v.location.x / width )), 1.0)
                    let normalizedValueY = min(max(0.0, Float(v.location.y / height )), 1.0)
                    
                    let x = remap(normalizedValueX,
                                  0.0,
                                  1.0,
                                  self.vmMin.uiValue.x,
                                  self.vmMax.uiValue.x)
                    
                    let y = remap(normalizedValueY,
                                  1.0,
                                  0.0,
                                  self.vmMin.uiValue.y,
                                  self.vmMax.uiValue.y)
                    
                    self.vm.uiValue = simd_float2(x, y)
                    
                }))
        }
        .frame(height:200)
    }
}

//#Preview
//{
////    XYPad(parameter: <#T##Binding<Float2Parameter>#>: .constant(simd_float2(0.5, 0.5) ) )
////        .frame(width: 300, height: 300)
//}
