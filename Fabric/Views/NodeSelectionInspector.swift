//
//  NodeSelectionInspector.swift
//  Fabric
//
//  Created by Anton Marini on 4/29/25.
//

import SwiftUI

struct NodeSelectionInspector: View {
    
    
    @SwiftUI.Environment(Graph.self) var graph:Graph

    var body: some View {
        
        let selectedNodes = self.graph.nodes.filter( { $0.isSelected } )
        
        
        List {
            
            ForEach(selectedNodes) { node in
            
                Section(header: Text( node.name ) )
                {
                    ForEach(node.ports, id: \.id) { port in
                        
                        Text(port.name + ": " + port.valueType() )
                    }
                }
                
            }
        }
        
    }
}

#Preview {
    NodeSelectionInspector()
}
