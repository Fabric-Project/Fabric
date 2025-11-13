//
//  NodeRegisitryView.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import SwiftUI
import Satin

public struct NodeRegisitryView: View {

    public let graph: Graph
    @Binding public var scrollOffset: CGPoint

    @State private var searchString:String = ""
    @State private var selection: Node.NodeTypeGroups = .SceneGraph

    public init(graph: Graph, scrollOffset: Binding<CGPoint>) {
        self.graph = graph
        self._scrollOffset = scrollOffset
    }
    
    public var body: some View
    {
        VStack(spacing: 0)
        {
            Divider()
            
            Spacer()

            HStack
            {
                Spacer()
                                    
                ForEach(Node.NodeTypeGroups.allCases, id: \.self) { nodeGroup in
                    //Label(nodeType.rawValue, systemImage: nodeType.imageName())
                    nodeGroup.image()
                        .foregroundStyle( nodeGroup == selection ? Color.accentColor : Color.secondary.opacity(0.5))
                        .tag(nodeGroup)
                        .help(nodeGroup.rawValue)
                        .onTapGesture {
                            self.selection = nodeGroup
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
                    
                    let filteredNodes = self.filteredNodes(forType: nodeType)
                    
                    if !filteredNodes.isEmpty
                    {
                        Section(header: Text("\(nodeType)")) {
                            
                            ForEach( 0 ..< filteredNodes.count, id:\.self ) { idx in
                                
                                let node = filteredNodes[idx]
                                
                                Text(node.nodeName)
                                    .font( .system(size: 11) )
                                    .onTapGesture {
                                        do {
                                            try self.graph.addNode(node, initialOffset:self.scrollOffset)
                                        }
                                        catch
                                        {
                                            
                                        }
                                    }
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
    
    func filteredNodes(forType nodeType:Node.NodeType) -> [NodeClassWrapper]
    {
        let availableNodes:[NodeClassWrapper] = NodeRegistry.shared.availableNodes
        let nodesForType:[NodeClassWrapper] = availableNodes.filter( { $0.nodeType == nodeType })
        return  self.searchString.isEmpty ? nodesForType : nodesForType.filter {  $0.nodeName.localizedCaseInsensitiveContains(self.searchString) }
    }
}
