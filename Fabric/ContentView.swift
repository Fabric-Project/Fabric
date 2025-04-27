//
//  ContentView.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Satin

struct ContentView: View {
    @Binding var document: FabricDocument

    @GestureState private var magnifyBy = 1.0
    
    @State private var finalMagnification = 1.0
    
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn

    @State private var searchString:String = ""
   
    var body: some View {
//        TextEditor(text: $document.text)
        
        NavigationSplitView(columnVisibility: self.$columnVisibility)
        {
            List {
                ForEach(Node.NodeType.allCases, id: \.self) { nodeType in
                        
                    Section(header: Text("\(nodeType)")) {
                        
                        let nodesForType = NodeRegistry.shared.nodesClasses.filter( { $0.type == nodeType })
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

        } content: {
            
            ZStack
            {
                Color.black.opacity(0.2)
                
                SatinMetalView(renderer: document.graphRenderer)
                
                ScrollView([.horizontal, .vertical])
                {
                    NodeCanvas()
                        .frame(width: 10000 , height: 10000)
                        .environment(self.document.graph)
                    //                        .scaleEffect(self.magnifyBy + self.finalMagnification)
                    
                    //                        .gesture(magnification)
                    
                }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.5))
            }
        } detail:
        {
            Text("Params go here")
        }

    }
}

#Preview {
    ContentView(document: .constant(FabricDocument()))
}
