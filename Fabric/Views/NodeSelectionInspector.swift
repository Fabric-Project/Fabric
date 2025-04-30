//
//  NodeSelectionInspector.swift
//  Fabric
//
//  Created by Anton Marini on 4/29/25.
//

import SwiftUI
import Satin

struct NodeSelectionInspector: View {
    
    
    @SwiftUI.Environment(Graph.self) var graph:Graph

    var body: some View {
        
        let selectedNodes = self.graph.nodes.filter( { $0.isSelected } )
        
        
        List {
            
            ForEach(selectedNodes) { node in
            
                Section(header: Text( node.name ) )
                {
                    
                    ParameterGroupView(parameterGroup: node.parameterGroup)
//                    ForEach(node.parameterGroup.params, id: \.id) { param in
//                        
//                        Text("\(param.label)")
//                            .font( .system(size: 11) )
////
//                    }
                    
//                    ForEach(node.ports, id: \.id) { port in
//                        
//                        Text(port.name + ": " + port.valueType() )
//                            .font( .system(size: 11) )
//
//                    }
                }
                
            }
        }
        .listStyle(.sidebar)
        
    }
}

#Preview {
    NodeSelectionInspector()
}
