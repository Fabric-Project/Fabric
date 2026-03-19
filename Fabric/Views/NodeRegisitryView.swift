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
    @Binding private var inputFocus: FabricEditorInputFocus

    @State private var searchString:String = ""
    @State private var selection = Set<UUID>()
    @State private var headerSelection: Node.NodeTypeGroups = .All
    @FocusState private var isSearchFocused: Bool

    // These are computed properties in an effort to avoid race conditions on multiple states
    private var filteredNodesForTypes: [Node.NodeType:[NodeClassWrapper]] {
        Dictionary(uniqueKeysWithValues: Node.NodeType.allCases.map { t in (t, self.filteredNodes(forType: t)) })
    }

    /// Flat ordered list of currently visible nodes, respecting header filter and search.
    ///
    /// SwiftUI's List handles arrow-key navigation internally, but only when the List itself
    /// holds keyboard focus. Our UX requires the search field to retain focus for typing while
    /// arrow keys simultaneously navigate the list. List exposes no API to drive selection
    /// externally (no moveSelectionDown(), no ordered-item query, no "select first" command),
    /// and it silently retains stale UUIDs in the selection binding when items leave the data
    /// source. This property bridges that gap — it gives us the ordered item list needed by
    /// selectFirstNode(), moveSelection(by:), the search-text onChange validity check,
    /// and the "No Results Found" overlay (via numNodesToShow / haveNodesToShow).
    /// When the List has focus (e.g. after a click), its native keyboard handling takes over
    /// and these helpers are bypassed via the isSearchFocused guard.
    private var visibleNodes: [NodeClassWrapper] {
        self.headerSelection.nodeTypes().flatMap { self.filteredNodes(forType: $0) }
    }

    private var numNodesToShow: Int { self.visibleNodes.count }

    private var haveNodesToShow: Bool { self.numNodesToShow > 0 }
    
    public init(graph: Graph, inputFocus: Binding<FabricEditorInputFocus>) {
        self.graph = graph
        self._inputFocus = inputFocus
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

            ScrollViewReader { listProxy in
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
                                        .id(node.id)
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

                } primaryAction: { _ in
                    self.addSelectedNodes()
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        self.inputFocus = .registry
                    }
                )
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
                .onChange(of: self.selection) { _, newSelection in
                    self.inputFocus = .registry
                    if let id = newSelection.first
                    {
                        withAnimation {
                            listProxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            
//            Divider()
//            
//            Spacer()
        }
        .searchable(text: $searchString, placement: .sidebar)
        .searchFocused($isSearchFocused)
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onChange(of: self.searchString) { _, _ in
            self.inputFocus = .registry
            let visible = self.visibleNodes
            let selectionStillValid = self.selection.contains(where: { id in visible.contains(where: { $0.id == id }) })
            if !selectionStillValid
            {
                self.selectFirstNode()
            }
        }
        .onChange(of: self.inputFocus) { _, newValue in
            if newValue == .registry
            {
                self.isSearchFocused = true
            }
        }
        .onChange(of: self.isSearchFocused) { _, focused in
            if focused, self.selection.isEmpty
            {
                self.selectFirstNode()
            }
        }
        // Manual key handling for search-focused mode. When the List has focus these return
        // .ignored, letting the List's native arrow navigation and primaryAction take over.
        .onKeyPress(.upArrow) {
            guard self.isSearchFocused else { return .ignored }
            self.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard self.isSearchFocused else { return .ignored }
            self.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard self.isSearchFocused, !self.selection.isEmpty else { return .ignored }
            self.addSelectedNodes()
            return .handled
        }
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
                        self.inputFocus = .registry
                        self.headerSelection = nodeGroup
                    }
            }
            
            Spacer()
        }
    }
    
    private func addSelectedNodes()
    {
        for nodeID in self.selection
        {
            if let node = NodeRegistry.shared.availableNodes.first(where: { $0.id == nodeID })
            {
                do
                {
                    try self.graph.addNode(node)
                }
                catch
                {
                    print("Unable to add node:\(node)")
                }
            }
        }
        self.inputFocus = .canvas
    }

    private func selectFirstNode()
    {
        if let first = self.visibleNodes.first
        {
            self.selection = [first.id]
        }
        else
        {
            self.selection.removeAll()
        }
    }

    private func moveSelection(by offset: Int)
    {
        let nodes = self.visibleNodes
        guard !nodes.isEmpty else { return }

        let currentID = self.selection.first
        let currentIndex = currentID.flatMap { id in nodes.firstIndex(where: { $0.id == id }) }
        let newIndex: Int

        if let currentIndex
        {
            newIndex = min(max(currentIndex + offset, 0), nodes.count - 1)
        }
        else
        {
            newIndex = 0
        }

        self.selection = [nodes[newIndex].id]
    }

    func filteredNodes(forType nodeType:Node.NodeType) -> [NodeClassWrapper]
    {
        let availableNodes:[NodeClassWrapper] = NodeRegistry.shared.availableNodes
        let nodesForType:[NodeClassWrapper] = availableNodes.filter( { $0.nodeType == nodeType })
        return  self.searchString.isEmpty ? nodesForType : nodesForType.filter {  $0.nodeName.localizedCaseInsensitiveContains(self.searchString) }
    }
}
