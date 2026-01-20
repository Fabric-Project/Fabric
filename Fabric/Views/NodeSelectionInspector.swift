//
//  NodeSelectionInspector.swift
//  Fabric
//
//  Created by Anton Marini on 4/29/25.
//

import SwiftUI
import Satin

public struct NodeSelectionInspector: View
{
    let graph:Graph
    
    public init(graph:Graph)
    {
        self.graph = graph
    }
    
    public var body: some View {
        
        let graph = self.graph.activeSubGraph ?? self.graph
        
        let selectedNodes = graph.nodes.filter( { $0.isSelected } )
        
        List {
            
            Section(header: Text("Published"))
            {
                ParameterGroupView(parameterGroup:graph.publishedParameterGroup)
            }
            
            ForEach(selectedNodes, id: \.id) { node in
            
                Section(header: Text( node.name ) )
                {
                    @Bindable var bindableNode:Node = node
                    
                    Toggle("Node Settings", isOn: $bindableNode.showSettings)
                        .opacity(bindableNode.providesSettingsView() ? 1.0 : 0.0)

                    ParameterGroupView(parameterGroup: node.parameterGroup)
                }
            }
        }
        .listStyle(.sidebar)
        .id(graph.shouldUpdateConnections)
        
    }
}

//#Preview {
////    NodeSelectionInspector()
//}
