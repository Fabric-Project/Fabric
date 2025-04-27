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

    // Drag to Offset bullshit
    @State private var offset:CGSize = CGSize(width: 50, height: 50) // CGSize(width: 50, height: SourceGrid.sourceGridHeight + 45)
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View
    {
        // Movable Canvas
        GeometryReader { geom in
            
//            let width = geom.size
                        
            ZStack
            {
                //                    // image size is 225
                //                Image("background")
                //                    .resizable(resizingMode: .tile)// Need this pattern image repeated throughout the page
                //                    .frame(maxWidth:.infinity, maxHeight:.infinity)
                
               
                
                // Nodes
                ForEach(self.graph.nodes) { currentNode in
                    
                    NodeView(node: currentNode, offset: currentNode.offset)
                    
                }
               

            }
            .offset(geom.size / 2)
            .coordinateSpace(name: "graph")    // make sure all anchors share this space
            .backgroundPreferenceValue(PortAnchorKey.self) { portAnchors in
                
                let ports = self.graph.nodes.flatMap(\.ports)
                
                ForEach( ports, id: \.id) { port in
                    
                    ForEach(port.connections, id: \.id) { connectedPort in
                        
                        if let sourceAnchor = portAnchors[port.id],
                           let destAnchor = portAnchors[connectedPort.id]
                        {
                            let sourcePoint = geom[ sourceAnchor ]

                            let destPoint = geom[ destAnchor ]

                            Path { path in
                                path.move(to: sourcePoint)
                                path.addLine(to: destPoint)
                            }
                            .stroke(Color.blue, lineWidth: 2)

                        }
                        
                    }
                    
                }
            }
               
                
    
                
            } // Pan Canvas
            

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
