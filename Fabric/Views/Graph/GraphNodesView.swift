//
//  GraphNodesView.swift
//  Fabric
//

import SwiftUI

struct GraphNodesView: View
{
    let editingContext: GraphCanvasContext
    let focus: FocusState<FabricEditorFocusTarget?>.Binding
    @Binding var settingsEntries: [GraphSettingsEntry]
    @Binding var renamingNodeID: UUID?

    /// Move keyboard focus to the canvas so arrow-key node navigation works
    /// after interacting with a node. Guarded so an already-focused canvas
    /// doesn't get a redundant FocusState write (which can revoke focus).
    private func focusCanvas()
    {
        if focus.wrappedValue != .canvas { focus.wrappedValue = .canvas }
    }

    @State private var initialOffsets: [UUID: CGSize] = [:]
    @State private var activeDragAnchor: UUID? = nil

    var body: some View
    {
        let currentGraph = editingContext.currentGraph

        ForEach(currentGraph.nodes) { currentNode in
            let nodeViewModel = currentGraph.viewModel(for: currentNode)

            NodeView(nodeViewModel: nodeViewModel, editingContext: editingContext)
                .offset(nodeViewModel.offset)
#if os(macOS)
                .highPriorityGesture(
                    TapGesture(count: 1)
                        .modifiers(.shift)
                        .onEnded {
                            self.focusCanvas()
                            nodeViewModel.isSelected.toggle()
                        }
                )
#endif
                .gesture(
                    SimultaneousGesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                self.calcDragChanged(forValue: value,
                                                     currentGraph: currentGraph,
                                                     currentNodeViewModel: nodeViewModel)
                            }
                            .onEnded { _ in
                                self.calcDragEnded(currentGraph: currentGraph)
                            },

                        SimultaneousGesture(
                            TapGesture(count: 1)
                                .onEnded {
                                    self.focusCanvas()
                                    currentGraph.deselectAllNodes()
                                    nodeViewModel.isSelected.toggle()
                                },
                            TapGesture(count: 2)
                                .onEnded {
                                    self.focusCanvas()
                                    if let subgraph = currentNode as? SubgraphNode
                                    {
                                        self.editingContext.enter(subgraph)
                                    }
                                }
                        )
                    )
                )
                .contextMenu {
                    self.contextMenu(forNode: currentNode,
                                     nodeViewModel: nodeViewModel,
                                     currentGraph: currentGraph)
                }
                .onChange(of: nodeViewModel.showSettings) { _, show in
                    self.sychronizeSettingsFor(nodeViewModel: nodeViewModel, show: show)
                }
        }
    }

    // MARK: - Drag Helpers

    private func calcDragChanged(forValue value: DragGesture.Value,
                                  currentGraph: Graph,
                                  currentNodeViewModel: NodeViewModel)
    {
        self.focusCanvas()

        if self.activeDragAnchor == nil
        {
            self.activeDragAnchor = currentNodeViewModel.id

            if !currentNodeViewModel.isSelected
            {
                currentGraph.selectNode(node: currentNodeViewModel.node, expandSelection: false)
            }

            self.initialOffsets = Dictionary(uniqueKeysWithValues: currentGraph.selectedNodes
                .map { ($0.id, currentGraph.viewModel(for: $0).offset) }
            )

            currentGraph.selectedNodes.forEach { currentGraph.viewModel(for: $0).isDragging = true }
        }

        let t = value.translation
        for node in currentGraph.selectedNodes
        {
            let nodeViewModel = currentGraph.viewModel(for: node)
            if let base = initialOffsets[node.id] {
                nodeViewModel.offset = base + t
            }
        }
    }

    private func calcDragEnded(currentGraph: Graph)
    {
        let selectedNodes = currentGraph.selectedNodes

        currentGraph.undoManager?.beginUndoGrouping()

        for node in selectedNodes
        {
            if let offset = initialOffsets[node.id]
            {
                currentGraph.undoManager?.registerUndo(withTarget: node) {
                    let cachedOffset = $0.offset
                    currentGraph.undoManager?.registerUndo(withTarget: node) { $0.offset = cachedOffset }
                    $0.offset = offset
                }
            }
        }

        currentGraph.undoManager?.endUndoGrouping()
        currentGraph.undoManager?.setActionName("Move Nodes")

        selectedNodes.forEach { currentGraph.viewModel(for: $0).isDragging = false }
        self.activeDragAnchor = nil
        self.initialOffsets.removeAll()
    }

    // MARK: - Context Menu

    @ViewBuilder private func contextMenu(forNode currentNode: Node,
                                           nodeViewModel: NodeViewModel,
                                           currentGraph: Graph) -> some View
    {
        Menu("Selection")
        {
            Button {
                currentGraph.selectAllNodes()
            } label: {
                Text("Select All Nodes")
            }

            Button {
                currentGraph.deselectAllNodes()
                currentGraph.selectUpstreamNodes(fromNode: currentNode)
            } label: {
                Text("Select All Upstream Nodes")
            }

            Button {
                currentGraph.deselectAllNodes()
                currentGraph.selectDownstreamNodes(fromNode: currentNode)
            } label: {
                Text("Select All Downstream Nodes")
            }

            Menu("Embed Selection In...") {
                let embedClasses = [SubgraphNode.self, IteratorNode.self, EnvironmentNode.self, DeferredSubgraphNode.self]

                ForEach(0 ..< embedClasses.count, id: \.self) { embedClassIndex in
                    let embedClass = embedClasses[embedClassIndex]
                    Button {
                        currentGraph.createSubgraphFromSelection(centeredOnNode: currentNode, usingClass: embedClass)
                    } label: {
                        Text(embedClass.name)
                    }
                }
            }
        }

        Button {
            renamingNodeID = currentNode.id
        } label: {
            Text("Rename")
        }

        Divider()

#if os(macOS)
        Button {
            let nodesToCopy = currentGraph.selectedNodes.isEmpty ? [currentNode] : currentGraph.selectedNodes
            currentGraph.copyNodesToPasteboard(nodesToCopy)
        } label: {
            Text("Copy")
        }
#endif

        Button {
            let nodesToDuplicate = currentGraph.selectedNodes.isEmpty ? [currentNode] : currentGraph.selectedNodes
            currentGraph.duplicateNodes(nodesToDuplicate)
        } label: {
            Text("Duplicate")
        }
    }

    // MARK: - Node Settings

    // Settings popover focus is handled by GraphNodeSettingsView so canvas and
    // registry key handlers do not steal keys while settings controls are active.
    private func sychronizeSettingsFor(nodeViewModel: NodeViewModel, show: Bool)
    {
        if show && nodeViewModel.providesSettingsView()
        {
            if !settingsEntries.contains(where: { $0.id == nodeViewModel.id })
            {
                settingsEntries.append((id: nodeViewModel.id, nodeViewModel: nodeViewModel, anchorSize: nodeViewModel.nodeSize))
            }
        }
        else if !show
        {
            settingsEntries.removeAll { $0.id == nodeViewModel.id }
        }
    }
}
