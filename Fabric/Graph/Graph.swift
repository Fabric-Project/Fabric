//
//  NodeGraph.swift
//  v
//
//  Created by Anton Marini on 2/1/25.
//
import SwiftUI
import Satin
internal import AnyCodable

@Observable public class Graph : Codable, Identifiable, Hashable, Equatable
{
    public enum Version : Codable
    {
        case alpha1
        case beta
    }
    
    static let currentVersion = Version.beta

    // Diagnostic types (DroppedPortStateDiagnostic, DroppedConnectionDiagnostic,
    // MissingNodeDiagnostic) and the recording functions that populate the
    // arrays below live in Graph+SerializationDiagnostics.swift.

    public static func == (lhs: Graph, rhs: Graph) -> Bool
    {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
    
    public let id:UUID
    public let version: Graph.Version
    @ObservationIgnored public let context:Context
    @ObservationIgnored public weak var undoManager: UndoManager?

    /// Directory against which scheme-less file-picker values resolve.
    @ObservationIgnored public private(set) var fileReferenceBaseURL: URL?

    public private(set) var nodes: [Node]
    public private(set) var notes: [Note]
    public private(set) var connections: [Connection] = []

    /// NodeViewModels shadow the nodes array 1-to-1. Always created/destroyed
    /// in lockstep with addNode / delete so the array is safe to force-index.
    /// @ObservationIgnored: dict key mutations must not trigger SwiftUI re-renders.
    /// Individual ViewModel properties are @Observable themselves, so changes to
    /// isSelected / offset / etc. still propagate. The ForEach is driven solely by
    /// the `nodes` array; since ViewModel insertion precedes nodes.append and
    /// ViewModel removal follows nodes.removeAll, the invariant is always intact
    /// by the time SwiftUI evaluates the ForEach body.
    @ObservationIgnored private var nodeViewModels: [UUID: NodeViewModel] = [:]

    /// Nodes that are currently selected (as tracked by their NodeViewModels).
    public var selectedNodes: [Node] {
        nodes.filter { nodeViewModels[$0.id]?.isSelected == true }
    }

    /// Mirrors GraphRenderer's per-node execute guard (isDirty || Consumer || Provider):
    /// a graph containing time-based Provider or Consumer nodes always needs another
    /// pass even when every node is clean, otherwise a Processor-mode SubgraphNode
    /// (whose isDirty is this property) is skipped by its parent after the first frame
    /// and e.g. a movie inside it freezes.
    var needsExecution:Bool {
        self.nodes.contains { node in
            node.isDirty
                || node.nodeExecutionMode == .Provider
                || node.nodeExecutionMode == .Consumer
        }
    }
    
    var scene:Object
    
    var renderables: [Satin.Renderable] {
        let allNodes = self.nodes
        
        let renderableNodes:[BaseObjectNode] = allNodes.compactMap{ $0 as? BaseObjectNode } //.compactMap( { $0 as? BaseRenderableNode })
            
        return renderableNodes.compactMap { $0.getObject() as? Satin.Renderable }
    }
    
    // Fix for #103 - connection/topology changes trigger syncNodesToScene() inside of `GraphRenderer`.
    @ObservationIgnored private var pendingConnectionSceneSync = false
    public private(set) var connectionRevision = 0
    internal private(set) var connectionTopologyGeneration = 0
    internal private(set) var executionTopologyGeneration = 0
    @ObservationIgnored private var connectionTopologyBatchDepth = 0
    @ObservationIgnored private var hasPendingBatchedConnectionTopologyChange = false

    /// Nodes whose membership, connections or published ports changed since
    /// GraphRenderer last reviewed their lifecycle. Holding them strongly keeps
    /// removed nodes alive until the renderer retires them. Both are keyed by
    /// the node object, not its id, which Node's equality uses: a node put in
    /// place of another under the same id is a different node to start and stop.
    @ObservationIgnored private var nodesAwaitingLifecycleReview: [ObjectIdentifier: Node] = [:]
    @ObservationIgnored private var nodesWithPublishedPortsAtLastReview: [ObjectIdentifier: Node] = [:]
    @ObservationIgnored internal private(set) var subgraphNodes: [SubgraphNode] = []

    /// Populated once at decode; empty for graphs built programmatically.
    @ObservationIgnored public private(set) var droppedPortStateDiagnostics: [DroppedPortStateDiagnostic] = []

    /// Populated once at decode; empty for graphs built programmatically.
    @ObservationIgnored public private(set) var droppedConnectionDiagnostics: [DroppedConnectionDiagnostic] = []

    /// Populated once at decode; empty for graphs built programmatically.
    @ObservationIgnored public private(set) var missingNodeDiagnostics: [MissingNodeDiagnostic] = []

    @ObservationIgnored private var cachedPublishedOutputPortsRevision: Int?
    @ObservationIgnored private var cachedPublishedOutputPorts: [Port] = []
  
    @ObservationIgnored weak var lastNode:(Node)? = nil

    public func markConnectionTopologyChanged()
    {
        if connectionTopologyBatchDepth > 0
        {
            hasPendingBatchedConnectionTopologyChange = true
            return
        }

        connectionRevision += 1
        pendingConnectionSceneSync = true
        connectionTopologyGeneration += 1
    }

    public func markExecutionTopologyChanged()
    {
        executionTopologyGeneration += 1
    }

    public func markConnectionsChanged()
    {
        markConnectionTopologyChanged()
    }

    func consumePendingConnectionSceneSync() -> Bool
    {
        let shouldSyncScene = pendingConnectionSceneSync
        pendingConnectionSceneSync = false
        return shouldSyncScene
    }

    internal func markNodeForLifecycleReview(_ node: Node)
    {
        nodesAwaitingLifecycleReview[ObjectIdentifier(node)] = node
    }

    internal func takeNodesAwaitingLifecycleReview() -> [Node]
    {
        let reviewedNodes = Array(nodesAwaitingLifecycleReview.values)
        nodesAwaitingLifecycleReview.removeAll(keepingCapacity: true)
        return reviewedNodes
    }

    private func nodeMembershipDidChange(_ node: Node)
    {
        if let subgraphNode = node as? SubgraphNode
        {
            subgraphNodes.removeAll { $0 === subgraphNode }
            if subgraphNode.graph === self { subgraphNodes.append(subgraphNode) }
        }
        markNodeForLifecycleReview(node)
    }

    public let publishedParameterGroup:ParameterGroup = ParameterGroup("Published")

    /// The SubgraphNode whose sub graph this is; nil for a document's root
    /// graph. What an undo step puts back in the containing graph, the wires
    /// onto a proxy and the proxy's own publishing, is reached through it.
    @ObservationIgnored public internal(set) weak var ownerNode: SubgraphNode?

    /// Called when the set of published ports changes. SubgraphNode uses
    /// this to rebuild its proxy ports without polling.
    @ObservationIgnored var onPublishedPortsChanged: (() -> Void)?

    /// Called when this graph resolves to a different scene camera. A
    /// SubgraphNode propagates the change to its containing graph so camera
    /// selection remains cached across the complete nested graph hierarchy.
    @ObservationIgnored var onCameraSelectionChanged: (() -> Void)?

    enum CodingKeys : String, CodingKey
    {
        case id
        case version
        case requiredPlugins
        case nodeMap
        case portConnectionMap
        case connections
        case notes
    }
    
    public init(context:Context, fileReferenceBaseURL: URL? = nil)
    {
        self.scene = Object(context: context)
        print("Init Graph")
        self.id = UUID()
        self.version = .beta
        self.context = context
        self.fileReferenceBaseURL = fileReferenceBaseURL?.standardizedFileURL
        self.nodes = []
        self.notes = []
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.context = decodeContext.documentContext
        self.fileReferenceBaseURL = decodeContext.fileReferenceBaseURL?.standardizedFileURL

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.version = try container.decode(Graph.Version.self, forKey: .version)

        self.nodes = []
        self.scene = Object(context: context)

        self.notes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
        let requiredPlugins = try container.decodeIfPresent([PluginRequirement].self, forKey: .requiredPlugins) ?? []
        let nodeRegistry = try NodeRegistry.shared
        try nodeRegistry.validatePluginRequirements(requiredPlugins)

        // For Subgraphs - we capture and reset state
        // this is needed for ProxyPorts which expose inner graph ports
        // to parent graph ports
        // we leverage the decode context current graph to be the subgraph
        // we we need to 'pop it' - Anton
        let previousGraph = decodeContext.currentGraph

        decodeContext.currentGraph = self

        defer
        {
            decodeContext.currentGraph = previousGraph
        }
        
        // get a single value container
        var nestedContainer = try container.nestedUnkeyedContainer( forKey: .nodeMap)
        
        // this is stupid but works!
        // We make a new encoder to re-encode the data
        // we pass to the intospected types class decoder based initialier
        // since they all conform to NodeProtocol we can do this
        // this is better than the alternative switch for each class..
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        while !nestedContainer.isAtEnd
        {
            let anyCodableMap = try nestedContainer.decode(AnyCodableMap.self)

            let nodeID = Self.qualifiedNodeID(fromSerializedType: anyCodableMap.type)

            do {
                if let nodeClass = nodeRegistry.nodeClass(pluginID: nodeID.pluginID, nodeID: nodeID.nodeID)
                {
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(nodeClass, from: jsonData)

                    self.addNode(node)
                }
                else if anyCodableMap.type == "BaseImageNode"
                {
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseImageNode.self, from: jsonData)
                    self.addNode(node)
                }
                
                else if anyCodableMap.type == "LiveEffectNode"
                {
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    
                    let decoder = JSONDecoder()
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(LiveImageNode.self, from: jsonData)
                    self.addNode(node)
                }
                
                // MARK: - Deprecated Node Types -> BaseImageNode
                else if anyCodableMap.type == "BaseEffectThreeChannelNode"
                {
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseImageNode.self, from: jsonData)

                    self.addNode(node)
                }
                else if anyCodableMap.type == "BaseEffectTwoChannelNode"
                {
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseImageNode.self, from: jsonData)

                    self.addNode(node)
                }
                else if anyCodableMap.type == "BaseEffectNode"
                {
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    
                    let decoder = JSONDecoder()
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseImageNode.self, from: jsonData)

                    self.addNode(node)
                }

