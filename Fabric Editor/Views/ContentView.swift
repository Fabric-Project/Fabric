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
    @Environment(\.undoManager) private var undoManager

    @GestureState private var magnifyBy = 1.0
    @State private var finalMagnification = 1.0
    @State private var magnifyAnchor: UnitPoint = .center
    @State private var scrollGeometry: ScrollGeometry = ScrollGeometry(contentOffset: .zero, contentSize: .zero, contentInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0), containerSize: .zero)

    @State private var hitTestEnable:Bool = true
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @State private var inspectorVisibility:Bool = true
    @State private var scrollOffset: CGPoint = .zero

    // Magic Numbers...
    private let zoomMin = 0.25
    private let zoomMax = 2.0
    private let canvasSize = 10000.0
    private let halfCanvasSize = 5000.0
    
    var body: some View {

        NavigationSplitView(columnVisibility: self.$columnVisibility)
        {
            NodeRegisitryView(graph: document.graph, scrollOffset: $scrollOffset)
                .navigationSplitViewColumnWidth(min: 150, ideal: 200, max:250)

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
                                .frame(width: self.canvasSize, height: self.canvasSize)
                                .environment(self.document.graph)
                                .scaleEffect(finalMagnification * magnifyBy, anchor: magnifyAnchor)
                                .gesture(
                                    MagnifyGesture()
                                        .updating($magnifyBy, body: { value, state, _ in
                                            
                                            let proposedScale = finalMagnification * value.magnification
                                            
                                            guard (self.zoomMin ..< self.zoomMax).contains(proposedScale)
                                            else
                                            {
                                                return
                                            }
                                            
                                            state = min(max(value.magnification, self.zoomMin), self.zoomMax)
                                            
                                            let scale = proposedScale   // or finalMagnification * state
                                            
                                            // 0–1 in visible rect
                                            let u = value.startAnchor.x
                                            let v = value.startAnchor.y
                                            
                                            let containerSize = self.scrollGeometry.containerSize
                                            let contentOffset = self.scrollGeometry.contentOffset
                                            
                                            // Convert scroll geometry into *canvas space* by dividing by scale
                                            let visibleWidthInCanvas  = containerSize.width  / scale
                                            let visibleHeightInCanvas = containerSize.height / scale
                                            
                                            let offsetXInCanvas = contentOffset.x / scale
                                            let offsetYInCanvas = contentOffset.y / scale
                                            
                                            // Point under the fingers in canvas coords
                                            let canvasX = offsetXInCanvas + u * visibleWidthInCanvas
                                            let canvasY = offsetYInCanvas + v * visibleHeightInCanvas
                                            
                                            // Normalize to 0–1 over the full scaled canvas
                                            let newX = max(0, min(1, canvasX / (self.canvasSize / scale)))
                                            let newY = max(0, min(1, canvasY / (self.canvasSize / scale)))
                                            
                                            magnifyAnchor = UnitPoint(x: newX, y: newY)
                                        })
                                        .onEnded { value in
                                            finalMagnification = min(max(finalMagnification * value.magnification, self.zoomMin), self.zoomMax)
                                        }
                                )
                                .allowsHitTesting(self.hitTestEnable)
                                .id("canvas")
                                .onAppear {
                                    self.document.graph.undoManager = undoManager

                                    // This is hacky as hell, but it seems our scroll offset doesn work since on can fire before other views are fully online?
                                    // Or at least whatever is happening is fixed by this logic
                                    // Fixes #100
                                    DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(10)) ) {
                                        
                                        if let firstNode = self.document.graph.nodes.first
                                        {
                                            let targetPoint = UnitPoint( x: (self.halfCanvasSize + firstNode.offset.width) / self.canvasSize,
                                                                         y: (self.halfCanvasSize + firstNode.offset.height) / self.canvasSize)
                                            proxy.scrollTo("canvas", anchor: targetPoint)
                                        }
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
                    .inspectorColumnWidth(min:250, ideal:250, max:300)
            }
            .toolbar
            {
                ToolbarItem(placement: .automatic)
                {
                    Button("Parameters", systemImage: "sidebar.right") {
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
