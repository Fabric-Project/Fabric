//
//  ContentView.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Satin
import Fabric


struct ContentView: View {
    
    @Binding var document: FabricDocument

    @GestureState private var magnifyBy = 1.0
    
    @State private var finalMagnification = 1.0

    @State private var hitTestEnable:Bool = true
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @State private var inspectorVisibility:Bool = false
    @State private var scrollOffset: CGPoint = .zero
    
    var body: some View {
        
        NavigationSplitView(columnVisibility: self.$columnVisibility)
        {
            NodeRegisitryView(graph: document.graph, scrollOffset: $scrollOffset)

        } detail: {
                    
                    ZStack
                    {
//                        SatinMetalView(renderer: document.graphRenderer)

                        GeometryReader { geom in
                            RadialGradient(colors: [.clear, .black.opacity(0.75)], center: .center, startRadius: 0, endRadius: geom.size.width * 1.5)
                                .allowsHitTesting(false)
                        }

                        ScrollView([.horizontal, .vertical])
                        {
                            NodeCanvas()
                                .frame(width: 10000 , height: 10000)
                                .environment(self.document.graph)
                                                        .allowsHitTesting(self.hitTestEnable)
                            
                        }
                        .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.5))
                        .onScrollGeometryChange(for: CGPoint.self) { geometry in
                            let center = CGPoint(x: geometry.contentSize.width / 2,
                                                 y: geometry.contentSize.height / 2)
                            let offset = (geometry.contentOffset - center) + (geometry.containerSize / 2)
                            return offset
                            
                        } action: { oldScrollOffset, newScrollOffset in
                            self.scrollOffset =  newScrollOffset
                        }
                        .onScrollPhaseChange { oldPhase, newPhase in
                            self.hitTestEnable = !newPhase.isScrolling
                        }
                    
            }
            
            .inspector(isPresented: self.$inspectorVisibility)
            {
                NodeSelectionInspector()
                    .environment(self.document.graph)

            }
            .toolbar
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
