//
//  NodeView.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Satin

struct NodeView : View
{
    @SwiftUI.Environment(Graph.self) var graph:Graph
    
    let node:Node
    
    // Drag to Offset bullshit
    @State var offset = CGSize.zero
    @GestureState private var dragOffset: CGSize = .zero
    
    var body: some View
    {
        GeometryReader { geom in
            
//            let nodeClass = self.node 
            
            // Param List
            ZStack(alignment: .topLeading)
            {
                
                Color( (self.node.isSelected) ? "NodeBackgroundColorSelected" : "NodeBackgroundColor")
                                
                Rectangle()
                    .fill( (self.node.isSelected) ? self.node.nodeType.color().gradient : self.node.nodeType.backgroundColor().gradient )
                    .frame(height: 30)
            
                VStack(alignment: .leading, spacing: 10) {
                    
                    // Name
                    Text( self.node.name )
                        .font(.system(size: 9))
                        .bold()
                        .frame(maxHeight: 20)
                        .padding(.top, 5)
                        .padding(.horizontal, 20)
                    
//                    Spacer()
                    
                    ForEach(self.node.ports.filter({$0.kind == .Inlet && $0.direction == .Horizontal}), id: \.id) { port in
                        NodeInletView(port: port)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: self.node.nodeSize.width + NodeInletView.radius, alignment: .leading)
                
                
                VStack(alignment: .trailing, spacing: 10) {
                    Spacer(minLength: 0)
                        .frame(height: 25)
                    
                    ForEach(self.node.ports.filter({$0.kind == .Outlet && $0.direction == .Horizontal}), id: \.id) { port in
                        NodeOutletView(port: port)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: self.node.nodeSize.width + NodeInletView.radius, alignment: .trailing)
                
                
            }
            .frame(width: self.node.nodeSize.width, height: self.node.nodeSize.height)
            .cornerRadius(self.cornerRadius())
            .overlay {
                RoundedRectangle(cornerRadius: self.cornerRadius())
                    .stroke( .gray, lineWidth: 1.0)
            }
            .contextMenu
            {
                ForEach(self.node.ports, id:\.id) { port in
                
                    Button {
                        
                        port.published = !port.published
                        
                        // Hacky!
                        self.graph.rebuildPublishedParameterGroup()
                        
                    } label: {
                        Text( port.published ?  "Unpublish Port: \(port.name)" : "Publish Port: \(port.name)" )
                    }
                    
                }
            }
            .onTapGesture(count: 2)
            {
                if let subgraph = self.node as? SubgraphNode {
                    self.graph.activeSubGraph = subgraph.graph
                }
            }
        }
    }
    
    func cornerRadius() -> CGFloat {
        switch self.node.nodeType {
        case .Subgraph:
            return 5.0
        default:
            return 15.0
        }
    }
}
    
