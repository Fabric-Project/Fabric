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
    
    static func == (lhs: XYPad, rhs: XYPad) -> Bool
    {
        return lhs.parameter.id == rhs.parameter.id
    }
    
    
    @ObservedObject var parameter:Float2Parameter

    init(param:Float2Parameter)
    {
        self.parameter = param
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
                Rectangle()
                    .foregroundColor(.gray)
                    
                Circle()
                    .frame(width: circleDiameter, height: circleDiameter)
                    
                    .position(x:  CGFloat(remap(self.parameter.value.x,
                                                self.parameter.min.x,
                                                self.parameter.max.x,
                                                0.0,
                                                1.0)) * width,
                              y:  CGFloat(remap(self.parameter.value.y,
                                                self.parameter.min.y,
                                                self.parameter.max.y,
                                                1.0,
                                                0.0)) * height)
                    .foregroundColor(.orange)
                

                Text(self.parameter.label)
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
                                  self.parameter.min.x,
                                  self.parameter.max.x)
                    
                    let y = remap(normalizedValueY,
                                  1.0,
                                  0.0,
                                  self.parameter.min.y,
                                  self.parameter.max.y)
                    
                    self.parameter.value = simd_float2(x, y)
                    
//                    if self.recording.wrappedValue
//                    {
//                        self.recorder.record( 1.0 - normalizedValue, atTime: Date.timeIntervalSinceReferenceDate)
//                    }
                }))


        }
//        .frame(height: 100)

    }
}

//#Preview
//{
////    XYPad(parameter: <#T##Binding<Float2Parameter>#>: .constant(simd_float2(0.5, 0.5) ) )
////        .frame(width: 300, height: 300)
//}
