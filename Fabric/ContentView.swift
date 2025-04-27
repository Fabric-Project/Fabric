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
            .inspector(isPresented: self.$inspectorVisibility)
            {
                Text("Node params go here")
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
