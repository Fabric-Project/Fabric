//
//  GraphCanvas.swift
//  Fabric
//
//  Created by Anton Marini on 5/26/24.
//

import SwiftUI
import UniformTypeIdentifiers

typealias GraphSettingsEntry = (id: UUID, nodeViewModel: NodeViewModel, anchorSize: CGSize)

public struct GraphCanvas : View
{
    let editingContext: GraphCanvasContext
    let focus: FocusState<FabricEditorFocusTarget?>.Binding
    let canvasSize: CGSize
    let connectionsHitTestingEnabled: Bool

    public init(editingContext: GraphCanvasContext,
                focus: FocusState<FabricEditorFocusTarget?>.Binding,
                canvasSize: CGSize,
                connectionsHitTestingEnabled: Bool = true)
    {
        self.editingContext = editingContext
        self.focus = focus
        self.canvasSize = canvasSize
        self.connectionsHitTestingEnabled = connectionsHitTestingEnabled
        self.editingContext.canvasSize = canvasSize
    }

    // Marquee (rubber-band) selection
    @State private var marqueeRect: CGRect = .zero
    @State private var preMarqueeSelection: Set<UUID> = []

    @State private var renamingNodeID: UUID? = nil

    // Stable list of settings panels keyed by NodeViewModel — port changes
    // do not mutate this list so active popovers are never dismissed unexpectedly.
    @State private var settingsEntries: [GraphSettingsEntry] = []

