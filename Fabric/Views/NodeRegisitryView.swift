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
    @State private var selection: Node.NodeTypeGroups = .All

    @State private var numNodesToShow = 0
    @State private var haveNodesToShow = true
    @State private var filteredNodesForTypes: [Node.NodeType:[NodeClassWrapper]] = [:]
    
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
                ForEach(self.selection.nodeTypes(), id: \.self) { nodeType in
                    
                    if let filteredNodesForType:[NodeClassWrapper] = self.filteredNodesForTypes[nodeType],
                       filteredNodesForType.isEmpty == false
                    {
                        
                        Section(header: Text("\(nodeType)")) {
                            
                            ForEach( 0 ..< filteredNodesForType.count, id:\.self ) { idx in
                                
                                let node = filteredNodesForType[idx]
                                
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
            .overlay
            {
                VStack
                {
                    Spacer()
                    
                    Text("No Results Found")
                        .font( .headline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .opacity( self.haveNodesToShow ? 0.0 : 1.0 )
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
                        .onChange(of: self.searchString) { _, _ in
                            self.numNodesToShow = self.calcNumTotalNodes()
                            self.haveNodesToShow = self.calcIfWeHaveNodesToShow()
                            self.filteredNodesForTypes = self.calcFilteredNodesDict()
                        }
                    
                    Spacer()
                    
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .onTapGesture {
                            self.searchString = ""
                        }
                    
                    Spacer()
                }
                
                Text(String( self.numNodesToShow ) + " Nodes")
                    .font( .caption )
                    .padding(.vertical, 3)
            }
        })
        .onAppear()
        {
            // not the best..
            self.numNodesToShow = self.calcNumTotalNodes()
            self.filteredNodesForTypes = self.calcFilteredNodesDict()
        }
    }
    
    func calcFilteredNodesDict() -> [Node.NodeType:[NodeClassWrapper]]
    {
        var dict = [Node.NodeType:[NodeClassWrapper]]()
        
        for nodeType in Node.NodeType.allCases
        {
            dict[nodeType] = self.filteredNodes(forType: nodeType)
        }
        
        return dict
    }
    
    func filteredNodes(forType nodeType:Node.NodeType) -> [NodeClassWrapper]
    {
        let availableNodes:[NodeClassWrapper] = NodeRegistry.shared.availableNodes
        let nodesForType:[NodeClassWrapper] = availableNodes.filter( { $0.nodeType == nodeType })
        return  self.searchString.isEmpty ? nodesForType : nodesForType.filter {  $0.nodeName.localizedCaseInsensitiveContains(self.searchString) }
    }
    
    func calcIfWeHaveNodesToShow() -> Bool
    {
        self.numNodesToShow > 0
    }
    
    func calcNumTotalNodes() -> Int
    {
        self.selection.nodeTypes().compactMap( { self.filteredNodes(forType:$0)} ).joined().count
    }
}
