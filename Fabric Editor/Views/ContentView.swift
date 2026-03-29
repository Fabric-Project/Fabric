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

    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @State private var inspectorVisibility:Bool = true
    @State private var inputFocus: FabricEditorInputFocus = .canvas

    init(document: Binding<FabricDocument>) {
        self._document = document
    }

    // Magic Numbers...
    private let zoomMin = 0.25
    private let zoomMax = 2.0
    private let canvasSize = 10000.0
    private let halfCanvasSize = 5000.0
    
    var body: some View {

        NavigationSplitView(columnVisibility: self.$columnVisibility)
        {
            NodeRegisitryView(editingContext: self.document.editingContext, inputFocus: self.$inputFocus)
                .navigationSplitViewColumnWidth(min: 150, ideal: 200, max:250)

        } detail: {
            VStack(alignment: .leading, spacing:0)
            {
                Divider()

                Spacer()

                HStack(spacing:5)
                {
                    Button("Root Graph", action: self.document.editingContext.popToRoot)
                        .font(.headline)
                        .buttonStyle(.plain)

                    ForEach(self.document.editingContext.entries) { node in
                        Text("›")
                            .font(.headline)
                        Button(node.name) { self.document.editingContext.popTo(node) }
                            .font(.headline)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Spacer()

                Divider()

                ZStack
                {
                    RadialGradient(colors: [.clear, .black.opacity(0.75)], center: .center, startRadius: 0, endRadius: self.scrollGeometry.containerSize.width * 1.5)

                    ScrollViewReader { proxy in
                        ScrollView([.horizontal, .vertical])
                        {
                            GraphCanvas(editingContext: self.document.editingContext, inputFocus: self.$inputFocus)
                                .id("canvas")
                                .focusedSceneValue(\.editorInputFocus, self.$inputFocus)
                                .frame(width: self.canvasSize, height: self.canvasSize)
                                .scaleEffect(finalMagnification * magnifyBy, anchor: magnifyAnchor)
                                .contextMenu(menuItems: {
                                    Button("New Note") {
                                        let currentGraph = self.document.editingContext.currentGraph
                                        let note = Note(note: "New Note", rect: CGRect(origin: self.document.editingContext.currentScrollOffset, size:CGSize(width: 500, height: 500)))
                                        currentGraph.addNote(note)
                                    }
                                })
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

                                            let scale = proposedScale

                                            let u = value.startAnchor.x
                                            let v = value.startAnchor.y

                                            let containerSize = self.scrollGeometry.containerSize
                                            let contentOffset = self.scrollGeometry.contentOffset

                                            let visibleWidthInCanvas  = containerSize.width  / scale
                                            let visibleHeightInCanvas = containerSize.height / scale

                                            let offsetXInCanvas = contentOffset.x / scale
                                            let offsetYInCanvas = contentOffset.y / scale

                                            let canvasX = offsetXInCanvas + u * visibleWidthInCanvas
                                            let canvasY = offsetYInCanvas + v * visibleHeightInCanvas

                                            let newX = max(0, min(1, canvasX / (self.canvasSize / scale)))
                                            let newY = max(0, min(1, canvasY / (self.canvasSize / scale)))

                                            magnifyAnchor = UnitPoint(x: newX, y: newY)
                                        })
                                        .onEnded { value in
                                            finalMagnification = min(max(finalMagnification * value.magnification, self.zoomMin), self.zoomMax)
                                        }
                                )
                                .onAppear {
                                    self.document.editingContext.rootGraph.undoManager = undoManager

                                    DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(10)) ) {
                                        if let firstNode = self.document.editingContext.rootGraph.nodes.first
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
                        self.document.editingContext.currentScrollOffset = newScrollOffset.offset
                    }
                }
            }
            .inspector(isPresented: self.$inspectorVisibility)
            {
                NodeSelectionInspector(editingContext: self.document.editingContext, inputFocus: self.$inputFocus)
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
