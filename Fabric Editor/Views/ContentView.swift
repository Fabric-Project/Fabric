//
//  ContentView.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Fabric

struct ContentView: View {

    struct ScrollGeomHelper : Equatable
    {
        let offset:CGPoint
        let geometry:ScrollGeometry
        
        static func == (lhs: ScrollGeomHelper, rhs: ScrollGeomHelper) -> Bool
        {
            lhs.offset == rhs.offset && lhs.geometry == rhs.geometry
        }
    }
    
    @Binding var document: FabricDocument

    @State private var magnifyBy = 1.0
    @State private var finalMagnification = 1.0
    @State private var magnifyAnchor: UnitPoint = .center
    @State private var scrollGeometry: ScrollGeometry = ScrollGeometry(contentOffset: .zero, contentSize: .zero, contentInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0), containerSize: .zero)

    @State private var hitTestEnable:Bool = true
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @State private var inspectorVisibility:Bool = false
    @State private var scrollOffset: CGPoint = .zero

    var body: some View {

        NavigationSplitView(columnVisibility: self.$columnVisibility)
        {
            NodeRegisitryView(graph: document.graph, scrollOffset: $scrollOffset)

        } detail: {

            // Movable Canvas
            VStack(alignment: .leading, spacing:0)
            {
                Divider()

                Spacer()

                HStack(spacing:5)
                {
                    Text("Root Patch")
                        .font(.headline)
                        .onTapGesture { self.document.graph.activeSubGraph = nil }

                    if let _ = self.document.graph.activeSubGraph
                    {
                        Text(">")
                            .font(.headline)

                        Text("Todo: Graphs Need Names")
                            .font(.headline)
                    }

                }
                .padding(.horizontal)

                Spacer()

                Divider()

                ZStack
                {
                    // Render behind nodes ?
                    // SatinMetalView(renderer: document.graphRenderer)

                    GeometryReader { geom in
                        RadialGradient(colors: [.clear, .black.opacity(0.75)], center: .center, startRadius: 0, endRadius: geom.size.width * 1.5)
                            .allowsHitTesting(false)
                    }

                    ScrollViewReader { proxy in
                        ScrollView([.horizontal, .vertical])
                        {
                            NodeCanvas()
                                .frame(width: 10000, height: 10000)
                                .environment(self.document.graph)
                                .scaleEffect(finalMagnification * magnifyBy, anchor: magnifyAnchor)
                                .gesture(
                                    MagnifyGesture()
                                        .onChanged { value in

                                            magnifyBy = min(max(value.magnification, 0.25), 4.0)
                                            
                                            // we need to unproject the value.startAnchor from a visible scroll rect, to scroll content rect
                                            let newX = remap(Float(value.startAnchor.x), 0, Float(self.scrollGeometry.contentSize.width), 0, Float(self.scrollGeometry.containerSize.width))
                                            let newY = remap(Float(value.startAnchor.y), 0, Float(self.scrollGeometry.contentSize.height), 0, Float(self.scrollGeometry.containerSize.height))

                                            magnifyAnchor = UnitPoint(x: CGFloat( newX + 0.5),
                                                                      y: CGFloat( newY + 0.5))
                                        }
                                        .onEnded { value in
                                            finalMagnification = min(max(finalMagnification * value.magnification, 0.25), 4.0)
                                            magnifyBy = 1.0
                                        }
                                )
                                .allowsHitTesting(self.hitTestEnable)
                                .id("canvas")
                                .onAppear {
                                    if let firstNode = self.document.graph.nodes.first {
                                        let targetPoint = UnitPoint(
                                            x: (5000 + firstNode.offset.width) / 10000,
                                            y: (5000 + firstNode.offset.height) / 10000
                                        )
                                        proxy.scrollTo("canvas", anchor: targetPoint)
                                    }
                                }
                        }
                        .defaultScrollAnchor(.center)
                    }
                    .onScrollGeometryChange(for: ScrollGeomHelper.self) { geometry in
                        
                        let center = CGPoint(x: geometry.contentSize.width / 2,
                                             y: geometry.contentSize.height / 2)
                        let offset = (geometry.contentOffset - center) + (geometry.containerSize / 2)
                        
                        return ScrollGeomHelper(offset: offset, geometry: geometry)
                        
                    } action: { _, newScrollOffset in
                        scrollGeometry = newScrollOffset.geometry
                        scrollOffset = newScrollOffset.offset
                    }
                    .onScrollPhaseChange { oldPhase, newPhase in
                        self.hitTestEnable = !newPhase.isScrolling
                    }

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
