//
//  ColorParameterView.swift
//  v
//
//  Created by Anton Marini on 11/3/24.
//

import SwiftUI
import Satin
import simd

struct ColorParameterView: View, Equatable
{
    static func == (lhs: ColorParameterView, rhs: ColorParameterView) -> Bool
    {
        return lhs.parameter.id == rhs.parameter.id
    }
    
    @ObservedObject var parameter:Float4Parameter
    @State var color:Color = .purple
    
    var body: some View {
        
            ZStack
            {
                ColorPicker(selection: self.$color, supportsOpacity: true) {
                    
                    LinearGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple]), startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 4.0))
                        .overlay(
                            Text(self.parameter.label).frame(maxWidth: .infinity, alignment: .leading)
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
}
