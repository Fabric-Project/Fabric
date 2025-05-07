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

    @State private var hitTestEnable:Bool = true
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @State private var inspectorVisibility:Bool = false
   
    var body: some View {
//        TextEditor(text: $document.text)
        
        NavigationSplitView(columnVisibility: self.$columnVisibility)
        {
            NodeRegisitryView(document: $document)

        } detail: {
            
            ZStack
            {
                SatinMetalView(renderer: document.graphRenderer)
                
                ScrollView([.horizontal, .vertical])
                {
                    NodeCanvas()
                        .frame(width: 10000 , height: 10000)
                        .environment(self.document.graph)
                        .allowsHitTesting(self.hitTestEnable)
//                        .scaleEffect(self.magnifyBy + self.finalMagnification)
//                        .gesture(magnification)
                    
                }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.5))
                .onScrollPhaseChange { oldPhase, newPhase in
                    self.hitTestEnable = !newPhase.isScrolling
                }
                .scrollIndicators(.never, axes: [.horizontal, .vertical])
                
            }
            .inspector(isPresented: self.$inspectorVisibility)
            {
                NodeSelectionInspector()
                    .environment(self.document.graph)

            }
            .toolbar()
            {
                ToolbarItem(placement: .automatic)
                {
                    Button("Parameters", systemImage: "info.circle") {
                        self.inspectorVisibility.toggle()
                    }
                }
            }
        }

    }
}

#Preview {
    ContentView(document: .constant(FabricDocument()))
}
