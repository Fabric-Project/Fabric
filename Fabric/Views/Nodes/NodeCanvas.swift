//
//  NodeCanvas.swift
//  v
//
//  Created by Anton Marini on 5/26/24.
//

import SwiftUI



public struct NodeCanvas : View
{
    @Environment(Graph.self) var graph:Graph

//    @State var activityMonitor = NodeCanvasUserActivityMonitor()
    
    // Drag to Offset bullshit
    @State private var initialOffsets: [UUID: CGSize] = [:]
    @State private var activeDragAnchor: UUID? = nil       // which node started the drag

//    @Binding currentFraph
    
    public init() { }
    
    public var body: some View
    {
        GeometryReader { geom in
            
            ZStack
            {
                // image size is 225
                Image("background")
                    .resizable(resizingMode: .tile)// Need this pattern image repeated throughout the page
                    .offset(-geom.size / 2)
                
                let graph = self.graph.activeSubGraph ?? self.graph
                ForEach(graph.nodes, id: \.id) { currentNode in
                    
                    NodeView(node: currentNode , offset: currentNode.offset)
                        .offset( currentNode.offset )
                        .highPriorityGesture(
                            TapGesture(count: 1)
                                .modifiers(.shift)
                                .onEnded {
                                    // Expand selection
                                    graph.selectNode(node: currentNode, expandSelection: true)
                                }, // fires when Shift is held
                        )
                        .gesture(
                            SimultaneousGesture(
                                DragGesture(minimumDistance: 3)
                                
                                    .onChanged { value in
                                        
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
                                    .onEnded { _ in
                                        // End drag
                                        graph.nodes.filter { $0.isSelected }.forEach { $0.isDragging = false }
                                        self.activeDragAnchor = nil
                                        self.initialOffsets.removeAll()
                                    },
                                
                                
                                TapGesture(count: 1)
                                    .onEnded {
                                        // Replace selection
                                        graph.deselectAllNodes()
                                        currentNode.isSelected.toggle()
                                    }
                                
                            )
                            
                        )
                    
                }
            }
            .offset(geom.size / 2)
            .clipShape(Rectangle())
            .contentShape(Rectangle())
            .coordinateSpace(name: "graph")    // make sure all anchors share this space
            .overlayPreferenceValue(PortAnchorKey.self) { portAnchors in
                
                let graph = self.graph.activeSubGraph ?? self.graph

                let ports = graph.nodes.flatMap(\.ports)
                
                ForEach( ports.filter({ $0.kind == .Outlet }), id: \.id) { port in
                    
                    let connectedPorts:[any NodePortProtocol] = port.connections.filter({ $0.kind == .Inlet })
                    
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
//                                connectedPort.disconnect(from:port)
                                port.disconnect(from:connectedPort)
                                graph.shouldUpdateConnections.toggle()
                            }
                        }
                    }
                }
            }
            .focusable(true, interactions: .edit)
            .focusEffectDisabled()
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
    
    private func calcPathUsing(port:(any NodePortProtocol), start:CGPoint, end:CGPoint) -> Path
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
