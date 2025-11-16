//
//  ContentView.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Fabric

struct ScrollGeometry: Equatable {
    let offset: CGPoint
    let containerSize: CGSize
}

struct ContentView: View {
    
    @Binding var document: FabricDocument
    
    @GestureState private var magnifyBy = 1.0
    
    @State private var finalMagnification = 1.0

    @State private var hitTestEnable:Bool = true
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @State private var inspectorVisibility:Bool = false
    @State private var contentOffset: CGPoint = .zero
    @State private var scrollOffset: CGPoint = .zero
    @State private var zoomAnchor: UnitPoint = .center
    @State private var hoverLocation: CGPoint = .zero
    @State private var isMagnifying = false
    
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
                                .scaleEffect(finalMagnification * magnifyBy, anchor: zoomAnchor)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            if !isMagnifying {
                                                isMagnifying = true
                                                let canvasX = 1.0 - ((contentOffset.x + hoverLocation.x) / 10000)
                                                let canvasY = (contentOffset.y + hoverLocation.y) / 10000
                                                zoomAnchor = UnitPoint(x: canvasX.clamped(to: 0...1), y: canvasY.clamped(to: 0...1))
                                            }
                                        }
                                        .updating($magnifyBy) { value, gestureState, _ in
                                            gestureState = value
                                        }
                                        .onEnded { value in
                                            finalMagnification *= value
                                            finalMagnification = min(max(finalMagnification, 0.25), 4.0)
                                            isMagnifying = false
                                        }
                                )
                                .environment(self.document.graph)
                                .allowsHitTesting(self.hitTestEnable)
                                .id("canvas")
                                .task {
                                    try? await Task.sleep(for: .milliseconds(100))
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
                        .onContinuousHover { phase in
                            if case .active(let location) = phase {
                                hoverLocation = location
                            }
                        }
                    }
                    .onScrollGeometryChange(for: ScrollGeometry.self) { geometry in
                        return ScrollGeometry(offset: geometry.contentOffset, containerSize: geometry.containerSize)
                    } action: { _, new in
                        contentOffset = new.offset
                        let center = CGPoint(x: 5000, y: 5000)
                        scrollOffset = (new.offset - center) + (new.containerSize / 2)
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

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
