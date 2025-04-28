//
//  NodeRegisitryView.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import SwiftUI
import Satin

struct NodeRegisitryView: View {

    @Binding var document: FabricDocument

    @State private var searchString:String = ""

    var body: some View
    {
        List {
            ForEach(Node.NodeType.allCases, id: \.self) { nodeType in
                
                Section(header: Text("\(nodeType)")) {
                    
                    let nodesForType = NodeRegistry.shared.nodesClasses.filter( { $0.nodeType == nodeType })
                    let filteredNodes = self.searchString.isEmpty ? nodesForType :
                    nodesForType.filter {  $0.name.localizedCaseInsensitiveContains(self.searchString) }
                    
                    ForEach( 0 ..< filteredNodes.count, id:\.self ) { idx in
                        
                        let nodeType = filteredNodes[idx]
                        
                        Text(nodeType.name)
                            .font( .system(size: 11) )
                            .onTapGesture {
                                self.document.graph.addNodeType(nodeType)
                            }
                    }
                }
            }
        }
        .searchable(text: $searchString, placement:.sidebar)
        .controlSize(.small)
    }
}