    public var body: some View
    {
        ZStack
        {
            GraphBackground()
                .offset(-canvasSize / 2)

            GraphNotesView(editingContext: editingContext,
                           focus: focus)
                .offset(-canvasSize / 2)

            GraphNodesView(editingContext: editingContext,
                           focus: focus,
                           settingsEntries: $settingsEntries,
                           renamingNodeID: $renamingNodeID)
                .offset(-canvasSize / 2)

            GraphNodeSettingsView(settingsEntries: $settingsEntries,
                                  focus: focus)
                .offset(-canvasSize / 2)
        }
        .offset(canvasSize / 2)
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .coordinateSpace(name: "graph")
        .overlay {
            GraphConnectionsView(editingContext: editingContext,
                                 allowsConnectionHitTesting: connectionsHitTestingEnabled,
                                 marqueeRect: marqueeRect)
            .id(editingContext.currentGraph.connectionRevision)
        }
        .focusable(true, interactions: .edit)
        .focused(focus, equals: .canvas)
        .focusEffectDisabled()
        .onKeyPress(keys: self.keys()) { keyPress in
            return self.handleKeyPress(keyPress: keyPress)
        }
#if os(macOS)
        .onDeleteCommand {
            guard self.focus.wrappedValue == .canvas else { return }
            
            let currentGraph = self.editingContext.currentGraph
            currentGraph.selectedNodes.forEach { currentGraph.delete(node: $0) }
        }
#endif
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    self.calcMarqueeDragChanged(forValue: value,
                                                currentGraph: self.editingContext.currentGraph,
                                                canvasSize: canvasSize)
                }
                .onEnded { _ in
                    self.marqueeRect = .zero
                    self.preMarqueeSelection = []
                }
        )
        // No focus write here: the canvas is .focusable(interactions: .edit),
        // so a click already gives it focus. Writing the FocusState again from
        // a tap handler triggers a redundant update that can revoke focus.
        .onTapGesture {
            self.editingContext.currentGraph.deselectAllNodes()
        }
        .onDrop(of: [.nodeRegistryItem, .fileURL], isTargeted: nil) { providers, location in
            self.handleDrop(providers: providers, location: location, canvasSize: canvasSize)
        }
        .onChange(of: editingContext.currentGraph.nodes.count) { _, _ in
            let nodeIDs = Set(editingContext.currentGraph.nodes.map(\.id))
            settingsEntries.removeAll { !nodeIDs.contains($0.id) }
        }
    }

    // MARK: - Marquee Drag

    private func calcMarqueeDragChanged(forValue value: DragGesture.Value, currentGraph graph: Graph, canvasSize: CGSize)
    {
        if self.marqueeRect == .zero
        {
            if NSEvent.modifierFlags.contains(.shift)
            {
                self.preMarqueeSelection = Set(graph.selectedNodes.map(\.id))
            }
            else
            {
                preMarqueeSelection = []
                graph.deselectAllNodes()
            }
        }

        let start = value.startLocation

        let origin = CGPoint(x: min(start.x, value.location.x),
                             y: min(start.y, value.location.y))

        let size = CGSize(width: abs(value.location.x - start.x),
                          height: abs(value.location.y - start.y))

        self.marqueeRect = CGRect(origin: origin, size: size)

        let marqueeInNodeSpace = CGRect(
            x: origin.x - canvasSize.width / 2,
            y: origin.y - canvasSize.height / 2,
            width: size.width,
            height: size.height
        )

        for node in graph.nodes
        {
            let nodeViewModel = graph.viewModel(for: node)
            let nodeOrigin = CGPoint(x: nodeViewModel.offset.width  - nodeViewModel.nodeSize.width  / 2,
                                     y: nodeViewModel.offset.height - nodeViewModel.nodeSize.height / 2)
            let nodeRect = CGRect(origin: nodeOrigin, size: nodeViewModel.nodeSize)
            let inMarquee = nodeRect.intersects(marqueeInNodeSpace)
            nodeViewModel.isSelected = inMarquee || preMarqueeSelection.contains(node.id)
        }
    }

    // MARK: - Drop Helpers

    // FIXME: NSItemProvider load callbacks run on an arbitrary queue. Graph/Node are not
    // thread-safe and have no actor isolation, so the addNode calls below rely on AppKit
    // happening to deliver on main. If Fabric adopts Swift 6 strict concurrency or
    // @MainActor isolation, these callbacks will need explicit main-thread dispatch.

    private func handleDrop(providers: [NSItemProvider], location: CGPoint, canvasSize: CGSize) -> Bool
    {
        let currentGraph = self.editingContext.currentGraph

        var handled = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.nodeRegistryItem.identifier)
        {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.nodeRegistryItem.identifier) { data, error in
                guard let data = data,
                      let dragData = try? JSONDecoder().decode(NodeRegistryDragData.self, from: data),
                      let wrapper = try? NodeRegistry.shared.availableNodes.first(where: { $0.id == dragData.wrapperID })
                else {
                    print("GraphCanvas: registry drag decode failed: \(error?.localizedDescription ?? "unknown")")
                    handled = false
                    return
                }

                do {
                    let node = try wrapper.initializeNode(context: currentGraph.context)
                    try self.editingContext.layoutNode(node)

                    node.offset.width += location.x - canvasSize.width / 2.0 - self.editingContext.currentScrollOffset.x
                    node.offset.height += location.y - canvasSize.height / 2.0 - self.editingContext.currentScrollOffset.y - node.nodeSize.height / 4.0

                    currentGraph.addNode(node)
                    handled = true
                }
                catch {
                    print("GraphCanvas: failed to create node from registry drag: \(error)")
                    handled = false
                }
            }

        }

        return handled ? true :  self.handleFileDrop(providers: providers, location: location, canvasSize: canvasSize)
    }

    private func handleFileDrop(providers: [NSItemProvider], location: CGPoint, canvasSize: CGSize) -> Bool
    {
        let currentGraph = self.editingContext.currentGraph
        var handled = false

        for provider in providers
        {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true)
                else { return }

                guard let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
                      let contentType = resourceValues.contentType,
                      let nodeClass = try? NodeRegistry.shared.dropTargetNodeClass(for: contentType)
                else { return }

                let node = nodeClass.init(context: currentGraph.context)
                node.setFileURL(url)
                node.offset = CGSize(width: location.x - canvasSize.width / 2.0 - node.nodeSize.width / 2.0,
                                     height: location.y - canvasSize.height / 2.0 - node.nodeSize.height / 2.0)
                currentGraph.addNode(node)
            }

            handled = true
        }

        return handled
    }

    // MARK: - Key Press

    private func keys() -> Set<KeyEquivalent>
    {
        return [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .space, .escape, .deleteForward]
    }

    private func handleKeyPress(keyPress: KeyPress) -> KeyPress.Result
    {
        // Real focus, not a shadow flag: when a text field (settings popover,
        // rename, search) is being edited this is not .canvas, so arrows and
        // delete pass through to the field editor.
        guard self.focus.wrappedValue == .canvas else { return .ignored }
        if renamingNodeID != nil { return .ignored }

        switch keyPress.key
        {
        case .upArrow:
            self.editingContext.currentGraph.selectNextNode(inDirection: .Up, expandSelection: keyPress.modifiers.contains(.shift))

        case .downArrow:
            self.editingContext.currentGraph.selectNextNode(inDirection: .Down, expandSelection: keyPress.modifiers.contains(.shift))

        case .leftArrow:
            self.editingContext.currentGraph.selectNextNode(inDirection: .Left, expandSelection: keyPress.modifiers.contains(.shift))

        case .rightArrow:
            self.editingContext.currentGraph.selectNextNode(inDirection: .Right, expandSelection: keyPress.modifiers.contains(.shift))

        case .escape:
            self.editingContext.currentGraph.deselectAllNodes()

        case .deleteForward:
            let currentGraph = self.editingContext.currentGraph
            currentGraph.selectedNodes.forEach { currentGraph.delete(node: $0) }

        default:
            return .ignored
        }

        return .handled
    }
}
