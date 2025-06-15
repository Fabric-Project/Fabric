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

    @State private var selection: Node.NodeTypeGroups = .SceneGraph

    @Binding var scrollOffset: CGPoint
    
    var body: some View
    {
        VStack(spacing: 0)
        {
            Divider()
            
            Spacer()

            HStack
            {
                Spacer()
                                    
                ForEach(Node.NodeTypeGroups.allCases, id: \.self) { nodeType in
                    //Label(nodeType.rawValue, systemImage: nodeType.imageName())
                    nodeType.image()
                        .foregroundStyle( nodeType == selection ? Color.accentColor : Color.secondary.opacity(0.5))
                        .tag(nodeType)
                        .help(nodeType.rawValue)
                        .onTapGesture {
                            self.selection = nodeType
                        }
                }
                
                Spacer()
            }
            
            Spacer()

            Divider()

            Spacer()

            List
            {
                ForEach(selection.nodeTypes(), id: \.self) { nodeType in
                    
                    Section(header: Text("\(nodeType)")) {
                        
                        let nodesForType = NodeRegistry.shared.nodesClasses.filter( { $0.nodeType == nodeType })
                        let filteredNodes = self.searchString.isEmpty ? nodesForType :
                        nodesForType.filter {  $0.name.localizedCaseInsensitiveContains(self.searchString) }
                        
                        ForEach( 0 ..< filteredNodes.count, id:\.self ) { idx in
                            
                            let nodeType = filteredNodes[idx]
                            
                            Text(nodeType.name)
                                .font( .system(size: 11) )
                                .onTapGesture {
                                    self.document.graph.addNodeType(nodeType, initialOffset:self.scrollOffset)
                                }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: VerticalEdge.bottom, content: {
            
            VStack
            {
                Divider()
                
                HStack
                {
                    Spacer()

                    TextField("Search", text: $searchString)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .controlSize(.small)
                    
                    Spacer()
                    
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .onTapGesture {
                            self.searchString = ""
                        }
                    
                    Spacer()

                }
                .padding(.bottom, 3)
            }
        })
    }
}
