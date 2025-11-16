//
//  ContentView.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Fabric

struct ContentView: View {

    @Binding var document: FabricDocument
    @Environment(\.undoManager) private var undoManager

    @State private var magnifyBy = 1.0
    @State private var finalMagnification = 1.0
    @State private var viewportAnchor: UnitPoint = .center

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
                                .scaleEffect(finalMagnification * magnifyBy, anchor: viewportAnchor)
                                .gesture(
                                    MagnifyGesture()
                                        .onChanged { value in
                                            magnifyBy = value.magnification
                                        }
                                        .onEnded { value in
                                            finalMagnification *= value.magnification
                                            finalMagnification = min(max(finalMagnification, 0.25), 4.0)
                                            magnifyBy = 1.0
                                        }
                                )
                                .allowsHitTesting(self.hitTestEnable)
                                .id("canvas")
                                .task {
                                    self.document.graph.undoManager = undoManager
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
                    }
                    .onScrollGeometryChange(for: CGPoint.self) { geometry in
                        let center = CGPoint(x: geometry.contentSize.width / 2,
                                             y: geometry.contentSize.height / 2)
                        let offset = (geometry.contentOffset - center) + (geometry.containerSize / 2)
                        let viewportCenter = offset + CGPoint(x: 5000, y: 5000)
                        viewportAnchor = UnitPoint(x: viewportCenter.x / 10000, y: viewportCenter.y / 10000)
                        return offset
                    } action: { _, newScrollOffset in
                        scrollOffset = newScrollOffset
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
