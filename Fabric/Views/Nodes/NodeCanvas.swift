//
//  NodeCanvas.swift
//  v
//
//  Created by Anton Marini on 5/26/24.
//

import SwiftUI


//public struct NodeRenameView
//{
//    @Environment(\.dismiss) var dismiss // For programmatic dismissal
//
//    let node:Node
//    
//    var body: some View {
//            VStack {
//                TextField("Node Name", text: self.$node.name)
//                Button("Save") {
//                    dismiss() // Dismiss the modal
//                }
//            }
//        }
//}


public struct NodeCanvas : View
{
    @Environment(Graph.self) var graph:Graph
    
    public init() { }
    
//    @State var activityMonitor = NodeCanvasUserActivityMonitor()
    
    // Drag to Offset bullshit
    @State private var initialOffsets: [UUID: CGSize] = [:]
    @State private var activeDragAnchor: UUID? = nil       // which node started the drag

    @State private var portPositions: [UUID: CGPoint] = [:]

    public var body: some View
    {
        GeometryReader { geom in

            ZStack
            {
                // image size is 255
                Image("background")
                    .resizable(resizingMode: .tile)// Need this pattern image repeated throughout the page
                    .offset(-geom.size / 2)
                
                let graph = self.graph.activeSubGraph ?? self.graph
                
                ForEach(graph.notes, id:\.id) { currentNote in
                        
                    NoteView(note: currentNote)
                        .offset(-geom.size / 2)
                        .offset(x: currentNote.rect.origin.x, y: currentNote.rect.origin.y )
                        .contextMenu {
                            Button("Delete Note") {
                                graph.deleteNote(currentNote)
                            }
                        }
                }
                
                
                ForEach(graph.nodes, id: \.id) { currentNode in

                    NodeView(node: currentNode , offset: currentNode.offset)
                        .offset( currentNode.offset )
                        .highPriorityGesture(
                            TapGesture(count: 1)
                                .modifiers(.shift)
                                .onEnded {
                                    // Expand selection
                                    currentNode.isSelected.toggle()
                                },
                        )
                        .gesture(
                            SimultaneousGesture(
                                DragGesture(minimumDistance: 3)
                                    .onChanged { value in
                                        
                                        self.calcDragChanged(forValue: value, activeGraph: graph, currentNode: currentNode)
                                    }
                                    .onEnded { _ in

                                        self.calcDragEnded()
                                    },
                                
                                SimultaneousGesture(
                                    
                                    TapGesture(count: 1)
                                        .onEnded {
                                            // Replace selection
                                            graph.deselectAllNodes()
                                            currentNode.isSelected.toggle()
                                        },
                                    TapGesture(count: 2)
                                        .onEnded
                                    {
                                        if let subgraph = currentNode as? SubgraphNode
                                        {
                                            self.graph.activeSubGraph = subgraph.subGraph
                                        }
                                    }
                                )
                            )
                        )
                        .contextMenu
                        {
                            self.contextMenu(forNode: currentNode, graph: graph)
                        }
                }
            }
            .offset(geom.size / 2)
            .clipShape(Rectangle())
            .contentShape(Rectangle())
            .coordinateSpace(name: "graph")
            .onPreferenceChange(PortAnchorKey.self) { portAnchors in
                self.calcPortAnchors(portAnchors, geometryProxy: geom)
            }
            .overlayPreferenceValue(PortAnchorKey.self) { portAnchors in
                self.calcOverlayPaths(portAnchors, geometryProxy: geom)
            }
            .focusable(true, interactions: .edit)
            .focusEffectDisabled()
            .onKeyPress(keys: self.keys() ) { keyPress in
                return self.handleKeyPress(keyPress:keyPress)
            }
            .onDeleteCommand {
                
                let graph = self.graph.activeSubGraph ?? self.graph

                let selectedNodes = graph.nodes.filter({ $0.isSelected })
                selectedNodes.forEach( { graph.delete(node: $0) } )
            }
            .onTapGesture {
                let graph = self.graph.activeSubGraph ?? self.graph

                graph.deselectAllNodes()
            }
           
            
            .id(self.graph.activeSubGraph?.shouldUpdateConnections ?? self.graph.shouldUpdateConnections)
            // For hiding the nodes after a timeout - used if rendering nodes above content?
//            .opacity(self.activityMonitor.isActive ? 1.0 : 0.0)
//                           .animation(.easeInOut(duration: 0.5), value: self.activityMonitor.isActive)
            
        } // Pan Canvas
    }
    
