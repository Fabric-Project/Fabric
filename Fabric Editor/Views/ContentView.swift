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
    @State private var inspectorVisibility:Bool = false
    @State private var scrollOffset: CGPoint = .zero
    @State private var scrollProxy: ScrollViewProxy? = nil

    // Magic Numbers...
    private let zoomMin = 0.25
    private let zoomMax = 2.0
    private let canvasSize = 10000.0
    private let halfCanvasSize = 5000.0
    
    var body: some View {

        NavigationSplitView(columnVisibility: self.$columnVisibility)
        {
            NodeRegisitryView(
                graph: document.graph, 
                scrollOffset: $scrollOffset,
                scrollGeometry: $scrollGeometry,
                onScrollToPosition: { position in
                    self.scrollToPosition(position)
                }
            )

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
                                    // Capture scroll proxy for programmatic scrolling
                                    self.scrollProxy = proxy
                                    
                                    // Initialize undo manager
                                    self.document.graph.undoManager = undoManager
                                    
                                    // Scroll to first node if exists
                                    if let firstNode = self.document.graph.nodes.first
                                    {
                                        let targetPoint = UnitPoint( x: (self.halfCanvasSize + firstNode.offset.width) / self.canvasSize,
                                                                     y: (self.halfCanvasSize + firstNode.offset.height) / self.canvasSize)
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
                    Button("Parameters", systemImage: "sidebar.right") {
                        self.inspectorVisibility.toggle()
                    }
                }

            }
            .focusedValue(\.centerOnSelectedNode, self.centerOnSelectedNode)
        }
    }
    
    // MARK: - Scroll to Position
    
    /// Scrolls the canvas to make the given position visible
    private func scrollToPosition(_ position: CGPoint)
    {
        guard let proxy = scrollProxy else {
            print("ScrollViewProxy not available")
            return
        }
        
        // Convert canvas coordinates (centered at 0,0) to UnitPoint (0-1 range)
        // Canvas is 10000x10000 with origin at center (-5000 to +5000)
        let normalizedX = (self.halfCanvasSize + position.x) / self.canvasSize
        let normalizedY = (self.halfCanvasSize + position.y) / self.canvasSize
        
        // Clamp to valid range
        let clampedX = max(0, min(1, normalizedX))
        let clampedY = max(0, min(1, normalizedY))
        
        let targetPoint = UnitPoint(x: clampedX, y: clampedY)
        
        print("Scrolling to position: \(position) -> UnitPoint(\(clampedX), \(clampedY))")
        
        // Immediately update scrollOffset to the target position to prevent race condition
        // where rapid node additions use stale scroll position before animation completes
        scrollOffset = position
        
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("canvas", anchor: targetPoint)
        }
    }
    
    // MARK: - Menu Actions
    
    /// Centers the view on the currently selected node
    private func centerOnSelectedNode()
    {
        let graph = self.document.graph.activeSubGraph ?? self.document.graph
        
        // Find the first selected node
        guard let selectedNode = graph.nodes.first(where: { $0.isSelected }) else {
            print("No node selected")
            return
        }
        
        print("Centering on selected node: \(selectedNode.name) at \(selectedNode.anchorPoint)")
        
        // Use the existing scroll-to implementation
        scrollToPosition(selectedNode.anchorPoint)
    }
}

#Preview {
    ContentView(document: .constant(FabricDocument()))
}
