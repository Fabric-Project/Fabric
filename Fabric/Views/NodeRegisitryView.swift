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
    @State private var selection = Set<UUID>()
    @State private var headerSelection: Node.NodeTypeGroups = .All

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
                        .foregroundStyle( nodeGroup == headerSelection ? Color.accentColor : Color.secondary.opacity(0.5))
                        .tag(nodeGroup)
                        .help(nodeGroup.rawValue)
                        .onTapGesture {
                            self.headerSelection = nodeGroup
                        }
                }
                
                Spacer()
            }
            
            Spacer()

            Divider()
            
            Spacer()
            
            List(selection:$selection)
            {
                ForEach(self.headerSelection.nodeTypes(), id: \.self) { nodeType in
                    
                    if let filteredNodesForType:[NodeClassWrapper] = self.filteredNodesForTypes[nodeType],
                       filteredNodesForType.isEmpty == false
                    {
                        Section(header: Text("\(nodeType.rawV)")) {
                            ForEach(filteredNodesForType, id: \.id) { node in
                                Text(node.nodeName)
                                    .tag(node.id)
                                    .font( .system(size: 11) )
                            }
                        }
                    }
                }
            }
            // Below replaces the onTap action that was on the list item
            // This affords double click to add / return to add
            // Single click to select
            // Multi Select
            // Type to select
            // Arrow navigation
            // Weird that its a context menu filter!
            // This fixes #114 - Anton
            .contextMenu(forSelectionType: UUID.self)
            { items in
                
                // No context menu ever
                EmptyView()
                
            } primaryAction: { selection in

                for nodeID in selection
                {
                    if let node = NodeRegistry.shared.availableNodes.first(where: { $0.id == nodeID })
                    {
                        do
                        {
                            try self.graph.addNode(node, initialOffset:self.scrollOffset)
                        }
                        catch
                        {
                            print("Unable to add node:\(node)")
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
        self.headerSelection.nodeTypes().compactMap( { self.filteredNodes(forType:$0)} ).joined().count
    }
}
