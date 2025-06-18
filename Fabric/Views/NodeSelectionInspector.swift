//
//  NodeSelectionInspector.swift
//  Fabric
//
//  Created by Anton Marini on 4/29/25.
//

import SwiftUI
import Satin

public struct NodeSelectionInspector: View {
    
    @SwiftUI.Environment(Graph.self) var graph:Graph

    public init() { }

    public var body: some View {
        
        let selectedNodes = self.graph.nodes.filter( { $0.isSelected } )
        
        List {
            
            ForEach(selectedNodes) { node in
            
                Section(header: Text( node.name ) )
                {
                    ParameterGroupView(parameterGroup: node.parameterGroup)
                }
            }
        }
        .listStyle(.sidebar)
        
    }
}

#Preview {
    NodeSelectionInspector()
}
