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
    
    static func == (lhs: FloatSlider, rhs: FloatSlider) -> Bool {
        return lhs.param.id == lhs.param.id
    }

    @ObservedObject var param:FloatParameter
    
    @State var sliderForgroundColor:Color = .black.opacity(0.25)
    @State var recorderForgroundColor:Color = .orange
            
//    private let colors = [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple]

    init(param: FloatParameter)
    {
        self.param = param
    }
    
    
    var body: some View
    {
//        let _ = Self._printChanges()

        GeometryReader
        { geometry in
            
            let maxWidth = 30.0
            let sliderWidth = max(geometry.size.width - maxWidth, 1)
            let sliderHeight = max(geometry.size.height, 1)
            let cornerRadius = 4.0 // min(12, max(3.0, sliderHeight / 5.0) )

            HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 0.0, content:
            {
                ZStack(alignment: .leading)
                {
                    Rectangle()
                        .foregroundColor( self.recorderForgroundColor )
                        .frame(maxWidth: maxWidth, maxHeight: sliderHeight)
                }
                
                
                ZStack(alignment: .leading)
                {
                    Color.gray
                    //colors.randomElement()
                    
                
                    
                    Rectangle()
                        .foregroundColor(self.sliderForgroundColor)
                        .frame(width: sliderWidth * CGFloat( remap(self.param.value,
                                                                   self.param.min,
                                                                   self.param.max,
                                                                   0.0,
                                                                   1.0) ) )

                    HStack( content: {
                        Text(self.param.label).frame(maxWidth: .infinity, alignment: .leading)
                            .font(.system(size: 10))
                        
                        Text(String(format: "%0.2f", self.param.value) ).frame(maxWidth: .infinity, alignment: .trailing)
                            .font(.system(size: 10))
                    })
                    .padding()
                    .frame(width: sliderWidth, height: sliderHeight)
                }
                .frame(width: sliderWidth, height: sliderHeight)

                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged({ v in
                        let normalizedValue = min(max(0.0, Float(v.location.x / sliderWidth )), 1.0)
                        
                        self.param.value = remap(normalizedValue,
                                                 0.0,
                                                 1.0,
                                                 self.param.min,
                                                 self.param.max)
                    }))
            })
            .cornerRadius(cornerRadius)

        }
//        .frame(height: sliderHeight)
//            .keyboardShortcut(KeyEquivalent("r"), modifiers: /*@START_MENU_TOKEN@*/.command/*@END_MENU_TOKEN@*/)
//            {
////                $recording = !$recording
//            }
        
    }
}


//#Preview {
//    @State var value:Float = 0.5
//    vSlider(valueMin: 0, valueMax: 1, value: $value)
//}