                else if anyCodableMap.type == "BaseGeneratorNode"
                {
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    
                    let decoder = JSONDecoder()
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseImageNode.self, from: jsonData)

                    self.addNode(node)
                }
               
                else
                {
                    self.missingNodeDiagnostics.append(
                        self.makeMissingNodeDiagnostic(serializedType: anyCodableMap.type,
                                                       reason: .typeNotRegistered,
                                                       summary: "Could not find \(nodeID.nodeID)")
                    )
                }
            }
            catch
            {
                self.missingNodeDiagnostics.append(
                    self.makeMissingNodeDiagnostic(serializedType: anyCodableMap.type,
                                                   reason: .decodeFailed,
                                                   summary: "Could not load \(nodeID.nodeID): \(error.localizedDescription)")
                )
            }
        }
        
        // Node inits (including their dynamic-port rebuilds) are done; end
        // each node's hydration window. Whatever state remains unconsumed
        // matched nothing the code declares, and closing the window here means
        // ports added later in the document's life cannot resurrect stale
        // snapshot state.
        self.droppedPortStateDiagnostics = self.makeDroppedPortStateDiagnostics()

        let decodedConnections = try container.decodeIfPresent([Connection].self, forKey: .connections)

        // Restoring a wire resolves both its endpoints, and reporting a dropped
        // one resolves them again; nodePort(forID:) is a linear scan of every
        // port in the document, so index once and read from that. Mirror what
        // it scans, subgraph proxy ports included.
        let portsByID: [UUID: Port] = self.nodes.reduce(into: [:]) { index, node in
            for port in node.ports { index[port.id] = port }
        }

        // The legacy map holds every connection under both endpoints; report
        // each dropped one once, whichever side surfaces it first.
        var reportedDroppedPairs = Set<Set<UUID>>()

        func reportDroppedConnection(from portID: UUID, to otherPortID: UUID, reason: DroppedConnectionDiagnostic.Reason)
        {
            guard let diagnostic = self.makeDroppedConnectionDiagnostic(from: portID,
                                                                        to: otherPortID,
                                                                        reason: reason,
                                                                        portsByID: portsByID,
                                                                        reportedPairs: &reportedDroppedPairs)
            else { return }

            self.droppedConnectionDiagnostics.append(diagnostic)
        }

        if let decodedConnections
        {
            // Attach bypasses validatedConnect, so the endpoint and type
            // checks (and their diagnostics) live here.
            for connection in decodedConnections
            {
                guard let outlet = portsByID[connection.outletPortID],
                      let inlet = portsByID[connection.inletPortID]
                else
                {
                    reportDroppedConnection(from: connection.outletPortID, to: connection.inletPortID, reason: .missingEndpoint)
                    continue
                }

                guard outlet.canConnect(to: inlet) else
                {
                    reportDroppedConnection(from: connection.outletPortID, to: connection.inletPortID, reason: .incompatibleTypes)
                    continue
                }

                attachConnection(connection, outlet: outlet, inlet: inlet)
            }
        }
        else
        {
            let portMap = try container.decodeIfPresent([UUID:[UUID]].self, forKey: .portConnectionMap) ?? [:]

            for portID in portMap.keys
            {
                let portConnections = portMap[portID] ?? []

                guard let port = portsByID[portID] else
                {
                    for connectedPortID in portConnections
                    {
                        reportDroppedConnection(from: portID, to: connectedPortID, reason: .missingEndpoint)
                    }
                    continue
                }

                for connectedPortID in portConnections
                {
                    guard let connectedPort = portsByID[connectedPortID] else
                    {
                        reportDroppedConnection(from: portID, to: connectedPortID, reason: .missingEndpoint)
                        continue
                    }

                    guard port.canConnect(to: connectedPort) else
                    {
                        reportDroppedConnection(from: portID, to: connectedPortID, reason: .incompatibleTypes)
                        continue
                    }

                    guard port.kind == .Outlet else { continue }
                    let connection = Connection(outletPortID: port.id, inletPortID: connectedPort.id)
                    attachConnection(connection, outlet: port, inlet: connectedPort)
                }
            }
        }

        self.rebuildPublishedParameterGroup()
    }

    deinit
    {
        self.nodes.forEach { $0.teardown() }
        print("Deinit Graph: \(self.id)")
    }
    
    public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.id, forKey: .id)
        try container.encode(Self.currentVersion, forKey: .version)
        let requiredPlugins = try self.requiredPlugins(for: self.nodes)
        try container.encode(requiredPlugins, forKey: .requiredPlugins)

        let nodeMap:[ AnyCodableMap ] = try self.nodes.map {
            let qualifiedNodeID = try self.qualifiedNodeID(for: type(of: $0))
            return AnyCodableMap(type: qualifiedNodeID.description,
                                 value: AnyCodable($0))
        }
        
        try container.encode(self.notes, forKey: .notes)
        
        try container.encode( nodeMap, forKey: .nodeMap)
        try container.encode(self.connections.filter { connection in
            self.nodePort(forID: connection.outletPortID) != nil &&
            self.nodePort(forID: connection.inletPortID) != nil
        }, forKey: .connections)
    }
 
    //MARK: - Undo -

    /// Registers the undo step for an edit made in this graph. Every edit
    /// registers through here, so it is the one place that sees an edit made
    /// in a graph, wherever in the editor it was made.
    ///
    /// The step is handed this graph as the document holds it when the step
    /// runs, found from the root by the ids of the subgraph nodes on the way
    /// down, and finds what it acts on there by id. It holds ids and values,
    /// never this graph's nodes, ports, wires or notes: by the time it runs,
    /// something may have put another object in place of one under the same
    /// id. What it brings back from outside the graph, a deleted node, it
    /// holds.
    ///
    /// Steps record on effectiveUndoManager.
    public func registerUndo(_ handler: @escaping (Graph) -> Void)
    {
        guard let undoManager = self.effectiveUndoManager else { return }
        let location = UndoLocation(of: self)
        // The step holds the location: an undo manager does not keep its targets.
        undoManager.registerUndo(withTarget: location) { [location] _ in
            guard let graph = location.graph else { return }
            handler(graph)
        }
    }

    /// The undo manager edits made in this graph record on: its own, or the
    /// root's until the canvas gives it its own. withoutUndoRegistration(_:)
    /// suspends this one.
    internal var effectiveUndoManager: UndoManager?
    {
        self.undoManager ?? UndoLocation(of: self).root?.undoManager
    }

    /// Registers an undo step acting on `node`, a node in this graph, found
    /// again by its id; see registerUndo(_:).
    public func registerUndo<N: Node>(on node: N, _ handler: @escaping (N) -> Void)
    {
        let id = node.id
        self.registerUndo { graph in
            guard let node = graph.node(forID: id) as? N else { return }
            handler(node)
        }
    }

    /// Records a change already made to `parameter`'s value, from `previous`,
    /// as an undo step. The parameter is a port's, on a node in this graph or
    /// in a graph inside it, as a published parameter shown further up is.
    public func registerValueChange<Value: Codable & Equatable>(of parameter: GenericParameter<Value>,
                                                               from previous: Value,
                                                               label: String)
    {
        guard let owner = self.graph(holdingPortOf: parameter) else { return }
        let portID = parameter.id
        let current = parameter.value
        owner.registerUndo { graph in
            guard let parameter = graph.nodePort(forID: portID)?.parameter as? GenericParameter<Value> else { return }
            parameter.value = previous
            graph.registerValueChange(of: parameter, from: current, label: label)
        }
        owner.undoManager?.setActionName("Change \(label)")
    }

    /// The graph, this one or one inside it, with the port `parameter` is
    /// the parameter of. A proxy shares its inner port's parameter, and is
    /// passed over for it.
    private func graph(holdingPortOf parameter: any Parameter) -> Graph?
    {
        let holdsPort = self.nodes.contains { node in
            node.ports.contains { $0.parameter === parameter && !($0 is any ProxyPortProtocol) }
        }
        if holdsPort { return self }
        for case let subgraphNode as SubgraphNode in self.nodes
        {
            if let graph = subgraphNode.subGraph.graph(holdingPortOf: parameter) { return graph }
        }
        return nil
    }

    /// Where an undo step acts: the root graph, and the ids of the subgraph
    /// nodes from it down to the graph the edit was made in.
    private final class UndoLocation
    {
        private(set) weak var root: Graph?
        private let path: [UUID]

        init(of graph: Graph)
        {
            var path: [UUID] = []
            var root = graph
            while let owner = root.ownerNode, let parent = owner.graph
            {
                path.append(owner.id)
                root = parent
            }
            self.root = root
            self.path = path.reversed()
        }

        var graph: Graph?
        {
            self.path.reduce(self.root) { graph, id in (graph?.node(forID: id) as? SubgraphNode)?.subGraph }
        }
    }

    //MARK: - Notes API -

    public func addNote(_ note: Note)
    {
        self.insertNote(note, at: self.notes.endIndex)
        undoManager?.setActionName("Add Note")
    }

    public func deleteNote(_ note:Note)
    {
        self.deleteNote(id: note.id)
    }

    private func deleteNote(id: UUID)
    {
        guard let index = self.notes.firstIndex(where: { $0.id == id }) else { return }
        let note = self.notes.remove(at: index)

        self.registerUndo { graph in
            graph.insertNote(note, at: index)
            graph.undoManager?.setActionName("Delete Note")
        }
        undoManager?.setActionName("Delete Note")
    }

    private func insertNote(_ note: Note, at index: Int)
    {
        guard !self.notes.contains(where: { $0.id == note.id }) else { return }
        self.notes.insert(note, at: min(index, self.notes.endIndex))
        let id = note.id
        self.registerUndo { $0.deleteNote(id: id) }
    }

    /// Records an edit already made to `note`'s text or frame, from the text
    /// and frame it had before, as one undo step.
    public func registerNoteEdit(_ note: Note, previousText: String, previousRect: CGRect)
    {
        let id = note.id
        let text = note.note
        let rect = note.rect
        guard text != previousText || rect != previousRect else { return }

        self.registerUndo { graph in
            guard let note = graph.notes.first(where: { $0.id == id }) else { return }
            note.note = previousText
            note.rect = previousRect
            graph.registerNoteEdit(note, previousText: text, previousRect: rect)
        }
        undoManager?.setActionName("Edit Note")
    }
    
    //MARK: - Nodes API -
    
    /// Initialize a node from a wrapper and add it to this graph.
    /// The node receives no special positioning — use
    /// `GraphCanvasContext.addNode(_:)` for interactive placement.
    public func addNode(_ node: NodeClassWrapper) throws
    {
        let node = try node.initializeNode(context: self.context)
        self.addNode(node)
    }

    /// Add a node to this graph. The node's offset is taken as-is — callers are
    /// responsible for positioning (see `GraphCanvasContext.addNode` for
    /// interactive placement with scroll-offset and rapid-add staggering).
    public func addNode(_ node:Node)
    {
        print("Graph: \(self.id) Add Node", node)
        self.maybeAddNodeToScene(node)

        // Create the ViewModel before appending so it is always present
        // when SwiftUI re-evaluates the ForEach triggered by nodes.append.
        self.nodeViewModels[node.id] = NodeViewModel(node: node)

        self.nodes.append(node)
        node.graph = self
        self.nodeMembershipDidChange(node)

        if let subgraphNode = node as? SubgraphNode
        {
            subgraphNode.subGraph.updateFileReferenceBaseURL(self.fileReferenceBaseURL)
        }

        self.registerUndo(on: node) { node in
            node.graph?.delete(node: node)
        }

        self.undoManager?.setActionName("Add Node")
        self.markConnectionsChanged()

        self.updateCameraSelection(afterAdding: node)
        self.rebuildPublishedParameterGroup()
    }

    /// Updates the saved-document directory used by relative file paths and
    /// invalidates every file-picker node so it reloads at the new location.
    /// This propagates through nested subgraphs.
    public func updateFileReferenceBaseURL(_ url: URL?)
    {
        let standardizedURL = url?.standardizedFileURL
        guard self.fileReferenceBaseURL != standardizedURL else { return }

        self.fileReferenceBaseURL = standardizedURL

        for node in self.nodes
        {
            var hasFileReference = false

            for port in node.ports where port.parameter?.controlType == .filepicker
            {
                port.valueDidChange = true
                hasFileReference = true
            }

            if hasFileReference
            {
                node.markDirty()
            }

            if let subgraphNode = node as? SubgraphNode
            {
                subgraphNode.subGraph.updateFileReferenceBaseURL(standardizedURL)
            }
        }
    }

    /// Rewrites static file references at save time, preserving their targets
    /// when the document acquires a location or is saved to a different directory.
    public func rewriteFileReferences(relativeTo directoryURL: URL?)
    {
        for node in self.nodes
        {
            // File-picker metadata also covers directory and model loaders.
            for port in node.ports
            {
                guard let filePort = port as? ParameterPort<String>,
                      filePort.parameter?.controlType == .filepicker,
                      filePort.connectedOutlets.isEmpty,
                      let reference = filePort.value,
                      let sourceURL = self.resolveFileReference(reference)
                else { continue }

                let rewrittenReference = DocumentFileReference.reference(for: sourceURL, relativeTo: directoryURL)
                if rewrittenReference != reference
                {
                    filePort.value = rewrittenReference
                }
            }

            if let subgraphNode = node as? SubgraphNode
            {
                subgraphNode.subGraph.rewriteFileReferences(relativeTo: directoryURL)
            }
        }

        self.updateFileReferenceBaseURL(directoryURL)
    }

    /// Resolves an absolute file URL, absolute filesystem path, or path relative
    /// to the directory containing this graph's document.
    public func resolveFileReference(_ reference: String,
                                     directoryHint: URL.DirectoryHint = .inferFromPath) -> URL?
    {
        DocumentFileReference.resolve(reference,
                                      relativeTo: self.fileReferenceBaseURL,
                                      directoryHint: directoryHint)
    }

    
    
    public func delete(node:Node, disconnect:Bool = true)
    {
        guard nodes.contains(where: { $0 === node }) else { return }

        let savedOffset = node.offset
        let nodePortIDs = Set(node.ports.map(\.id))
        let savedConnections = connections.filter {
            nodePortIDs.contains($0.outletPortID) || nodePortIDs.contains($0.inletPortID)
        }
        let savedWires = savedConnections.map(Wire.init)

        withoutUndoRegistration {
            if disconnect
            {
                for connection in savedConnections {
                    self.disconnect(connection)
                }
            }

            self.maybeDeleteNodeFromScene(node)
            self.nodes.removeAll { $0.id == node.id }
            node.graph = nil
            self.nodeMembershipDidChange(node)
            // Remove ViewModel after removing from nodes so any in-flight
            // ForEach evaluation still finds it.
            self.nodeViewModels[node.id] = nil
        }

        self.registerUndo { graph in
            graph.restoreDeletedNode(node,
                                     offset: savedOffset,
                                     wires: savedWires)
        }

        self.undoManager?.setActionName("Delete Node")
        self.markConnectionsChanged()

        self.updateCameraSelection()
        self.rebuildPublishedParameterGroup()
    }

    private func restoreDeletedNode(_ node: Node,
                                    offset: CGSize,
                                    wires: [Wire])
    {
        guard self.node(forID: node.id) == nil else { return }

        withoutUndoRegistration {
            node.offset = offset
            nodeViewModels[node.id] = NodeViewModel(node: node)
            nodes.append(node)
            node.graph = self
            nodeMembershipDidChange(node)
            maybeAddNodeToScene(node)

            for wire in wires {
                restore(wire)
            }

            node.markDirty()
            updateCameraSelection(afterAdding: node)
            rebuildPublishedParameterGroup()
            syncNodesToScene()
            markConnectionsChanged()
        }

        self.registerUndo(on: node) { node in
            node.graph?.delete(node: node)
        }
        undoManager?.setActionName("Delete Node")
    }
    
    public func node(forID:UUID) -> Node?
    {
        return self.nodes.first(where: { $0.id == forID })
    }
    
    // MARK: - Node View API -

    /// Returns the NodeViewModel for the given node.
    /// Always non-nil while the node is in this graph.
    public func viewModel(for node: Node) -> NodeViewModel
    {
        nodeViewModels[node.id]!
    }

    /// Returns the NodeViewModel when SwiftUI is evaluating transient stale
    /// references, such as connection rows from the same transaction as delete.
    public func viewModelIfPresent(for node: Node) -> NodeViewModel?
    {
        nodeViewModels[node.id]
    }
    
    public func nodePort(forID:UUID) -> Port?
    {
        let allPorts = self.nodes.flatMap(\.ports)
        return allPorts.first(where: { $0.id == forID })
    }

    private func recoverableGraphError(_ kind: FabricErrorKind.Graph,
                                       message: String) -> FabricError
    {
        FabricError(.graph(kind), severity: .recoverable, message: message)
    }

    private func connectionEndpointsBelongToGraph(outlet: Port, inlet: Port) -> Bool
    {
        guard outlet.node?.graph === self,
              inlet.node?.graph === self,
              nodePort(forID: outlet.id) === outlet,
              nodePort(forID: inlet.id) === inlet,
              outlet.kind == .Outlet,
              inlet.kind == .Inlet,
              outlet.canConnect(to: inlet)
        else { return false }

        return true
    }
    
    // MARK: - Connection API -

    @discardableResult
    public func connect(_ outlet: Port, to inlet: Port) -> Connection?
    {
        guard connectionEndpointsBelongToGraph(outlet: outlet, inlet: inlet) else { return nil }

        if let existing = connections.first(where: {
            $0.outletPortID == outlet.id && $0.inletPortID == inlet.id
        }) {
            return existing
        }

        let undoManager = self.undoManager
        let replacesExistingConnection = inlet.connections.contains { $0.inletPortID == inlet.id }
        if replacesExistingConnection { undoManager?.beginUndoGrouping() }

        for existing in inlet.connections where existing.inletPortID == inlet.id && existing.graph === self {
            disconnect(existing)
        }

        let connection = Connection(outletPortID: outlet.id, inletPortID: inlet.id)
        attachConnection(connection, outlet: outlet, inlet: inlet)
        markConnectionTopologyChanged()
        outlet.sendBoxed(outlet.snapshotValue(), force: true)

        let wire = Wire(connection)
        self.registerUndo { graph in
            graph.connection(matching: wire).map { graph.disconnect($0) }
        }
        undoManager?.setActionName("Connect Ports")

        if replacesExistingConnection { undoManager?.endUndoGrouping() }
        return connection
    }

    @discardableResult
    public func disconnect(_ outlet: Port, from inlet: Port) -> Bool
    {
        guard connectionEndpointsBelongToGraph(outlet: outlet, inlet: inlet) else { return false }

        guard let connection = connections.first(where: {
            $0.outletPortID == outlet.id && $0.inletPortID == inlet.id
        }) else { return false }

        return disconnect(connection)
    }

    @discardableResult
    public func disconnect(_ connection: Connection) -> Bool
    {
        guard connections.contains(where: { $0 === connection }),
              connection.graph === self,
              connection.outletPort?.node?.graph === self,
              connection.inletPort?.node?.graph === self,
              let outlet = connection.outletPort,
              let inlet = connection.inletPort
        else { return false }

        inlet.sendBoxed(nil, force: true)
        detachConnection(connection, outlet: outlet, inlet: inlet)
        markConnectionTopologyChanged()

        let wire = Wire(connection)
        self.registerUndo { graph in
            graph.restore(wire)
        }
        undoManager?.setActionName("Disconnect Ports")
        return true
    }

    public func disconnectAll(from port: Port)
    {
        guard port.node?.graph === self, nodePort(forID: port.id) === port else { return }

        let ownedConnections = port.connections.filter { $0.graph === self }
        guard !ownedConnections.isEmpty else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        for connection in ownedConnections {
            disconnect(connection)
        }
        undoManager?.setActionName("Disconnect Ports")
    }

    @discardableResult
    public func setConnection(_ connection: Connection, active: Bool) -> Bool
    {
        guard connections.contains(where: { $0 === connection }), connection.graph === self else { return false }

        guard connection.active != active else { return true }
        let previousActive = connection.active
        connection.active = active

        let wire = Wire(connection)
        self.registerUndo { graph in
            graph.connection(matching: wire).map { graph.setConnection($0, active: previousActive) }
        }
        undoManager?.setActionName(active ? "Enable Connection" : "Disable Connection")
        return true
    }

    internal func setConnections(from port: Port, active: Bool)
    {
        guard port.node?.graph === self, nodePort(forID: port.id) === port else { return }

        for connection in port.connections where connection.graph === self
        {
            connection.active = active
        }
    }

    /// A wire as an undo step holds it: by its id and the ids of the ports at
    /// its ends, which find it again whatever object stands for it then.
    internal struct Wire
    {
        let id: UUID
        let outletPortID: UUID
        let inletPortID: UUID
        let active: Bool

        init(_ connection: Connection)
        {
            self.init(id: connection.id,
                      outletPortID: connection.outletPortID,
                      inletPortID: connection.inletPortID,
                      active: connection.active)
        }

        init(id: UUID, outletPortID: UUID, inletPortID: UUID, active: Bool)
        {
            self.id = id
            self.outletPortID = outletPortID
            self.inletPortID = inletPortID
            self.active = active
        }
    }

    /// The wire in this graph between the ports `wire` joins.
    internal func connection(matching wire: Wire) -> Connection?
    {
        connections.first { $0.outletPortID == wire.outletPortID && $0.inletPortID == wire.inletPortID }
    }

    /// Puts `wire` back, under its own id, where both its ports are in this
    /// graph and nothing joins them yet.
    @discardableResult
    internal func restore(_ wire: Wire) -> Bool
    {
        if connection(matching: wire) != nil { return true }
        guard let outlet = nodePort(forID: wire.outletPortID),
              let inlet = nodePort(forID: wire.inletPortID),
              connectionEndpointsBelongToGraph(outlet: outlet, inlet: inlet),
              !connections.contains(where: { $0.inletPortID == wire.inletPortID })
        else { return false }

        let connection = Connection(id: wire.id, outletPortID: wire.outletPortID, inletPortID: wire.inletPortID, active: wire.active)
        attachConnection(connection, outlet: outlet, inlet: inlet)
        markConnectionTopologyChanged()
        outlet.sendBoxed(outlet.snapshotValue(), force: true)

        self.registerUndo { graph in
            graph.connection(matching: wire).map { graph.disconnect($0) }
        }
        return true
    }

    private func detachConnection(_ connection: Connection, outlet: Port, inlet: Port)
    {
        connections.removeAll { $0 === connection }
        outlet.connections.removeAll { $0 === connection }
        inlet.connections.removeAll { $0 === connection }
        connection.graph = nil
        connection.outletPortReference = nil
        connection.inletPortReference = nil

        if let outletNode = outlet.node, let inletNode = inlet.node {
            outletNode.didDisconnectFromNode(inletNode)
            inletNode.didDisconnectFromNode(outletNode)
            outletNode.updateConnectionTopology()
            inletNode.updateConnectionTopology()
            markNodeForLifecycleReview(outletNode)
            markNodeForLifecycleReview(inletNode)
        }
    }

    private func transferConnection(_ connection: Connection, to destination: Graph)
    {
        connections.removeAll { $0 === connection }
        if !destination.connections.contains(where: { $0 === connection }) {
            destination.connections.append(connection)
        }
        connection.graph = destination
    }

    private func rebindConnection(_ connection: Connection, replacing oldPort: Port, with newPort: Port)
    {
        oldPort.connections.removeAll { $0 === connection }
        if !newPort.connections.contains(where: { $0 === connection }) {
            newPort.connections.append(connection)
        }

        if connection.outletPortID == oldPort.id {
            connection.outletPortReference = newPort
        } else if connection.inletPortID == oldPort.id {
            connection.inletPortReference = newPort
        }

        if let oldNode = oldPort.node,
           let oppositeNode = connection.port(opposite: newPort)?.node
        {
            oldNode.didDisconnectFromNode(oppositeNode)
            oppositeNode.didDisconnectFromNode(oldNode)
            oldNode.updateConnectionTopology()
            oppositeNode.updateConnectionTopology()
            markNodeForLifecycleReview(oldNode)
        }

        if let newNode = newPort.node,
           let oppositeNode = connection.port(opposite: newPort)?.node
        {
            newNode.didConnectToNode(oppositeNode)
            oppositeNode.didConnectToNode(newNode)
            newNode.updateConnectionTopology()
            oppositeNode.updateConnectionTopology()
            markNodeForLifecycleReview(newNode)
            markNodeForLifecycleReview(oppositeNode)
        }
    }

    private func attachConnection(_ connection: Connection, outlet: Port, inlet: Port)
    {
        connection.graph = self
        connection.outletPortReference = outlet
        connection.inletPortReference = inlet

        if !connections.contains(where: { $0 === connection })
        {
            connections.append(connection)
        }

        if !outlet.connections.contains(where: { $0.id == connection.id })
        {
            outlet.connections.append(connection)
        }

        if !inlet.connections.contains(where: { $0.id == connection.id })
        {
            inlet.connections.append(connection)
        }

        if let outletNode = outlet.node,
           let inletNode = inlet.node
        {
            outletNode.didConnectToNode(inletNode)
            inletNode.didConnectToNode(outletNode)
            outletNode.updateConnectionTopology()
            inletNode.updateConnectionTopology()
            markNodeForLifecycleReview(outletNode)
            markNodeForLifecycleReview(inletNode)
        }
    }

    /// Re-binds this graph's wires onto `ports`, for a port that went away and
    /// came back under the same id, as a sub graph node's proxy does when its
    /// inner port is republished. Nothing else recovers such a wire: the id
    /// still resolves so it reads as live, while the port it points at is the
    /// old object, and `disconnect` refuses it once that object has gone.
    /// Identity, not nil-ness, is the test: whoever still holds the old port
    /// decides only when it dies, never whether the wire was left behind.
    internal func reattachConnections(to ports: [Port])
    {
        guard !ports.isEmpty, !connections.isEmpty else { return }

        let portsByID = Dictionary(ports.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for connection in connections
        {
            let currentOutlet = portsByID[connection.outletPortID]
            let currentInlet = portsByID[connection.inletPortID]
            let outletIsStale = currentOutlet != nil && connection.outletPortReference !== currentOutlet
            let inletIsStale = currentInlet != nil && connection.inletPortReference !== currentInlet

            guard outletIsStale || inletIsStale,
                  let outlet = currentOutlet ?? connection.outletPortReference,
                  let inlet = currentInlet ?? connection.inletPortReference
            else { continue }

            if outletIsStale { connection.outletPortReference?.connections.removeAll { $0 === connection } }
            if inletIsStale { connection.inletPortReference?.connections.removeAll { $0 === connection } }

            attachConnection(connection, outlet: outlet, inlet: inlet)
            outlet.sendBoxed(outlet.snapshotValue(), force: true)
        }
    }
    
    // MARK: - Publish Port API -
    /// All ports in this graph that have been published.
    public func getPublishedPorts() -> [Port]
    {
        return self.nodes.flatMap { $0.publishedPorts() }
    }

    public func publishedInputPorts() -> [Port]
    {
        return self.nodesWithPublishedInputs().flatMap { $0.publishedInputPorts() }
    }

    public func publishedOutputPorts() -> [Port]
    {
        if cachedPublishedOutputPortsRevision == connectionRevision {
            return cachedPublishedOutputPorts
        }

        cachedPublishedOutputPorts = self.nodesWithPublishedOutputs().flatMap { $0.publishedOutputPorts() }
        cachedPublishedOutputPortsRevision = connectionRevision

        return cachedPublishedOutputPorts
    }

    /// Publishes or unpublishes `port`, a port of a node in this graph, as a
    /// deliberate act rather than the rebuild that follows one. Undoable.
    ///
    /// Unpublishing takes the proxy that stood for the port in the containing
    /// graph with it, with the wires onto it, and so on up for as far as each
    /// proxy was published. Left alone the wires name a port that has gone:
    /// the port at the other end still reports itself wired, and a republish
    /// would bring them back with it. Undoing the unpublish puts each level's
    /// proxy state and wires back.
    public func setPublished(_ published: Bool, on port: Port)
    {
        guard port.published != published else { return }

        let previousName = port.publishedName
        var proxyChain: ProxyChainState?
        if !published
        {
            proxyChain = self.proxyChainState(standingFor: port)
            self.disconnectProxyChain(standingFor: port)
            port.publishedName = nil
            // Publishing named the parameter after the port's published name.
            port.parameter?.label = port.displayName
        }

        port.published = published
        self.rebuildPublishedParameterGroup()

        let portID = port.id
        self.registerUndo { graph in
            guard let port = graph.nodePort(forID: portID) else { return }
            graph.setPublished(!published, on: port)
            if let proxyChain
            {
                port.publishedName = previousName
                graph.rebuildPublishedParameterGroup()
                graph.restoreProxyChain(standingFor: port, to: proxyChain)
            }
        }
        undoManager?.setActionName(published ? "Publish Port" : "Unpublish Port")
    }

    /// Names `port`, a published port of a node in this graph, as the
    /// containing graph shows it; nil goes back to the port's own name.
    /// Undoable.
    public func setPublishedName(_ name: String?, on port: Port)
    {
        let previousName = port.publishedName
        guard previousName != name else { return }

        port.publishedName = name
        self.rebuildPublishedParameterGroup()
        self.markConnectionsChanged()

        let portID = port.id
        self.registerUndo { graph in
            graph.nodePort(forID: portID).map { graph.setPublishedName(previousName, on: $0) }
        }
        undoManager?.setActionName("Rename Port")
    }

    /// What the proxies standing for a published port hold in the graphs
    /// above: at each level, the wires onto the proxy there and the proxy's
    /// own publishing, for as far up as it is published. What a port taking
    /// its proxies with it, unpublished or removed, has an undo put back.
    internal struct ProxyChainState
    {
        struct Level
        {
            let wires: [ProxyWire]
            let published: Bool
            let publishedName: String?
        }

        let levels: [Level]
    }

    /// A wire onto a proxy, by the port at its other end: the proxy that
    /// comes back stands under the id the proxy over the same port has then.
    internal struct ProxyWire
    {
        let id: UUID
        let otherEndID: UUID
        let proxyIsInlet: Bool
        let active: Bool

        init(_ connection: Connection, onProxy proxy: Port)
        {
            self.id = connection.id
            self.proxyIsInlet = connection.inletPortID == proxy.id
            self.otherEndID = self.proxyIsInlet ? connection.outletPortID : connection.inletPortID
            self.active = connection.active
        }

        func wire(onProxy proxy: Port) -> Wire
        {
            Wire(id: id,
                 outletPortID: proxyIsInlet ? otherEndID : proxy.id,
                 inletPortID: proxyIsInlet ? proxy.id : otherEndID,
                 active: active)
        }
    }

    /// The proxy standing for `port`, a port of a node in this graph, on the
    /// subgraph node around it, with the graph that subgraph node is in.
    private func proxy(standingFor port: Port) -> (proxy: Port, parent: Graph)?
    {
        guard let owner = self.ownerNode, let parent = owner.graph,
              let proxy = owner.ports.first(where: { ($0 as? any ProxyPortProtocol)?.innerPortID == port.id })
        else { return nil }
        return (proxy, parent)
    }

    /// See ProxyChainState. `port` is a port of a node in this graph.
    internal func proxyChainState(standingFor port: Port) -> ProxyChainState
    {
        var levels: [ProxyChainState.Level] = []
        var graph = self
        var standingFor = port
        while let (proxy, parent) = graph.proxy(standingFor: standingFor)
        {
            levels.append(.init(wires: proxy.connections.map { ProxyWire($0, onProxy: proxy) },
                                published: proxy.published,
                                publishedName: proxy.publishedName))
            guard proxy.published else { break }
            graph = parent
            standingFor = proxy
        }
        return ProxyChainState(levels: levels)
    }

    /// Takes the wires off the proxy standing for `port`, a port of a node in
    /// this graph, and off each proxy above it published in turn, with no
    /// undo: an undo of what took them is the step that puts them back.
    internal func disconnectProxyChain(standingFor port: Port)
    {
        var graph = self
        var standingFor = port
        while let (proxy, parent) = graph.proxy(standingFor: standingFor)
        {
            parent.withoutUndoRegistration {
                for connection in proxy.connections { _ = parent.disconnect(connection) }
            }
            guard proxy.published else { return }
            graph = parent
            standingFor = proxy
        }
    }

    /// Puts back what `state` holds for `port`, published again, level by
    /// level, each proxy's publishing bringing the proxy above it back.
    internal func restoreProxyChain(standingFor port: Port, to state: ProxyChainState)
    {
        var graph = self
        var standingFor = port
        for level in state.levels
        {
            guard let (proxy, parent) = graph.proxy(standingFor: standingFor) else { return }
            proxy.published = level.published
            proxy.publishedName = level.publishedName
            parent.rebuildPublishedParameterGroup()
            parent.withoutUndoRegistration {
                for wire in level.wires { parent.restore(wire.wire(onProxy: proxy)) }
            }
            graph = parent
            standingFor = proxy
        }
    }

    public func rebuildPublishedParameterGroup()
    {
        self.publishedParameterGroup.clear()

        let publishedPorts = self.getPublishedPorts()

        // Sync each parameter's label to its port's displayName so the
        // inspector reflects renames made via PortRenameAlert. The
        // parameter is the underlying source of truth for label across
        // all parameter views (sliders, input fields, color pickers
        // etc.), and the user's rename was a deliberate naming action.
        let publishedParams: [any Parameter] = publishedPorts.compactMap { port in
            guard let param = port.parameter else { return nil }
            let display = port.displayName
            if param.label != display { param.label = display }
            return param
        }

        self.publishedParameterGroup.append( publishedParams )

        // A published port connects its node through the enclosing subgraph node.
        let nodesWithPublishedPorts = Dictionary(self.nodesWithPublishedPorts().map { (ObjectIdentifier($0), $0) },
                                                 uniquingKeysWith: { first, _ in first })
        for (key, node) in nodesWithPublishedPorts where self.nodesWithPublishedPortsAtLastReview[key] == nil
        {
            self.markNodeForLifecycleReview(node)
        }
        for (key, node) in self.nodesWithPublishedPortsAtLastReview where nodesWithPublishedPorts[key] == nil
        {
            self.markNodeForLifecycleReview(node)
        }
        self.nodesWithPublishedPortsAtLastReview = nodesWithPublishedPorts

        self.markConnectionsChanged()
        self.onPublishedPortsChanged?()
    }
    
    internal func nodesWithPublishedPorts() -> [Node]
    {
        return self.nodes.filter { node in
            !node.publishedPorts().isEmpty
        }
    }
    
    internal func nodesWithPublishedInputs() -> [Node]
    {
        return self.nodes.filter { node in
            !node.publishedInputPorts().isEmpty
        }
    }
    
    internal func nodesWithPublishedOutputs() -> [Node]
    {
        return self.nodes.filter { node in
            !node.publishedOutputPorts().isEmpty
        }
    }
     
    // MARK: -Rendering Helpers
    internal var latestCamera:Camera? = nil

    private func setCameraSelection(_ camera: Camera?)
    {
        guard self.latestCamera !== camera else { return }
        self.latestCamera = camera
        self.onCameraSelectionChanged?()
    }

    private func updateCameraSelection(afterAdding node: Node)
    {
        if node.nodeType == .Object(objectType: .Camera),
           let camera = (node as? BaseObjectNode)?.getObject() as? Camera
        {
            self.setCameraSelection(camera)
            return
        }

        guard !(node is DeferredSubgraphNode),
              let subgraphNode = node as? SubgraphNode,
              let camera = subgraphNode.subGraph.latestCamera,
              !self.nodes.contains(where: { $0.nodeType == .Object(objectType: .Camera) })
        else { return }

        // With no direct camera, a newly appended subgraph is the last eligible
        // subgraph and therefore takes control.
        self.setCameraSelection(camera)
    }

    func updateCameraSelection()
    {
        self.setCameraSelection(Self.latestCamera(in: self))
    }
    
    /// The camera a graph renders with: the last one added to it, so a camera
    /// added to a graph that has one takes control rather than joining a queue
    /// behind it. One camera is active at a time; the rest are in the scene and
    /// inert.
    static func latestCamera(in graph:Graph) -> Camera?
    {
        if let latestCameraNode = graph.nodes.last(where: { $0.nodeType == .Object(objectType: .Camera) }),
           let camera = (latestCameraNode as? BaseObjectNode)?.getObject() as? Camera
        {
            return camera
        }

        // A regular subgraph contributes its scene to this graph, so its cached
        // camera is eligible here. A Deferred Subgraph renders through its own
        // renderer and keeps its camera isolated to that render pass.
        for node in graph.nodes.reversed()
        {
            guard !(node is DeferredSubgraphNode),
                  let subgraphNode = node as? SubgraphNode,
                  let camera = subgraphNode.subGraph.latestCamera
            else { continue }

            return camera
        }

        return nil
    }
    
    // MARK: -Selection
    
    public enum NodeSelectionDirection: Equatable {
        case Up
        case Down
        case Left
        case Right
        case Unknown

        static func from(angle: CGFloat) -> NodeSelectionDirection {
            // Normalize the angle to the range [0, 360)
            let normalizedAngle = angle.truncatingRemainder(dividingBy: 360)
            let angleIn360 = normalizedAngle >= 0 ? normalizedAngle : normalizedAngle + 360

            // Determine the direction based on the angle
            switch angleIn360 {
            case 45..<135:
                return .Up
            case 135..<225:
                return .Left
            case 225..<315:
                return .Down
            case 315..<360, 0..<45:
                return .Right
            default:
                return .Unknown
            }
        }
    }

    func selectNextNode(inDirection direction:NodeSelectionDirection, expandSelection:Bool = false)
    {
        if let referenceNode = self.lastNode ?? self.nodes.first
        {
            let referenceNodePoint = CGPoint(x: referenceNode.offset.width, y: referenceNode.offset.height)

            let relevantNodes = self.nodes.filter { $0.id != referenceNode.id }
            
            let distanceDirectionNodeTuples:[(Distance:Double, Direction:NodeSelectionDirection, Node:Node)] = relevantNodes.map {
                let nodePoint = CGPoint(x: $0.offset.width, y: $0.offset.height)
                
                let distance = nodePoint.distance(from: referenceNodePoint)

                let angle = referenceNodePoint.angle(to:nodePoint)
                
                // Due to Swift UI - we swap up and
                var direction = NodeSelectionDirection.from(angle: angle)
                switch direction
                {
                case .Up:
                    direction = .Down
                case .Down:
                    direction = .Up
                default:
                    break
                }
                
                print(referenceNode, referenceNode.offset, angle, direction, "to:", $0, $0.offset)
                return (distance, direction, $0 )
            }
            
            let relevantDistanceDirectionNodeTuples = distanceDirectionNodeTuples.filter { $0.Direction == direction }
            
            if let closestDistanceDirectionNodeTuples = relevantDistanceDirectionNodeTuples.sorted(by: { $0.Distance < $1.Distance }).first
            {
                print("reference node", referenceNode)

                self.selectNode(node: closestDistanceDirectionNodeTuples.Node, expandSelection: expandSelection)
            }
        }
    }
    
    public func selectNode(node:Node, expandSelection:Bool)
    {
        if !expandSelection
        {
            for n in self.nodes
            {
                nodeViewModels[n.id]?.isSelected = false
            }
        }

        self.lastNode = node
        nodeViewModels[node.id]?.isSelected = true
    }

    public func selectAllNodes()
    {
        for node in self.nodes
        {
            nodeViewModels[node.id]?.isSelected = true
        }
    }

    public func deselectAllNodes()
    {
        for node in self.nodes
        {
            nodeViewModels[node.id]?.isSelected = false
        }
    }

    public func selectDownstreamNodes(fromNode node:Node)
    {
        var visitedNodes:[Node] = []

        self.selectDownstreamNodesRecursive(fromNode: node, visitedNodes:&visitedNodes)
    }

    private func selectDownstreamNodesRecursive(fromNode node:Node, visitedNodes: inout [Node])
    {
        if !visitedNodes.contains(node)
        {
            visitedNodes.append( node )
            nodeViewModels[node.id]?.isSelected = true

            node.outputNodes.forEach( {
                self.selectDownstreamNodesRecursive(fromNode: $0, visitedNodes: &visitedNodes )
            } )
        }
    }

    public func selectUpstreamNodes(fromNode node:Node)
    {
        var visitedNodes:[Node] = []

        self.selectUpstreamNodesRecursive(fromNode: node, visitedNodes:&visitedNodes)
    }

    private func selectUpstreamNodesRecursive(fromNode node:Node, visitedNodes: inout [Node])
    {
        if !visitedNodes.contains(node)
        {
            visitedNodes.append( node )
            nodeViewModels[node.id]?.isSelected = true

            node.inputNodes.forEach( {
                self.selectUpstreamNodesRecursive(fromNode: $0, visitedNodes: &visitedNodes )
            } )
        }
    }

    private struct PublishedPortState
    {
        let portID: UUID
        let published: Bool
        let publishedName: String?
    }

    private struct BoundaryConnectionState
    {
        let wire: Wire
        let innerPortID: UUID
        var usesProxy = false
    }

    /// A Create Subgraph as its undo and redo hold it: the subgraph node, which
    /// is outside the graph whenever the embedding is to be applied, and
    /// everything else by id.
    private struct SubgraphEmbedding
    {
        var subgraphNode: SubgraphNode
        let nodeIDs: [UUID]
        let internalWires: [Wire]
        var boundaryConnections: [BoundaryConnectionState]
        let publishedPortStates: [PublishedPortState]
    }

    @discardableResult
    public func createSubgraph(from nodes: [Node],
                               centeredOn node: Node,
                               usingClass subgraphClass: SubgraphNode.Type) throws -> SubgraphNode
    {
        guard !nodes.isEmpty else {
            throw recoverableGraphError(.emptyNodeSelection,
                                        message: "At least one node is required.")
        }
        for selectedNode in nodes where selectedNode.graph !== self {
            throw recoverableGraphError(.nodeNotInGraph,
                                        message: "Node \(selectedNode.id) does not belong to this graph.")
        }
        guard node.graph === self else {
            throw recoverableGraphError(.nodeNotInGraph,
                                        message: "Node \(node.id) does not belong to this graph.")
        }

        let selectedNodeIDs = Set(nodes.map(\.id))
        let relevantConnections = connections.filter { connection in
            guard let outletNodeID = connection.outletPort?.node?.id,
                  let inletNodeID = connection.inletPort?.node?.id
            else { return false }
            return selectedNodeIDs.contains(outletNodeID) || selectedNodeIDs.contains(inletNodeID)
        }
        let internalConnections = relevantConnections.filter { connection in
            guard let outletNodeID = connection.outletPort?.node?.id,
                  let inletNodeID = connection.inletPort?.node?.id
            else { return false }
            return selectedNodeIDs.contains(outletNodeID) && selectedNodeIDs.contains(inletNodeID)
        }
        let internalConnectionIDs = Set(internalConnections.map(\.id))
        let boundaryConnections = relevantConnections
            .filter { !internalConnectionIDs.contains($0.id) }
            .compactMap { connection -> (state: BoundaryConnectionState, innerPort: Port)? in
                let movedPort: Port?
                if let outlet = connection.outletPort,
                   let outletNodeID = outlet.node?.id,
                   selectedNodeIDs.contains(outletNodeID)
                {
                    movedPort = outlet
                }
                else if let inlet = connection.inletPort,
                        let inletNodeID = inlet.node?.id,
                        selectedNodeIDs.contains(inletNodeID)
                {
                    movedPort = inlet
                }
                else
                {
                    movedPort = nil
                }
                return movedPort.map { (BoundaryConnectionState(wire: Wire(connection), innerPortID: $0.id), $0) }
            }
        let publishedPortStates = Dictionary(
            boundaryConnections.map { ($0.innerPort.id, $0.innerPort) },
            uniquingKeysWith: { first, _ in first }
        ).values.map {
            PublishedPortState(portID: $0.id, published: $0.published, publishedName: $0.publishedName)
        }

        let subgraphNode = subgraphClass.init(context: context)
        subgraphNode.offset = node.offset
        subgraphNode.subGraph.undoManager = undoManager
        let embedding = SubgraphEmbedding(subgraphNode: subgraphNode,
                                          nodeIDs: nodes.map(\.id),
                                          internalWires: internalConnections.map(Wire.init),
                                          boundaryConnections: boundaryConnections.map(\.state),
                                          publishedPortStates: publishedPortStates)

        applyEmbedding(embedding)
        undoManager?.setActionName("Create Subgraph")
        return subgraphNode
    }

    private func applyEmbedding(_ embedding: SubgraphEmbedding)
    {
        var embedding = embedding
        let subgraphNode = embedding.subgraphNode
        let subGraph = subgraphNode.subGraph
        let nodes = embedding.nodeIDs.compactMap { self.node(forID: $0) }

        performWithBatchedConnectionTopologyChanges {
            subGraph.performWithBatchedConnectionTopologyChanges {
                withoutUndoRegistration {
                    self.addNode(subgraphNode)
                    for node in nodes {
                        self.delete(node: node, disconnect: false)
                        subGraph.addNode(node)
                    }

                    for wire in embedding.internalWires {
                        if let connection = self.connection(matching: wire) {
                            self.transferConnection(connection, to: subGraph)
                        }
                    }

                    for state in embedding.publishedPortStates {
                        subGraph.nodePort(forID: state.portID)?.published = true
                    }
                    subGraph.rebuildPublishedParameterGroup()

                    for index in embedding.boundaryConnections.indices {
                        let state = embedding.boundaryConnections[index]
                        guard let connection = self.connection(matching: state.wire),
                              let innerPort = subGraph.nodePort(forID: state.innerPortID)
                        else { continue }

                        if let proxy = subgraphNode.ports.first(where: {
                            $0.id == state.innerPortID && $0 is any ProxyPortProtocol
                        }) {
                            self.rebindConnection(connection, replacing: innerPort, with: proxy)
                            embedding.boundaryConnections[index].usesProxy = true
                        }
                        else if let outlet = connection.outletPort,
                                let inlet = connection.inletPort
                        {
                            outlet.sendBoxed(nil, force: true)
                            self.detachConnection(connection, outlet: outlet, inlet: inlet)
                            embedding.boundaryConnections[index].usesProxy = false
                        }
                    }

                    self.markConnectionTopologyChanged()
                    subGraph.markConnectionTopologyChanged()
                }
            }
        }

        let applied = embedding
        self.registerUndo { graph in
            graph.revertEmbedding(applied)
        }
    }

    private func revertEmbedding(_ embedding: SubgraphEmbedding)
    {
        guard let subgraphNode = self.node(forID: embedding.subgraphNode.id) as? SubgraphNode else { return }
        let subGraph = subgraphNode.subGraph
        let nodes = embedding.nodeIDs.compactMap { subGraph.node(forID: $0) }
        let proxiesByInnerPortID = Dictionary(
            subgraphNode.ports.compactMap { port in
                (port as? any ProxyPortProtocol).map { ($0.innerPortID, port) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        performWithBatchedConnectionTopologyChanges {
            subGraph.performWithBatchedConnectionTopologyChanges {
                withoutUndoRegistration {
                    self.delete(node: subgraphNode, disconnect: false)
                    for node in nodes {
                        subGraph.delete(node: node, disconnect: false)
                        self.addNode(node)
                    }

                    for wire in embedding.internalWires {
                        if let connection = subGraph.connection(matching: wire) {
                            subGraph.transferConnection(connection, to: self)
                        }
                    }

                    for state in embedding.boundaryConnections {
                        if state.usesProxy
                        {
                            guard let proxy = proxiesByInnerPortID[state.innerPortID],
                                  let innerPort = self.nodePort(forID: state.innerPortID),
                                  let connection = self.connection(matching: state.wire)
                            else { continue }
                            self.rebindConnection(connection, replacing: proxy, with: innerPort)
                        }
                        else
                        {
                            self.restore(state.wire)
                        }
                    }

                    for state in embedding.publishedPortStates {
                        guard let port = self.nodePort(forID: state.portID) else { continue }
                        port.published = state.published
                        port.publishedName = state.publishedName
                    }
                    subGraph.rebuildPublishedParameterGroup()

                    self.markConnectionTopologyChanged()
                    subGraph.markConnectionTopologyChanged()
                }
            }
        }

        var reapplied = embedding
        reapplied.subgraphNode = subgraphNode
        self.registerUndo { graph in
            graph.applyEmbedding(reapplied)
            graph.undoManager?.setActionName("Create Subgraph")
        }
        undoManager?.setActionName("Create Subgraph")
    }

    internal func withoutUndoRegistration(_ operation: () -> Void)
    {
        let undoManager = self.effectiveUndoManager
        let shouldRestoreUndoRegistration = undoManager?.isUndoRegistrationEnabled == true
        if shouldRestoreUndoRegistration { undoManager?.disableUndoRegistration() }
        defer {
            if shouldRestoreUndoRegistration { undoManager?.enableUndoRegistration() }
        }
        operation()
    }

    private func performWithBatchedConnectionTopologyChanges(_ operation: () -> Void)
    {
        connectionTopologyBatchDepth += 1
        defer {
            connectionTopologyBatchDepth -= 1
            if connectionTopologyBatchDepth == 0, hasPendingBatchedConnectionTopologyChange
            {
                hasPendingBatchedConnectionTopologyChange = false
                markConnectionTopologyChanged()
            }
        }
        operation()
    }
    
    // Theres a possible race condition here, as a node
    // may not have a object loaded yet
    // ( lazy loading, needs execution, isnt connected)
    // we need to track when said node's object comes online....
    private func maybeAddNodeToScene(_ node:Node)
    {
        if let objectNode = node as? BaseObjectNode,
           let object = objectNode.getObject()
        {
//            print("Graph: \(self.id) Scene: Added Child", objectNode)
            self.scene.add( object )
        }
        else
        {
//            print("Graph: \(self.id) Scene: Skipped Child", node)
        }
    }
    
    private func maybeDeleteNodeFromScene(_ node:Node)
    {
        if let objectNode = node as? BaseObjectNode,
           let object = objectNode.getObject()
        {
            self.scene.remove( object )
        }
    }
    
    public func syncNodesToScene(removingObject:Object? = nil)
    {
        self.scene.removeAll()

//        print("Graph: \(self.id) Scene: Syncing Nodes")

        self.nodes.forEach({ self.maybeAddNodeToScene( $0) } )
    }

    // MARK: - Private Decode API Helpers -
    
    /// Decodes a single node from an AnyCodableMap, replicating the type resolution from Graph.init(from:)
    private func decodeNode(from map: AnyCodableMap) -> Node?
    {
        // Graph.init(from:) closes each node's hydration window once every node
        // is decoded; duplicate and paste come through here instead, so the
        // window has to close before the node is handed back or a port added
        // later would adopt paste-time state.
        guard let node = decodeNodeLeavingHydrationOpen(from: map) else { return nil }

        _ = node.finalizePortHydration()
        return node
    }

    private func decodeNodeLeavingHydrationOpen(from map: AnyCodableMap) -> Node?
    {
        do
        {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            decoder.context = DecoderContext(documentContext: self.context)

            let jsonData = try encoder.encode(map.value)

            let nodeID = Self.qualifiedNodeID(fromSerializedType: map.type)
            let nodeRegistry = try NodeRegistry.shared

            if let nodeClass = nodeRegistry.nodeClass(pluginID: nodeID.pluginID, nodeID: nodeID.nodeID)
            {
                return try decoder.decode(nodeClass, from: jsonData)
            }
            else if map.type == String(describing: type(of: BaseImageNode.self)).replacing(".Type", with:"")
            {
                return try decoder.decode(BaseImageNode.self, from: jsonData)
            }
            else if map.type == "BaseEffectThreeChannelNode"
            {
                return try decoder.decode(BaseImageNode.self, from: jsonData)
            }
            else if map.type == "BaseEffectTwoChannelNode"
            {
                return try decoder.decode(BaseImageNode.self, from: jsonData)
            }
            else if map.type == "BaseEffectNode"
            {
                return try decoder.decode(BaseImageNode.self, from: jsonData)
            }
            else if map.type == "BaseGeneratorNode"
            {
                return try decoder.decode(BaseImageNode.self, from: jsonData)
            }
            else if map.type == "LiveEffectNode"
            {
                return try decoder.decode(LiveImageNode.self, from: jsonData)
            }
            else
            {
                print("decodeNode: Failed to find nodeClass for \(map.type)")
            }
        }
        catch
        {
            print("decodeNode: Failed to decode node of type \(map.type): \(error)")
        }

        return nil
    }

    /// Checks if a string looks like a UUID (36 chars, proper format)
    private static func isUUIDString(_ string: String) -> Bool
    {
        return string.count == 36 && UUID(uuidString: string) != nil
    }

    /// Recursively collects the ids in a JSON object: UUID-formatted strings
    /// under a key that names an id, `id` or one ending in `ID`, as every
    /// encoded node, port, connection and proxy names its ids. A UUID-shaped
    /// string elsewhere is a value, such as text a user typed, and is left as
    /// it is.
    private static func collectUUIDs(from object: Any, into uuids: inout Set<String>, underIDKey: Bool = false)
    {
        switch object
        {
        case let string as String:
            if underIDKey, isUUIDString(string)
            {
                uuids.insert(string)
            }

        case let array as [Any]:
            for element in array
            {
                collectUUIDs(from: element, into: &uuids, underIDKey: underIDKey)
            }

        case let dict as [String: Any]:
            for (key, value) in dict
            {
                collectUUIDs(from: value, into: &uuids, underIDKey: isIDKey(key))
            }

        default:
            break
        }
    }

    private static func isIDKey(_ key: String) -> Bool
    {
        key == "id" || key.hasSuffix("ID") || key.hasSuffix("IDs")
    }

    private func qualifiedNodeID(for nodeClass: Node.Type) throws -> PluginQualifiedNodeID
    {
        let registry = try NodeRegistry.shared

        if let qualifiedNodeID = registry.qualifiedNodeID(for: nodeClass)
        {
            return qualifiedNodeID
        }

        throw FabricError(.deserialization(.nodeNotFound),
                          severity: .fatal,
                          message: "Could not find plugin registration for node class '\(String(describing: nodeClass))'")
    }

    private func requiredPlugins(for nodes: [Node]) throws -> [PluginRequirement]
    {
        let registry = try NodeRegistry.shared
        var requirementsByID: [String: PluginRequirement] = [:]

        for node in nodes
        {
            guard let qualifiedNodeID = registry.qualifiedNodeID(for: type(of: node)) else
            {
                throw FabricError(.deserialization(.nodeNotFound),
                                  severity: .fatal,
                                  message: "Could not find plugin registration for node class '\(String(describing: type(of: node)))'")
            }

            guard let pluginInfo = PluginLoader.shared.loadedPlugins[qualifiedNodeID.pluginID] else
            {
                throw FabricError(.loading(.pluginNotFound),
                                  severity: .fatal,
                                  message: "Required plugin '\(qualifiedNodeID.pluginID)' is not loaded")
            }

            requirementsByID[qualifiedNodeID.pluginID] = PluginRequirement(id: pluginInfo.id,
                                                                          version: pluginInfo.version)
        }

        return requirementsByID.values.sorted { $0.id < $1.id }
    }

    private static func qualifiedNodeID(fromSerializedType serializedType: String) -> PluginQualifiedNodeID
    {
        guard let separatorRange = serializedType.range(of: PluginQualifiedNodeID.separator) else
        {
            return PluginQualifiedNodeID(pluginID: PluginLoader.coreNodesPluginID,
                                         nodeID: serializedType)
        }

        return PluginQualifiedNodeID(pluginID: String(serializedType[..<separatorRange.lowerBound]),
                                     nodeID: String(serializedType[separatorRange.upperBound...]))
    }

    /// Finds the ids in JSON data; see `collectUUIDs`.
    private static func findAllUUIDs(in jsonData: Data) -> Set<String>
    {
        guard let object = try? JSONSerialization.jsonObject(with: jsonData) else { return [] }
        var uuids = Set<String>()
        collectUUIDs(from: object, into: &uuids)
        return uuids
    }

    /// Recursively replaces UUID strings in a JSON object using a remap table
    private static func remapUUIDs(in object: Any, remap: [String: String]) -> Any
    {
        switch object
        {
        case let string as String:
            return remap[string] ?? string

        case let array as [Any]:
            return array.map { remapUUIDs(in: $0, remap: remap) }

        case let dict as [String: Any]:
            var newDict = [String: Any]()
            for (key, value) in dict
            {
                newDict[key] = remapUUIDs(in: value, remap: remap)
            }
            return newDict

        default:
            return object
        }
    }

    /// Rewrites UUID strings in JSON data using a remap table
    private static func rewriteUUIDs(in jsonData: Data, remap: [String: String]) -> Data?
    {
        guard let object = try? JSONSerialization.jsonObject(with: jsonData) else { return nil }
        let remapped = remapUUIDs(in: object, remap: remap)
        return try? JSONSerialization.data(withJSONObject: remapped)
    }

    /// Builds a connection map containing only connections where both ports belong to nodes in the given set
    private func buildInternalConnectionMap(for nodes: [Node]) -> [UUID: [UUID]]
    {
        let allPortIDs = Set(nodes.flatMap { $0.ports.map { $0.id } })
        var connectionMap: [UUID: [UUID]] = [:]

        for node in nodes
        {
            for port in node.ports
            {
                let internalConnections = port.connectedPorts
                    .filter { allPortIDs.contains($0.id) }
                    .map { $0.id }

                if !internalConnections.isEmpty
                {
                    connectionMap[port.id] = internalConnections
                }
            }
        }

        return connectionMap
    }

    /// Duplicates the given nodes, preserving connections between them, and adds them to the graph
    @discardableResult
    public func duplicateNodes(_ nodesToDuplicate: [Node], offset: CGSize = CGSize(width: 20, height: 20)) -> [Node]
    {
        guard !nodesToDuplicate.isEmpty else { return [] }

        // 1. Capture internal connections before anything changes
        let internalConnections = self.buildInternalConnectionMap(for: nodesToDuplicate)

        // 2. Encode all nodes and build a unified UUID remap table
        let encoder = JSONEncoder()
        var uuidRemap: [String: String] = [:]
        var encodedEntries: [Data] = []

        for node in nodesToDuplicate
        {
            do
            {
                let qualifiedNodeID = try self.qualifiedNodeID(for: type(of: node))
                let map = AnyCodableMap(
                    type: qualifiedNodeID.description,
                    value: AnyCodable(node)
                )
                let data = try encoder.encode(map)
                encodedEntries.append(data)

                // Collect all UUIDs from this node's JSON
                for uuid in Graph.findAllUUIDs(in: data)
                {
                    if uuidRemap[uuid] == nil
                    {
                        uuidRemap[uuid] = UUID().uuidString
                    }
                }
            }
            catch
            {
                print("duplicateNodes: Failed to encode \(node): \(error)")
            }
        }

        // 3. Rewrite UUIDs and decode each node
        var newNodes: [Node] = []

        for data in encodedEntries
        {
            guard let rewrittenData = Graph.rewriteUUIDs(in: data, remap: uuidRemap) else { continue }

            do
            {
                let rewrittenMap = try JSONDecoder().decode(AnyCodableMap.self, from: rewrittenData)

                if let newNode = self.decodeNode(from: rewrittenMap)
                {
                    newNode.offset = newNode.offset + offset
                    newNodes.append(newNode)
                }
            }
            catch
            {
                print("duplicateNodes: Failed to decode rewritten node: \(error)")
            }
        }

        // 4. Add all new nodes (grouped undo)
        self.undoManager?.beginUndoGrouping()

        for newNode in newNodes
        {
            self.addNode(newNode)
        }

        // 5. Restore internal connections using remapped port IDs
        for (oldPortID, oldConnectedIDs) in internalConnections
        {
            guard let newPortIDString = uuidRemap[oldPortID.uuidString],
                  let newPortID = UUID(uuidString: newPortIDString),
                  let newPort = self.nodePort(forID: newPortID)
            else { continue }

            for oldConnectedID in oldConnectedIDs
            {
                guard let newConnectedIDString = uuidRemap[oldConnectedID.uuidString],
                      let newConnectedID = UUID(uuidString: newConnectedIDString),
                      let newConnectedPort = self.nodePort(forID: newConnectedID)
                else { continue }

                if newPort.kind == .Outlet {
                    self.connect(newPort, to: newConnectedPort)
                }
            }
        }

        self.undoManager?.endUndoGrouping()
        self.undoManager?.setActionName("Duplicate Nodes")

        // 6. Select only the new nodes
        self.deselectAllNodes()
        for newNode in newNodes { nodeViewModels[newNode.id]?.isSelected = true }

        self.markConnectionsChanged()

        return newNodes
    }

   
}

#if os(macOS)
extension Graph
{
    // MARK: - Copy / Paste / Duplicate

    public static let nodeClipboardType = NSPasteboard.PasteboardType("info.vade.fabric.nodes")

    private struct NodeClipboardData: Codable
    {
        let nodeEntries: [AnyCodableMap]
        let internalConnectionMap: [String: [String]]
    }
    
    /// Copies selected nodes and their internal connections to the system pasteboard
    public func copyNodesToPasteboard(_ nodes: [Node])
    {
        guard !nodes.isEmpty else { return }

        let internalConnections = buildInternalConnectionMap(for: nodes)

        let nodeEntries: [AnyCodableMap]

        do
        {
            nodeEntries = try nodes.map {
                let qualifiedNodeID = try self.qualifiedNodeID(for: type(of: $0))
                return AnyCodableMap(
                    type: qualifiedNodeID.description,
                    value: AnyCodable($0)
                )
            }
        }
        catch
        {
            print("copyNodesToPasteboard: Failed to resolve plugin node IDs: \(error)")
            return
        }

        // Store connection map with string keys for Codable compatibility
        let stringConnectionMap: [String: [String]] = internalConnections.reduce(into: [:]) { result, entry in
            result[entry.key.uuidString] = entry.value.map { $0.uuidString }
        }

        let clipboardData = NodeClipboardData(
            nodeEntries: nodeEntries,
            internalConnectionMap: stringConnectionMap
        )

        do
        {
            let data = try JSONEncoder().encode(clipboardData)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(data, forType: Graph.nodeClipboardType)
        }
        catch
        {
            print("copyNodesToPasteboard: Failed to encode: \(error)")
        }
    }

    /// Pastes nodes from the system pasteboard into the graph
    @discardableResult
    
    public func pasteNodesFromPasteboard(offset: CGSize = CGSize(width: 20, height: 20)) -> [Node]
    {
        guard let data = NSPasteboard.general.data(forType: Graph.nodeClipboardType) else
        {
            return []
        }

        do
        {
            let clipboardData = try JSONDecoder().decode(NodeClipboardData.self, from: data)

            let encoder = JSONEncoder()
            var uuidRemap: [String: String] = [:]
            var encodedEntries: [Data] = []

            // First pass: encode all entries and collect every UUID for remapping
            for entry in clipboardData.nodeEntries
            {
                let entryData = try encoder.encode(entry)
                encodedEntries.append(entryData)

                for uuid in Graph.findAllUUIDs(in: entryData)
                {
                    if uuidRemap[uuid] == nil
                    {
                        uuidRemap[uuid] = UUID().uuidString
                    }
                }
            }

            // Also ensure connection map UUIDs are in the remap
            for (portID, connectedIDs) in clipboardData.internalConnectionMap
            {
                if uuidRemap[portID] == nil { uuidRemap[portID] = UUID().uuidString }
                for cid in connectedIDs
                {
                    if uuidRemap[cid] == nil { uuidRemap[cid] = UUID().uuidString }
                }
            }

            // Second pass: rewrite UUIDs and decode each node
            var newNodes: [Node] = []

            for entryData in encodedEntries
            {
                guard let rewrittenData = Graph.rewriteUUIDs(in: entryData, remap: uuidRemap) else { continue }

                let rewrittenMap = try JSONDecoder().decode(AnyCodableMap.self, from: rewrittenData)

                if let newNode = self.decodeNode(from: rewrittenMap)
                {
                    newNode.offset = newNode.offset + offset
                    newNodes.append(newNode)
                }
            }

            // Add nodes and restore connections
            self.undoManager?.beginUndoGrouping()

            for newNode in newNodes
            {
                self.addNode(newNode)
            }

            // Restore internal connections using remapped IDs
            for (oldPortIDString, oldConnectedIDStrings) in clipboardData.internalConnectionMap
            {
                guard let newPortIDString = uuidRemap[oldPortIDString],
                      let newPortID = UUID(uuidString: newPortIDString),
                      let newPort = self.nodePort(forID: newPortID)
                else { continue }

                for oldConnectedIDString in oldConnectedIDStrings
                {
                    guard let newConnectedIDString = uuidRemap[oldConnectedIDString],
                          let newConnectedID = UUID(uuidString: newConnectedIDString),
                          let newConnectedPort = self.nodePort(forID: newConnectedID)
                    else { continue }

                    if newPort.kind == .Outlet {
                        self.connect(newPort, to: newConnectedPort)
                    }
                }
            }

            self.undoManager?.endUndoGrouping()
            self.undoManager?.setActionName("Paste Nodes")

            self.deselectAllNodes()
            for newNode in newNodes { nodeViewModels[newNode.id]?.isSelected = true }

            self.markConnectionsChanged()

            return newNodes
        }
        catch
        {
            print("pasteNodesFromPasteboard: Failed: \(error)")
            return []
        }
    }
}
#endif
