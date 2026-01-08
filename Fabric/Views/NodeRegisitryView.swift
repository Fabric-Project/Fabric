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

    // These are computed properties in an effort to avoid race conditions on multiple states
    private var filteredNodesForTypes: [Node.NodeType:[NodeClassWrapper]] {
        Dictionary(uniqueKeysWithValues: Node.NodeType.allCases.map { t in (t, self.filteredNodes(forType: t)) })
    }

    private var numNodesToShow: Int {
        self.headerSelection.nodeTypes().flatMap { self.filteredNodes(forType: $0) }.count
    }

    private var haveNodesToShow: Bool { self.numNodesToShow > 0 }
    
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

            self.headerBar()

            Spacer()

            Divider()

            List(selection:$selection)
            {
                ForEach(self.headerSelection.nodeTypes(), id: \.self) { nodeType in
                    
                    if let filteredNodesForType:[NodeClassWrapper] = self.filteredNodesForTypes[nodeType],
                       filteredNodesForType.isEmpty == false
                    {
                        Section(header: Text("\(nodeType)")) {
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
            // * Single click to select
            // * Multi Select
            // * Type to select
            // * Arrow navigation
            // Weird that its a context menu filter! But whatever.
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
                VStack(spacing:0)
                {
                    Spacer()
                    
                    Text("No Results Found")
                        .font( .headline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .opacity( self.haveNodesToShow ? 0.0 : 1.0 )
            }
            
//            Divider()
//            
//            Spacer()
        }
        .controlSize(.mini)
        .searchable(text: $searchString, placement: .sidebar)
        .searchPresentationToolbarBehavior(.avoidHidingContent)

        
        // It seems as though our custom search bar vs .searchable behave slightly differently?
        // Not sure why that is!?
//        .safeAreaInset(edge: .bottom) {
//            self.searchBar()
//        }
//        .onChange(of: self.searchString) { _, _ in
//            self.selection.removeAll()
//        }
//        .onChange(of: self.headerSelection) { _, _ in
//            self.selection.removeAll()
//        }
//        .onAppear()
//        {
//            // not the best..
//            self.numNodesToShow = self.calcNumTotalNodes()
//            self.filteredNodesForTypes = self.calcFilteredNodesDict()
//        }
    }
    
    @ViewBuilder private func headerBar() -> some View
    {
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
    }
    
    @ViewBuilder private func searchBar() -> some View
    {
        VStack(spacing:0)
        {
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
            
            Text(String( self.numNodesToShow ) + " Nodes")
                .font( .caption )
                .padding(.vertical, 3)
        }
    }
    
    func filteredNodes(forType nodeType:Node.NodeType) -> [NodeClassWrapper]
    {
        let availableNodes:[NodeClassWrapper] = NodeRegistry.shared.availableNodes
        let nodesForType:[NodeClassWrapper] = availableNodes.filter( { $0.nodeType == nodeType })
        return  self.searchString.isEmpty ? nodesForType : nodesForType.filter {  $0.nodeName.localizedCaseInsensitiveContains(self.searchString) }
    }
}
