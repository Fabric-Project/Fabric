//
//  GraphCanvas.swift
//  v
//
//  Created by Anton Marini on 5/26/24.
//

import SwiftUI
import UniformTypeIdentifiers

public struct GraphCanvas : View
{
    let editingContext: GraphCanvasContext
    @Binding var inputFocus: FabricEditorInputFocus

    public init(editingContext: GraphCanvasContext, inputFocus: Binding<FabricEditorInputFocus>)
    {
        self.editingContext = editingContext
        self._inputFocus = inputFocus
    }

//    @State var activityMonitor = GraphCanvasUserActivityMonitor()

    // Drag to Offset bullshit
    @State private var initialOffsets: [UUID: CGSize] = [:]
    @State private var activeDragAnchor: UUID? = nil       // which node started the drag

    // Marquee (rubber-band) selection
    @State private var marqueeRect: CGRect = .zero
    @State private var preMarqueeSelection: Set<UUID> = []
    
    @State private var renamingNodeID: UUID? = nil // node being renamed

    // Stable list of nodes with settings open - only mutated on explicit open/close
    // NOT derived from currentGraph.nodes, so port changes don't cause re-evaluation
    @State private var settingsEntries: [(id: UUID, node: Node, width: CGFloat, height: CGFloat, offset: CGSize)] = []

    public var body: some View
    {
        GeometryReader { geom in

            ZStack
            {
                // image size is 255
                Image("background")
                    .resizable(resizingMode: .tile)// Need this pattern image repeated throughout the page
                    .offset(-geom.size / 2)

                let currentGraph = self.editingContext.currentGraph

                ForEach(currentGraph.notes, id:\.id) { currentNote in

                    NoteView(note: currentNote)
                        .offset(-geom.size / 2)
                        .offset(x: currentNote.rect.origin.x, y: currentNote.rect.origin.y )
                        .contextMenu {
                            Button("Delete Note") {
                                currentGraph.deleteNote(currentNote)
                            }
                        }
                }

                ForEach(currentGraph.nodes, id: \.id) { currentNode in

                    NodeView(node: currentNode, editingContext: self.editingContext, offset: currentNode.offset)

                        .offset(-geom.size / 2)
                        .offset( currentNode.offset )
                    #if os(macOS)
                        .highPriorityGesture(
                            TapGesture(count: 1)
                                .modifiers(.shift)
                                .onEnded {
                                    self.inputFocus = .canvas
                                    // Expand selection
                                    currentNode.isSelected.toggle()
                                },
                        )
                    #endif
                        .gesture(
                            SimultaneousGesture(
                                DragGesture(minimumDistance: 3)
                                    .onChanged { value in

                                        self.calcDragChanged(forValue: value, currentGraph: currentGraph, currentNode: currentNode)
                                    }
                                    .onEnded { _ in

                                        self.calcDragEnded(currentGraph: currentGraph)
                                    },

                                SimultaneousGesture(

                                    TapGesture(count: 1)
                                        .onEnded {
                                            self.inputFocus = .canvas
                                            // Replace selection
                                            currentGraph.deselectAllNodes()
                                            currentNode.isSelected.toggle()
                                        },
                                    TapGesture(count: 2)
                                        .onEnded
                                    {
                                        self.inputFocus = .canvas
                                        if let subgraph = currentNode as? SubgraphNode
                                        {
                                            self.editingContext.enter(subgraph)
                                        }
                                    }
                                )
                            )
                        )
                        .contextMenu
                        {
                            self.contextMenu(forNode: currentNode, currentGraph: currentGraph)
                        }
                        .onChange(of: currentNode.showSettings) { _, show in
                            self.sychronizeSettingsFor(node: currentNode, show: show)
                        }
                }

                // Settings popovers - uses stable @State list so port changes don't
                // cause ForEach re-evaluation and popover dismissal
                ForEach(settingsEntries, id: \.id) { entry in
                    NodeSettingsPopoverAnchor( node: entry.node,
                                               nodeWidth: entry.width,
                                               nodeHeight: entry.height,
                                               onClose: {
                        // Setting showSettings = false triggers onChange which removes from settingsEntries
                        entry.node.showSettings = false
                    })
                    .offset(-geom.size / 2)
                    .offset(entry.offset)
                }
            }
            .offset(geom.size / 2)
            .clipShape(Rectangle())
            .contentShape(Rectangle())
            .coordinateSpace(name: "graph")
            .onPreferenceChange(PortAnchorKey.self) { portAnchors in
                self.calcPortAnchors(portAnchors, geometryProxy: geom)
            }
            .overlayPreferenceValue(PortAnchorKey.self) { portAnchors in
                self.calcOverlayPaths(portAnchors, geometryProxy: geom)
            }
            .overlay
            {
                // Marquee selection rectangle
                let opacity = self.marqueeRect == .zero ? 0.0 : 1.0
                
                Rectangle()
                    .fill(Color.accentColor.opacity(0.1))
                    .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1))
                    .frame(width: self.marqueeRect.width, height: self.marqueeRect.height)
                    .position(x: self.marqueeRect.midX, y: self.marqueeRect.midY)
                    .allowsHitTesting(false)
                    .opacity(opacity)
            }
            .focusable(true, interactions: .edit)
            .focusEffectDisabled()
            .onKeyPress(keys: self.keys() ) { keyPress in
                return self.handleKeyPress(keyPress:keyPress)
            }
#if os(macOS)
            .onDeleteCommand {
                guard self.inputFocus == .canvas else { return }

                let currentGraph = self.editingContext.currentGraph

                let selectedNodes = currentGraph.nodes.filter({ $0.isSelected })
                selectedNodes.forEach( { currentGraph.delete(node: $0) } )
            }
#endif
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in