    private func calcDragChanged(forValue value:DragGesture.Value, activeGraph graph:Graph, currentNode:Node)
    {
        // If this drag just began, capture snapshots
        if self.activeDragAnchor == nil
        {
            self.activeDragAnchor = currentNode.id
            
            // If the anchor isn't selected, select only it (or expand if you prefer)
            if !currentNode.isSelected
            {
                graph.selectNode(node: currentNode, expandSelection: false)
            }
            
            // Snapshot current offsets for all selected nodes
            self.initialOffsets = Dictionary(uniqueKeysWithValues:graph.nodes
                .filter { $0.isSelected }
                .map { ($0.id, $0.offset) }
            )
            
            // Mark dragging (optional)
            graph.nodes.filter { $0.isSelected }.forEach { $0.isDragging = true }
        }
        
        let t = value.translation
        // Apply translation relative to snapshot
        graph.nodes.filter { $0.isSelected }.forEach { n in
            if let base = initialOffsets[n.id] {
                n.offset = base + t
            }
        }
    }
    
    private func handleKeyPress(keyPress:KeyPress) -> KeyPress.Result
    {
        switch keyPress.key
        {
        case .upArrow:
            print("up arrow")
            self.graph.selectNextNode(inDirection: .Up, expandSelection: keyPress.modifiers.contains(.shift))
            
        case .downArrow:
            print("down arrow")
            self.graph.selectNextNode(inDirection: .Down, expandSelection: keyPress.modifiers.contains(.shift))
            
        case .leftArrow:
            print("left arrow")
            self.graph.selectNextNode(inDirection: .Left, expandSelection: keyPress.modifiers.contains(.shift))
            
        case .rightArrow:
            print("right arrow")
            self.graph.selectNextNode(inDirection: .Right, expandSelection: keyPress.modifiers.contains(.shift))

        case .escape:
            self.graph.deselectAllNodes()

        case .deleteForward:
            let graph = self.graph.activeSubGraph ?? self.graph
            let selectedNodes = graph.nodes.filter({ $0.isSelected })
            selectedNodes.forEach( { graph.delete(node: $0) } )
            
        default:
            return .ignored
        }
        
        return .handled
    }
    
    private func calcDragEnded()
    {
        let selectedNodes = graph.nodes.filter { $0.isSelected }
        
        self.graph.undoManager?.beginUndoGrouping()
        
        for node in selectedNodes
        {
            if let offset = initialOffsets[node.id]
            {
                self.graph.undoManager?.registerUndo(withTarget: node) {
                    
                    let cachedOffset = $0.offset
                    
                    // This registers a redo - as an undo
                    // https://nilcoalescing.com/blog/HandlingUndoAndRedoInSwiftUI/
                    self.graph.undoManager?.registerUndo(withTarget: node) { $0.offset = cachedOffset
                    }

                    $0.offset = offset
                }
            }
        }
        
        self.graph.undoManager?.endUndoGrouping()
        
        self.graph.undoManager?.setActionName("Move Nodes")
        
        selectedNodes.forEach { $0.isDragging = false }
        self.activeDragAnchor = nil

        self.initialOffsets.removeAll()
    }
    
    private func calcPortAnchors(_ portAnchors:(PortAnchorKey.Value), geometryProxy geom:GeometryProxy)
    {
        var positions: [UUID: CGPoint] = [:]
        for (portID, anchor) in portAnchors {
            positions[portID] = geom[anchor]
        }
        self.portPositions = positions
        self.graph.portPositions = positions
    }
    
    @ViewBuilder private func calcOverlayPaths(_ portAnchors:(PortAnchorKey.Value), geometryProxy geom:GeometryProxy) -> some View
    {
        let graph = self.graph.activeSubGraph ?? self.graph

        let ports = graph.nodes.flatMap(\.ports)

        ForEach( ports.filter({ $0.kind == .Outlet }), id: \.id) { port in
            
            let connectedPorts:[Port] = port.connections.filter({ $0.kind == .Inlet })
            
            ForEach( connectedPorts , id: \.id) { connectedPort in
                
                if let sourceAnchor = portAnchors[port.id],
                   let destAnchor = portAnchors[connectedPort.id]
                {
                    let start = geom[ sourceAnchor ]
                    let end = geom[ destAnchor ]
                    
                    let path = self.calcPathUsing(port:port, start: start, end: end)
                    
                    path.stroke(port.backgroundColor , lineWidth: 2)
                        .contentShape(
                            path.stroke(style: StrokeStyle(lineWidth: 5))
                        )
                        .onTapGesture(count: 2)
                    {
                        port.disconnect(from:connectedPort)
                        graph.shouldUpdateConnections.toggle()
                    }
                }
            }
        }
        
        if let sourcePortID = graph.dragPreviewSourcePortID,
           let targetPosition = graph.dragPreviewTargetPosition,
           let sourceAnchor = portAnchors[sourcePortID],
           let sourcePort = graph.nodePort(forID: sourcePortID)
        {
            let start = geom[ sourceAnchor ]
            let path = self.calcPathUsing(port: sourcePort, start: start, end: targetPosition)
            
            path.stroke(sourcePort.backgroundColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targetPosition)
        }
    }
    
