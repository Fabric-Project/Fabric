//
//  NodeCanvas.swift
//  v
//
//  Created by Anton Marini on 5/26/24.
//

import SwiftUI



struct NodeCanvas : View
{    
    @SwiftUI.Environment(Graph.self) var graph:Graph

    @State var activityMonitor = NodeCanvasUserActivityMonitor()
    
    // Drag to Offset bullshit
    @State private var offset:CGSize = CGSize(width: 50, height: 50) // CGSize(width: 50, height: SourceGrid.sourceGridHeight + 45)
    @GestureState private var dragOffset: CGSize = .zero
    
    @State private var needsRedraw:Bool = false

    var body: some View
    {
        // Movable Canvas
        GeometryReader { geom in

            ZStack
            {
                // Nodes
                ForEach(self.graph.nodes) { currentNode in
                    
                    NodeView(node: currentNode, offset: currentNode.offset)
                    
                }
            }
            .offset(geom.size / 2)
            .clipShape(Rectangle())
            .contentShape(Rectangle())
            .coordinateSpace(name: "graph")    // make sure all anchors share this space
            .overlayPreferenceValue(PortAnchorKey.self) { portAnchors in

                let ports = self.graph.nodes.flatMap(\.ports)
                                
                ForEach( ports.filter({ $0.kind == .Outlet }), id: \.id) { port in
                    
                    let connectedPorts:[any NodePortProtocol] = port.connections.filter({ $0.kind == .Inlet })
                    
                    ForEach( connectedPorts , id: \.id) { connectedPort in
                        
                        if let sourceAnchor = portAnchors[port.id],
                           let destAnchor = portAnchors[connectedPort.id]
                        {
                            let start = geom[ sourceAnchor ]
                            let end = geom[ destAnchor ]

                            self.calcPathUsing(port:port, start: start, end: end)
                                .stroke(port.backgroundColor , lineWidth: 2)
                                .contentShape(
                                    self.calcPathUsing(port:port, start: start, end: end)
                                        .stroke(style: StrokeStyle(lineWidth: 5))
                                )
                                .onTapGesture(count: 2)
                                {
                                    connectedPort.discconnect(from:port)
                                    port.discconnect(from:connectedPort)
                                    self.needsRedraw.toggle()
                                }
                        }
                    }
                }
            }
            .focusable(true, interactions: .edit)
            .focusEffectDisabled()
            .onDeleteCommand {
                
                let selectedNodes = self.graph.nodes.filter({ $0.isSelected })
                selectedNodes.forEach( { self.graph.delete(node: $0) } )
            }
            .onTapGesture {
                self.graph.deselectAllNodes()
            }
            .opacity(self.activityMonitor.isActive ? 1.0 : 0.0)
                           .animation(.easeInOut(duration: 0.5), value: self.activityMonitor.isActive)

        } // Pan Canvas
    }
    
    private func calcPathUsing(port:(any NodePortProtocol), start:CGPoint, end:CGPoint) -> Path
    {
        // Min 5 stem height
        let stemHeight:CGFloat = self.clamp( abs( end.y - start.y) / 4.0 , lowerBound: 5.0, upperBound: 35.0)
        let stemOffset:CGFloat =  self.clamp( self.dist(p1: start, p2:end) / 4.0, lowerBound: 5.0, upperBound: 35.0) /*min( max(5, self.dist(p1: start, p2:end)), 40 )*/

        switch port.direction
        {
        case .Vertical:
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
            let start1:CGPoint = CGPoint(x: start.x + stemHeight,
                                         y: start.y)
            
            let end1:CGPoint = CGPoint(x: end.x - stemHeight,
                                       y: end.y)
            
            let controlOffset:CGFloat = max(stemHeight + stemOffset, abs(end1.y - start1.y) / 2.4)
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
