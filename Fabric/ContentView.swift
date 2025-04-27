//
//  ContentView.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Satin

struct ContentView: View {
    @Binding var document: FabricDocument

    @GestureState private var magnifyBy = 1.0
    
    @State private var finalMagnification = 1.0
    
//    @State private var position = ScrollPosition( anchor: UnitPoint(x: 0.5, y: 0.5))
//    @State private var position = ScrollPosition( anchor: UnitPoint(x: 0.5, y: 0.5))

    
//    var magnification: some Gesture {
//        MagnifyGesture()
//            .updating($magnifyBy) { value, gestureState, transaction in
//                gestureState = value.magnification
//            }
//            .onEnded { value in
//                self.finalMagnification = value.magnification
//            }
//    }
   
    var body: some View {
//        TextEditor(text: $document.text)
        
            ZStack
            {
                Color.black.opacity(0.2)
                
                SatinMetalView(renderer: document.graphRenderer)
                
                ScrollView([.horizontal, .vertical])
                {
                    NodeCanvas()
                        .frame(width: 10000 , height: 10000)
                        .environment(self.document.graph)
//                        .scaleEffect(self.magnifyBy + self.finalMagnification)
                    
//                        .gesture(magnification)
                    
                }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.5))

                
                
            
        }
    }
}

#Preview {
    ContentView(document: .constant(FabricDocument()))
}