    @ViewBuilder private func contextMenu(forNode currentNode:Node, graph:Graph) -> some View
    {
            Menu("Selection")
            {
                Button {
                    graph.selectAllNodes()
                } label : {
                    Text("Select All Nodes")
                }
                
                Button {
                    graph.deselectAllNodes()
                    graph.selectUpstreamNodes(fromNode: currentNode)
                    
                } label : {
                    Text("Select All Upstream Nodes")
                }
                
                Button {
                    graph.deselectAllNodes()
                    graph.selectDownstreamNodes(fromNode: currentNode)
                    
                } label : {
                    Text("Select All Downstream Nodes")
                }
                
                Menu("Embed Selection In...") {
                    
                    let embedClasses = [SubgraphNode.self, IteratorNode.self, EnvironmentNode.self, DeferredSubgraphNode.self]
                    
                    ForEach (0 ..< embedClasses.count, id:\.self) { embedClassIndex in
                        let embedClass = embedClasses[embedClassIndex]
                        Button {
                            graph.createSubgraphFromSelection(centeredOnNode: currentNode, usingClass: embedClass)
                            
                        } label : {
                            Text(embedClass.name)
                        }
                    }
                }
            }
            
            
            Menu("Input Ports") {
                let inputPorts = currentNode.ports.filter { $0.kind == .Inlet }
                ForEach(inputPorts, id:\.id) { port in
                    
                    Button
                    {
                        port.published = !port.published
                        
                        // Hacky!
                        graph.rebuildPublishedParameterGroup()
                        
                    } label: {
                        Text( port.published ?  "Unpublish Port: \(port.name)" : "Publish Port: \(port.name)" )
                    }
                }
            }
            
            Menu("Output Ports") {
                let outputPorts = currentNode.ports.filter { $0.kind == .Outlet }
                
                ForEach(outputPorts, id:\.id) { port in
                    
                    Button {
                        
                        port.published = !port.published
                        
                        // Hacky!
                        graph.rebuildPublishedParameterGroup()
                        
                    } label: {
                        Text( port.published ?  "Unpublish Port: \(port.name)" : "Publish Port: \(port.name)" )
                    }
                    
                }
            }
    }
    
    private func calcPathUsing(port:Port, start:CGPoint, end:CGPoint) -> Path
    {
        let lowerBound = 5.0
        let upperBound = 10.0
        
        // Min 5 stem height
        let stemOffset:CGFloat =  self.clamp( self.dist(p1: start, p2:end) / 4.0, lowerBound: lowerBound, upperBound: upperBound) /*min( max(5, self.dist(p1: start, p2:end)), 40 )*/

        switch port.direction
        {
        case .Vertical:
            let stemHeight:CGFloat = self.clamp( abs( end.y - start.y) / 4.0 , lowerBound: lowerBound, upperBound: upperBound)

            let start1:CGPoint = CGPoint(x: start.x,
                                         y: start.y + stemHeight)
            
            let end1:CGPoint = CGPoint(x: end.x,
                                       y: end.y - stemHeight)
            
            let controlOffset:CGFloat = max(stemHeight + stemOffset, abs(end1.y - start1.y) / 2.4)
            let control1 = CGPoint(x: start1.x, y: start1.y + controlOffset )
            let control2 = CGPoint(x: end1.x, y:end1.y - controlOffset  )
            
            return Path { path in
                
                path.move(to: start )
                path.addLine(to: start1)
                
                path.addCurve(to: end1, control1: control1, control2: control2)
                
                path.addLine(to: end)
            }
            
        case .Horizontal:
            let stemHeight:CGFloat = self.clamp( abs( end.x - start.x) / 4.0 , lowerBound: lowerBound, upperBound: upperBound)

            let start1:CGPoint = CGPoint(x: start.x + stemHeight,
                                         y: start.y)

            let end1:CGPoint = CGPoint(x: end.x - stemHeight,
                                       y: end.y)

            let controlOffset:CGFloat = max(stemHeight + stemOffset, abs(end1.x - start1.x) / 2.4)
            let control1 = CGPoint(x: start1.x + controlOffset, y: start1.y  )
            let control2 = CGPoint(x: end1.x - controlOffset, y:end1.y   )
            
            return Path { path in
                
                path.move(to: start )
                path.addLine(to: start1)
                
                path.addCurve(to: end1, control1: control1, control2: control2)
                
                path.addLine(to: end)
            }
        }
    }
    
    private func clamp(_ x:CGFloat, lowerBound:CGFloat, upperBound:CGFloat) -> CGFloat
    {
        return max(min(x, upperBound), lowerBound)
    }
    
    private func dist(p1:CGPoint, p2:CGPoint) -> CGFloat
    {
        let distance = hypot(p1.x - p2.x, p1.y - p2.y)
        return distance
    }
    
    private func keys() -> Set<KeyEquivalent>
    {
//        if self.focusedView == .canvas
//        {
            return [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .space, .escape, .deleteForward]
//        }
//        
//        return []
    }
}