                        self.calcMarqueeDragChanged(forValue: value,
                                                    currentGraph: self.editingContext.currentGraph,
                                                    canvasSize: geom.size)
                    }
                    .onEnded { _ in
                        self.marqueeRect = .zero
                        self.preMarqueeSelection = []
                    }
            )
            
            .onTapGesture {
                self.inputFocus = .canvas
                self.editingContext.currentGraph.deselectAllNodes()
            }
            .onDrop(of: [.nodeRegistryItem, .fileURL], isTargeted: nil) { providers, location in
                self.handleDrop(providers: providers, location: location, canvasSize: geom.size)
            }
            .id(self.editingContext.currentGraph.shouldUpdateConnections)
           
        }
    }

    // MARK: - Drag Helper Functions
    
    private func calcMarqueeDragChanged(forValue value:DragGesture.Value, currentGraph graph:Graph, canvasSize:CGSize)
    {
        self.inputFocus = .canvas
        
        if self.marqueeRect == .zero
        {
            // Starting a new marquee
            if NSEvent.modifierFlags.contains(.shift)
            {
                self.preMarqueeSelection = Set(graph.nodes.filter(\.isSelected).map(\.id))
            }
            else
            {
                preMarqueeSelection = []
                graph.deselectAllNodes()
            }
        }
        
        let start = value.startLocation
        
        let origin = CGPoint( x: min(start.x, value.location.x),
                              y: min(start.y, value.location.y) )
        
        let size = CGSize(width: abs(value.location.x - start.x),
                          height: abs(value.location.y - start.y))
        
        self.marqueeRect = CGRect(origin: origin, size: size)
        
        // Convert marquee to node-offset space (origin at canvas centre)
        let marqueeInNodeSpace = CGRect(
            x: origin.x - canvasSize.width / 2,
            y: origin.y - canvasSize.height / 2,
            width: size.width,
            height: size.height
        )
        
        // Select nodes whose bounds intersect the marquee,
        // preserving pre-existing selection when shift is held
        for node in graph.nodes
        {
            let origin = CGPoint( x: node.offset.width - node.nodeSize.width / 2,
                                  y: node.offset.height - node.nodeSize.height / 2 )
            
            let nodeRect = CGRect( origin: origin,
                                   size: node.nodeSize)
            
            let inMarquee = nodeRect.intersects(marqueeInNodeSpace)
            node.isSelected = inMarquee || preMarqueeSelection.contains(node.id)
        }
    }
    
    private func calcDragChanged(forValue value:DragGesture.Value, currentGraph:Graph, currentNode:Node)
    {
        self.inputFocus = .canvas

        // If this drag just began, capture snapshots
        if self.activeDragAnchor == nil
        {
            self.activeDragAnchor = currentNode.id

            // If the anchor isn't selected, select only it (or expand if you prefer)
            if !currentNode.isSelected
            {
                currentGraph.selectNode(node: currentNode, expandSelection: false)
            }

            // Snapshot current offsets for all selected nodes
            self.initialOffsets = Dictionary(uniqueKeysWithValues:currentGraph.nodes
                .filter { $0.isSelected }
                .map { ($0.id, $0.offset) }
            )

            // Mark dragging (optional)
            currentGraph.nodes.filter { $0.isSelected }.forEach { $0.isDragging = true }
        }

        let t = value.translation
        // Apply translation relative to snapshot
        currentGraph.nodes.filter { $0.isSelected }.forEach { n in
            if let base = initialOffsets[n.id] {
                n.offset = base + t
            }
        }
    }

    private func calcDragEnded(currentGraph:Graph)
    {
        let selectedNodes = currentGraph.nodes.filter { $0.isSelected }

        currentGraph.undoManager?.beginUndoGrouping()

        for node in selectedNodes
        {
            if let offset = initialOffsets[node.id]
            {
                currentGraph.undoManager?.registerUndo(withTarget: node) {

                    let cachedOffset = $0.offset

                    // This registers a redo - as an undo
                    // https://nilcoalescing.com/blog/HandlingUndoAndRedoInSwiftUI/
                    currentGraph.undoManager?.registerUndo(withTarget: node) { $0.offset = cachedOffset
                    }

                    $0.offset = offset
                }
            }
        }

        currentGraph.undoManager?.endUndoGrouping()

        currentGraph.undoManager?.setActionName("Move Nodes")

        selectedNodes.forEach { $0.isDragging = false }
        self.activeDragAnchor = nil

        self.initialOffsets.removeAll()
    }
    
    // MARK: - Drop Helpers

    // FIXME: NSItemProvider load callbacks run on an arbitrary queue. Graph/Node are not
    // thread-safe and have no actor isolation, so the addNode calls below rely on AppKit
    // happening to deliver on main. If Fabric adopts Swift 6 strict concurrency or
    // @MainActor isolation, these callbacks will need explicit main-thread dispatch.

    private func handleDrop(providers: [NSItemProvider], location: CGPoint, canvasSize: CGSize) -> Bool
    {
        let currentGraph = self.editingContext.currentGraph

        // Try node registry drag from sidebar first
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.nodeRegistryItem.identifier)
        {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.nodeRegistryItem.identifier) { data, error in
                guard let data = data,
                      let dragData = try? JSONDecoder().decode(NodeRegistryDragData.self, from: data),
                      let wrapper = NodeRegistry.shared.availableNodes.first(where: { $0.id == dragData.wrapperID })
                else {
                    print("GraphCanvas: registry drag decode failed: \(error?.localizedDescription ?? "unknown")")
                    return
                }

                do {
                    let node = try wrapper.initializeNode(context: currentGraph.context)
                    node.offset = CGSize(width: location.x - canvasSize.width / 2.0 - node.nodeSize.width / 2.0,
                                         height: location.y - canvasSize.height / 2.0 - node.nodeSize.height / 2.0)
                    currentGraph.addNode(node)
                }
                catch {
                    print("GraphCanvas: failed to create node from registry drag: \(error)")
                }
            }
            return true
        }

        // Fall back to file drop from Finder
        return self.handleFileDrop(providers: providers, location: location, canvasSize: canvasSize)
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
                      let nodeClass = NodeRegistry.shared.dropTargetNodeClass(for: contentType)
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

    // MARK: - Key Press Functions

    private func keys() -> Set<KeyEquivalent>
    {
        return [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .space, .escape, .deleteForward]
    }
    
    private func handleKeyPress(keyPress:KeyPress) -> KeyPress.Result
    {
        guard self.inputFocus == .canvas else { return .ignored }
        if renamingNodeID != nil { return .ignored }

        switch keyPress.key
        {
        case .upArrow:
            print("up arrow")
            self.editingContext.currentGraph.selectNextNode(inDirection: .Up, expandSelection: keyPress.modifiers.contains(.shift))

        case .downArrow:
            print("down arrow")
            self.editingContext.currentGraph.selectNextNode(inDirection: .Down, expandSelection: keyPress.modifiers.contains(.shift))

        case .leftArrow:
            print("left arrow")
            self.editingContext.currentGraph.selectNextNode(inDirection: .Left, expandSelection: keyPress.modifiers.contains(.shift))

        case .rightArrow:
            print("right arrow")
            self.editingContext.currentGraph.selectNextNode(inDirection: .Right, expandSelection: keyPress.modifiers.contains(.shift))

        case .escape:
            self.editingContext.currentGraph.deselectAllNodes()

        case .deleteForward:
            let currentGraph = self.editingContext.currentGraph
            let selectedNodes = currentGraph.nodes.filter({ $0.isSelected })
            selectedNodes.forEach( { currentGraph.delete(node: $0) } )

        default:
            return .ignored
        }

        return .handled
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder private func contextMenu(forNode currentNode:Node, currentGraph:Graph) -> some View
    {
        Menu("Selection")
        {
            Button {
                currentGraph.selectAllNodes()
            } label : {
                Text("Select All Nodes")
            }
            
            Button {
                currentGraph.deselectAllNodes()
                currentGraph.selectUpstreamNodes(fromNode: currentNode)
                
            } label : {
                Text("Select All Upstream Nodes")
            }
            
            Button {
                currentGraph.deselectAllNodes()
                currentGraph.selectDownstreamNodes(fromNode: currentNode)
                
            } label : {
                Text("Select All Downstream Nodes")
            }
            
            Menu("Embed Selection In...") {
                
                let embedClasses = [SubgraphNode.self, IteratorNode.self, EnvironmentNode.self, DeferredSubgraphNode.self]
                
                ForEach (0 ..< embedClasses.count, id:\.self) { embedClassIndex in
                    let embedClass = embedClasses[embedClassIndex]
                    Button {
                        currentGraph.createSubgraphFromSelection(centeredOnNode: currentNode, usingClass: embedClass)
                        
                    } label : {
                        Text(embedClass.name)
                    }
                }
            }
        }
        
        
        Menu("Input Ports") {
            let inputPorts = currentNode.ports.filter { $0.kind == .Inlet }
            ForEach(inputPorts, id:\.id) { port in
                
                Button
                {
                    port.published = !port.published
                    
                    // Hacky!
                    currentGraph.rebuildPublishedParameterGroup()
                    
                } label: {
                    Text( port.published ?  "Unpublish Port: \(port.name)" : "Publish Port: \(port.name)" )
                }
            }
        }
        
        Menu("Output Ports") {
            let outputPorts = currentNode.ports.filter { $0.kind == .Outlet }
            
            ForEach(outputPorts, id:\.id) { port in
                
                Button {
                    
                    port.published = !port.published
                    
                    // Hacky!
                    currentGraph.rebuildPublishedParameterGroup()
                    
                } label: {
                    Text( port.published ?  "Unpublish Port: \(port.name)" : "Publish Port: \(port.name)" )
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
            let selectedNodes = currentGraph.nodes.filter { $0.isSelected }
            let nodesToCopy = selectedNodes.isEmpty ? [currentNode] : selectedNodes
            currentGraph.copyNodesToPasteboard(nodesToCopy)
        } label: {
            Text("Copy")
        }
#endif
        Button {
            let selectedNodes = currentGraph.nodes.filter { $0.isSelected }
            let nodesToDuplicate = selectedNodes.isEmpty ? [currentNode] : selectedNodes
            currentGraph.duplicateNodes(nodesToDuplicate)
        } label: {
            Text("Duplicate")
        }
    }

   // MARK: - Port / Connection Helpers

    private func calcPortAnchors(_ portAnchors:(PortAnchorKey.Value), geometryProxy geom:GeometryProxy)
    {
        var positions: [UUID: CGPoint] = [:]
        for (portID, anchor) in portAnchors {
            positions[portID] = geom[anchor]
        }

        self.editingContext.portPositions = positions
    }

    @ViewBuilder private func calcOverlayPaths(_ portAnchors:(PortAnchorKey.Value), geometryProxy geom:GeometryProxy) -> some View
    {
        let currentGraph = self.editingContext.currentGraph

        let ports = currentGraph.nodes.flatMap(\.ports)

        ForEach( ports.filter({ $0.kind == .Outlet }), id: \.id) { port in

            let connectedPorts:[Port] = port.connections.filter({ $0.kind == .Inlet })

            ForEach( connectedPorts , id: \.id) { connectedPort in

                if let sourceAnchor = portAnchors[port.id],
                   let destAnchor = portAnchors[connectedPort.id]
                {
                    let start = geom[ sourceAnchor ]
                    let end = geom[ destAnchor ]

                    let path = self.calcPathUsing(port:port, start: start, end: end)

                    path.stroke(port.backgroundColor , lineWidth: 2)
                        .contentShape(
                            path.stroke(style: StrokeStyle(lineWidth: 5))
                        )
                        .onTapGesture(count: 2)
                    {
                        port.disconnect(from:connectedPort)
                        currentGraph.shouldUpdateConnections.toggle()
                    }
                }
            }
        }

        if let sourcePortID = editingContext.dragPreviewSourcePortID,
           let targetPosition = editingContext.dragPreviewTargetPosition,
           let sourceAnchor = portAnchors[sourcePortID],
           let sourcePort = currentGraph.nodePort(forID: sourcePortID)
        {
            let start = geom[ sourceAnchor ]
            let path = self.calcPathUsing(port: sourcePort, start: start, end: targetPosition)

            path.stroke(sourcePort.backgroundColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targetPosition)
        }
    }

    private func calcPathUsing(port:Port, start:CGPoint, end:CGPoint) -> Path
    {
        let lowerBound = 5.0
        let upperBound = 10.0

        // Min 5 stem height
        let stemOffset:CGFloat =  self.clamp( self.dist(p1: start, p2:end) / 4.0, lowerBound: lowerBound, upperBound: upperBound) /*min( max(5, self.dist(p1: start, p2:end)), 40 )*/

        switch port.direction
        {
        case .Vertical:
            let stemHeight:CGFloat = self.clamp( abs( end.y - start.y) / 4.0 , lowerBound: lowerBound, upperBound: upperBound)

            let start1:CGPoint = CGPoint(x: start.x,
                                         y: start.y + stemHeight)

            let end1:CGPoint = CGPoint(x: end.x,
                                       y: end.y - stemHeight)

            let controlOffset:CGFloat = max(stemHeight + stemOffset, abs(end1.y - start1.y) / 2.4)
            let control1 = CGPoint(x: start1.x, y: start1.y + controlOffset )
            let control2 = CGPoint(x: end1.x, y:end1.y - controlOffset  )

            return Path { path in

                path.move(to: start )
                path.addLine(to: start1)

                path.addCurve(to: end1, control1: control1, control2: control2)

                path.addLine(to: end)
            }

        case .Horizontal:
            let stemHeight:CGFloat = self.clamp( abs( end.x - start.x) / 4.0 , lowerBound: lowerBound, upperBound: upperBound)

            let start1:CGPoint = CGPoint(x: start.x + stemHeight,
                                         y: start.y)

            let end1:CGPoint = CGPoint(x: end.x - stemHeight,
                                       y: end.y)

            let controlOffset:CGFloat = max(stemHeight + stemOffset, abs(end1.x - start1.x) / 2.4)
            let control1 = CGPoint(x: start1.x + controlOffset, y: start1.y  )
            let control2 = CGPoint(x: end1.x - controlOffset, y:end1.y   )

            return Path { path in

                path.move(to: start )
                path.addLine(to: start1)

                path.addCurve(to: end1, control1: control1, control2: control2)

                path.addLine(to: end)
            }
        }
    }

    // MARK: - Node Settings
    // Stable anchor for settings popover
    // This view intentionally does NOT read any Observable node properties in its own body
    // to avoid re-renders that dismiss the popover.
    // Node properties are only read inside the popover content
    // (which updating won't dismiss the popover).
    private struct NodeSettingsPopoverAnchor: View
    {
        let node: Node
        let nodeWidth: CGFloat
        let nodeHeight: CGFloat
        let onClose: () -> Void
        @State private var isPresented: Bool = true

        var body: some View
        {
            Rectangle()
                .fill(Color.clear)
                .frame(width: nodeWidth, height: nodeHeight)
                .popover(isPresented: $isPresented) {
                    Node.NodeSettingView(node: node)
                        .interactiveDismissDisabled(true)
                }
                .onChange(of: isPresented) { _, newValue in
                    if !newValue
                    {
                        onClose()
                    }
                }
        }
    }

    private func sychronizeSettingsFor(node currentNode:Node, show:Bool)
    {
        if show && currentNode.providesSettingsView()
        {
            self.inputFocus = .nodeSettings

            // Snapshot node into stable list
            if !settingsEntries.contains(where: { $0.id == currentNode.id })
            {
                settingsEntries.append((
                    id: currentNode.id,
                    node: currentNode,
                    width: currentNode.nodeSize.width,
                    height: currentNode.nodeSize.height,
                    offset: currentNode.offset
                ))
            }
        }
        else if !show
        {
            // Remove from stable list when showSettings becomes false
            settingsEntries.removeAll { $0.id == currentNode.id }
            if settingsEntries.isEmpty
            {
                self.inputFocus = .canvas
            }
        }

    }

    
    // MARK: - Misc Helpers
    private func clamp(_ x:CGFloat, lowerBound:CGFloat, upperBound:CGFloat) -> CGFloat
    {
        return max(min(x, upperBound), lowerBound)
    }

    private func dist(p1:CGPoint, p2:CGPoint) -> CGFloat
    {
        let distance = hypot(p1.x - p2.x, p1.y - p2.y)
        return distance
    }
}
