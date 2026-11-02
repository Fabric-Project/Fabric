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
    /// removed nodes alive until the renderer retires them.
    @ObservationIgnored private var nodesAwaitingLifecycleReview: Set<Node> = []
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
        nodesAwaitingLifecycleReview.insert(node)
    }

    internal func takeNodesAwaitingLifecycleReview() -> Set<Node>
    {
        let reviewedNodes = nodesAwaitingLifecycleReview
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
    /// graph. It owns the proxies standing for this graph's published ports,
    /// and is told of each change to them; see portDidPublish(_:).
    @ObservationIgnored public internal(set) weak var ownerNode: SubgraphNode?

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
 
    //MARK: - Notes API -
    
    public func addNote(_ note: Note)
    {
        self.notes.append(note)
    }
    
    public func deleteNote(_ note:Note)
    {
        self.notes.removeAll(where: { $0.id == note.id })
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

        self.undoManager?.registerUndo(withTarget: self) { graph in
            graph.delete(node: node)
        }

        self.undoManager?.setActionName("Add Node")
        self.markConnectionsChanged()

        self.updateCameraSelection(afterAdding: node)
        self.portsDidPublish(node.ports.filter(\.published))
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

    /// Rewrites absolute static file references at save time, making those
    /// inside the document directory relative. Relative references persist as
    /// written, wherever the document is saved.
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
                      // Without a directory, only absolute references resolve.
                      let sourceURL = URL(fileReference: reference, relativeTo: nil)
                else { continue }

                let rewrittenReference = sourceURL.fileReference(relativeTo: directoryURL)
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

    
    
    public func delete(node:Node, disconnect:Bool = true)
    {
        guard self.hasMember(node) else { return }

        let savedOffset = node.offset
        self.portsWillUnpublish(node.ports.filter(\.published))

        let nodePortIDs = Set(node.ports.map(\.id))
        let savedConnections = connections.filter {
            nodePortIDs.contains($0.outletPortID) || nodePortIDs.contains($0.inletPortID)
        }

        withoutUndoRegistration {
            if disconnect
            {
                for connection in savedConnections {
                    self.disconnect(connection)
                }
            }

            self.nodes.removeAll { $0.id == node.id }
            // Disconnecting inputs can make getObject() nil while its previous object
            // is still attached. Reconcile from the remaining nodes, not that accessor.
            self.syncNodesToScene()
            node.graph = nil
            self.nodeMembershipDidChange(node)
            // Remove ViewModel after removing from nodes so any in-flight
            // ForEach evaluation still finds it.
            self.nodeViewModels[node.id] = nil
        }

        self.undoManager?.registerUndo(withTarget: self) { graph in
            graph.restoreDeletedNode(node,
                                     offset: savedOffset,
                                     connections: savedConnections)
        }

        self.undoManager?.setActionName("Delete Node")
        self.markConnectionsChanged()

        self.updateCameraSelection()
        self.rebuildPublishedParameterGroup()
    }

    private func restoreDeletedNode(_ node: Node,
                                    offset: CGSize,
                                    connections: [Connection])
    {
        withoutUndoRegistration {
            node.offset = offset
            nodeViewModels[node.id] = NodeViewModel(node: node)
            nodes.append(node)
            node.graph = self
            nodeMembershipDidChange(node)
            maybeAddNodeToScene(node)

            for connection in connections where connection.graph == nil {
                restore(connection)
            }

            node.markDirty()
            updateCameraSelection(afterAdding: node)
            portsDidPublish(node.ports.filter(\.published))
            syncNodesToScene()
            markConnectionsChanged()
        }

        undoManager?.registerUndo(withTarget: self) { graph in
            graph.delete(node: node)
        }
        undoManager?.setActionName("Delete Node")
    }
    
    /// Whether `node` is in this graph's node list. The publishing API and
    /// Node's port edits test membership with this rather than `node.graph`,
    /// since a decoded node names its graph before the graph adds it.
    internal func hasMember(_ node: Node) -> Bool
    {
        self.nodes.contains { $0 === node }
    }

    /// Whether `port` is a port of a node in this graph; see hasMember(_:).
    private func hasMember(_ port: Port) -> Bool
    {
        port.node.map(self.hasMember) ?? false
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

        undoManager?.registerUndo(withTarget: self) { graph in
            graph.disconnect(connection)
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

        undoManager?.registerUndo(withTarget: self) { graph in
            graph.restore(connection)
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

        undoManager?.registerUndo(withTarget: self) { graph in
            graph.setConnection(connection, active: previousActive)
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

    @discardableResult
    private func restore(_ connection: Connection) -> Bool
    {
        if connections.contains(where: { $0 === connection }) { return true }
        guard let outlet = nodePort(forID: connection.outletPortID),
              let inlet = nodePort(forID: connection.inletPortID),
              connectionEndpointsBelongToGraph(outlet: outlet, inlet: inlet)
        else { return false }

        attachConnection(connection, outlet: outlet, inlet: inlet)
        markConnectionTopologyChanged()
        outlet.sendBoxed(outlet.snapshotValue(), force: true)

        undoManager?.registerUndo(withTarget: self) { graph in
            graph.disconnect(connection)
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

    /// The port at the far end of `connection`, a wire on `old`, if `new` can
    /// take that wire: `new` is of `old`'s kind and the two ports can connect.
    /// Nil otherwise.
    private func port(across connection: Connection, from old: Port, fitting new: Port) -> Port?
    {
        guard new.kind == old.kind, let other = connection.port(opposite: old) else { return nil }
        let fits = new.kind == .Outlet ? new.canConnect(to: other) : other.canConnect(to: new)
        return fits ? other : nil
    }

    /// Keeps each wire on `old` that `new` can take, as the same Connection
    /// now on `new`, and disconnects the rest as undo steps. For a replacement
    /// under `old`'s id, since a wire names its ports by id; a port with an id
    /// of its own takes wires through transferWires(from:to:). `old` must
    /// still be in this graph, so the disconnects find both ends of each wire.
    /// `new` may be `old` itself, retyped in place.
    internal func rebindWires(from old: Port, to new: Port)
    {
        let wires = old.connections.filter { $0.graph === self }
        guard !wires.isEmpty else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        for connection in wires
        {
            guard new.id == old.id, self.port(across: connection, from: old, fitting: new) != nil else
            {
                self.disconnect(connection)
                continue
            }

            if new !== old { self.rebindConnection(connection, replacing: old, with: new) }
            if let outlet = connection.outletPort { outlet.sendBoxed(outlet.snapshotValue(), force: true) }
        }
        self.markConnectionTopologyChanged()
    }

    /// Moves the wires on `port` in this graph that `replacement` can take to
    /// `replacement`, as disconnect and connect undo steps, where they displace
    /// nothing: an outlet takes every wire alongside its own, an inlet that is
    /// already wired keeps its wire. A wire that does not move stays on `port`
    /// for its unpublish to take down. For a port with an id of its own; a
    /// replacement under the old id keeps its wires through
    /// rebindWires(from:to:).
    internal func transferWires(from port: Port, to replacement: Port)
    {
        for connection in port.connections where connection.graph === self
        {
            guard let other = self.port(across: connection, from: port, fitting: replacement) else { continue }
            let isInlet = replacement.kind == .Inlet
            if isInlet, replacement.connections.contains(where: { $0.graph === self }) { continue }

            self.disconnect(connection)
            if isInlet
            {
                self.connect(other, to: replacement)
            }
            else
            {
                self.connect(replacement, to: other)
            }
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

    /// Publishes or unpublishes `port`, a port of a node in this graph, as an
    /// undo step. The sub graph node around this graph is told, and makes or
    /// drops the proxy standing for the port; see portDidPublish(_:).
    /// Publishing keeps the port's published name; unpublishing clears it.
    public func setPublished(_ published: Bool, on port: Port)
    {
        self.setPublished(published, on: port, name: published ? port.publishedName : nil)
    }

    /// `name` is the published name the port is left with. Undo passes the
    /// name the port had before, so undoing a publish restores a name the port
    /// carried while unpublished without a rename step.
    private func setPublished(_ published: Bool, on port: Port, name: String?)
    {
        guard port.published != published, self.hasMember(port) else { return }

        // One undo group: the sub graph node's reaction registers steps of its own.
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let previousName = port.publishedName
        if published
        {
            port.setPublishing(true, name: name)
            self.portDidPublish(port)
        }
        else
        {
            self.portWillUnpublish(port)
            port.setPublishing(false, name: name)
            // The label followed the published name; displayName is the port's own name again.
            port.parameter?.label = port.displayName
            self.rebuildPublishedParameterGroup()
        }

        self.registerPublishingUndo(of: port, published: published, previousName: previousName)
    }

    private func registerPublishingUndo(of port: Port, published: Bool, previousName: String?)
    {
        let portID = port.id
        undoManager?.registerUndo(withTarget: self) { graph in
            graph.nodePort(forID: portID).map { graph.setPublished(!published, on: $0, name: previousName) }
        }
        undoManager?.setActionName(published ? "Publish Port" : "Unpublish Port")
    }

    /// Publishes `ports`, ports of nodes in this graph, as setPublished(true,
    /// on:) does each one, raising one event for them all.
    private func publishPorts(_ ports: [Port])
    {
        let publishing = ports.filter { !$0.published && self.hasMember($0) }
        guard !publishing.isEmpty else { return }

        for port in publishing
        {
            let previousName = port.publishedName
            port.setPublishing(true, name: previousName)
            self.registerPublishingUndo(of: port, published: true, previousName: previousName)
        }
        self.portsDidPublish(publishing)
    }

    /// Takes this graph's wires off `ports`, ports of `node`, and unpublishes
    /// those that are published, as disconnectAll(from:) and
    /// setPublished(false, on:) would port by port, with one rebuild of the
    /// published parameter group. Called by a sub graph node retiring its own
    /// proxies.
    internal func disconnectAndUnpublish(_ ports: [Port], of node: Node)
    {
        guard self.hasMember(node), !ports.isEmpty else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        for connection in ports.flatMap(\.connections) where connection.graph === self
        {
            self.disconnect(connection)
        }

        let published = ports.filter(\.published)
        guard !published.isEmpty else { return }

        self.portsWillUnpublish(published)
        for port in published
        {
            let previousName = port.publishedName
            port.setPublishing(false, name: nil)
            port.parameter?.label = port.displayName
            self.registerPublishingUndo(of: port, published: false, previousName: previousName)
        }
        self.rebuildPublishedParameterGroup()
    }

    /// Sets the name the graph around shows `port`, a port of a node in this
    /// graph, under once it is published; nil goes back to the port's own
    /// name. An unpublished port may carry a name: publishing keeps it, and
    /// undoing a publish leaves it. Undoable.
    public func setPublishedName(_ name: String?, on port: Port)
    {
        let previousName = port.publishedName
        guard previousName != name, self.hasMember(port) else { return }

        port.setPublishing(port.published, name: name)
        self.portDidRename(port)

        let portID = port.id
        undoManager?.registerUndo(withTarget: self) { graph in
            graph.nodePort(forID: portID).map { graph.setPublishedName(previousName, on: $0) }
        }
        undoManager?.setActionName("Rename Port")
    }

    // MARK: - Publishing Events -

    // A port joins or leaves this graph's published set, or is replaced under
    // its id, only through this graph. The graph tells the sub graph node
    // around it of each change as the specific change it is, before anything
    // is taken away and after anything is added. The events keep the proxies
    // true to the published set, so they are raised whether or not undo
    // registration is on; what a reaction does through the graph's API
    // registers undo as that API does.

    /// `port`, a port of a node in this graph, has joined the published set.
    internal func portDidPublish(_ port: Port)
    {
        self.portsDidPublish([port])
    }

    /// `ports`, ports of nodes in this graph, have joined the published set
    /// together, as a node's ports do when the node is added.
    internal func portsDidPublish(_ ports: [Port])
    {
        guard !ports.isEmpty else { return }
        for node in ports.compactMap(\.node) { self.markNodeForLifecycleReview(node) }
        self.rebuildPublishedParameterGroup()
        self.ownerNode?.innerPortsDidPublish(ports)
    }

    /// `port`, a published port of a node in this graph, is about to be
    /// unpublished or removed with its node. Its proxy is removed now, with
    /// the wires on it and its own publishing in the graph around. The caller
    /// rebuilds the published parameter group once the port has gone.
    internal func portWillUnpublish(_ port: Port)
    {
        self.portsWillUnpublish([port])
    }

    /// `ports`, published ports of nodes in this graph, are about to leave the
    /// published set together, as a node's ports do when the node is deleted;
    /// see portWillUnpublish(_:).
    internal func portsWillUnpublish(_ ports: [Port])
    {
        guard !ports.isEmpty else { return }
        for node in ports.compactMap(\.node) { self.markNodeForLifecycleReview(node) }
        self.ownerNode?.innerPortsWillUnpublish(ports)
    }

    /// `new` has replaced `old`, a published port of a node in this graph,
    /// under the same id, published as `old` was.
    internal func port(_ old: Port, wasReplacedBy new: Port)
    {
        if let node = new.node { self.markNodeForLifecycleReview(node) }
        self.rebuildPublishedParameterGroup()
        self.ownerNode?.innerPort(old, wasReplacedBy: new)
    }

    /// `port`, a port of a node in this graph, has a new published name. No
    /// event for an unpublished port: its name is not in the published set.
    internal func portDidRename(_ port: Port)
    {
        guard port.published else { return }
        self.rebuildPublishedParameterGroup()
        self.ownerNode?.innerPortDidRename(port)
    }

    /// Rebuilds the parameters standing for this graph's published ports.
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

        self.markConnectionsChanged()
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
     
    // MARK: - Rendering Helpers
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
    
    // MARK: - Selection
    
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
        let port: Port
        let published: Bool
        let publishedName: String?
    }

    private struct BoundaryConnectionState
    {
        let connection: Connection
        let innerPort: Port
        var usesProxy = false
    }

    private final class SubgraphEmbedding
    {
        let nodes: [Node]
        let subgraphNode: SubgraphNode
        let internalConnections: [Connection]
        var boundaryConnections: [BoundaryConnectionState]
        let publishedPortStates: [PublishedPortState]

        init(nodes: [Node],
             subgraphNode: SubgraphNode,
             internalConnections: [Connection],
             boundaryConnections: [BoundaryConnectionState],
             publishedPortStates: [PublishedPortState])
        {
            self.nodes = nodes
            self.subgraphNode = subgraphNode
            self.internalConnections = internalConnections
            self.boundaryConnections = boundaryConnections
            self.publishedPortStates = publishedPortStates
        }
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
            .compactMap { connection -> BoundaryConnectionState? in
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
                return movedPort.map { BoundaryConnectionState(connection: connection, innerPort: $0) }
            }
        let publishedPortStates = Dictionary(
            boundaryConnections.map { ($0.innerPort.id, $0.innerPort) },
            uniquingKeysWith: { first, _ in first }
        ).values.map {
            PublishedPortState(port: $0, published: $0.published, publishedName: $0.publishedName)
        }

        let subgraphNode = subgraphClass.init(context: context)
        subgraphNode.offset = node.offset
        subgraphNode.subGraph.undoManager = undoManager
        let embedding = SubgraphEmbedding(nodes: nodes,
                                          subgraphNode: subgraphNode,
                                          internalConnections: internalConnections,
                                          boundaryConnections: boundaryConnections,
                                          publishedPortStates: publishedPortStates)

        applyEmbedding(embedding)
        undoManager?.registerUndo(withTarget: self) { graph in
            graph.revertEmbedding(embedding)
        }
        undoManager?.setActionName("Create Subgraph")
        return subgraphNode
    }

    private func applyEmbedding(_ embedding: SubgraphEmbedding)
    {
        performWithBatchedConnectionTopologyChanges {
            embedding.subgraphNode.subGraph.performWithBatchedConnectionTopologyChanges {
                withoutUndoRegistration {
                    self.addNode(embedding.subgraphNode)
                    for node in embedding.nodes {
                        self.delete(node: node, disconnect: false)
                        embedding.subgraphNode.subGraph.addNode(node)
                    }

                    for connection in embedding.internalConnections {
                        self.transferConnection(connection, to: embedding.subgraphNode.subGraph)
                    }

                    embedding.subgraphNode.subGraph.publishPorts(embedding.publishedPortStates.map(\.port))

                    for index in embedding.boundaryConnections.indices {
                        let state = embedding.boundaryConnections[index]
                        if let proxy = embedding.subgraphNode.ports.first(where: {
                            $0.id == state.innerPort.id && $0 is any ProxyPortProtocol
                        }) {
                            self.rebindConnection(state.connection, replacing: state.innerPort, with: proxy)
                            embedding.boundaryConnections[index].usesProxy = true
                        }
                        else if let outlet = state.connection.outletPort,
                                let inlet = state.connection.inletPort
                        {
                            outlet.sendBoxed(nil, force: true)
                            self.detachConnection(state.connection, outlet: outlet, inlet: inlet)
                            embedding.boundaryConnections[index].usesProxy = false
                        }
                    }

                    self.markConnectionTopologyChanged()
                    embedding.subgraphNode.subGraph.markConnectionTopologyChanged()
                }
            }
        }
    }

    private func revertEmbedding(_ embedding: SubgraphEmbedding)
    {
        let boundaryProxiesByInnerPortID = embedding.boundaryConnections.reduce(into: [UUID: Port]()) { proxies, state in
            guard state.usesProxy,
                  proxies[state.innerPort.id] == nil,
                  let proxy = embedding.subgraphNode.ports.first(where: {
                      $0.id == state.innerPort.id && $0 is any ProxyPortProtocol
                  })
            else { return }

            proxies[state.innerPort.id] = proxy
        }

        performWithBatchedConnectionTopologyChanges {
            embedding.subgraphNode.subGraph.performWithBatchedConnectionTopologyChanges {
                withoutUndoRegistration {
                    self.delete(node: embedding.subgraphNode, disconnect: false)
                    for node in embedding.nodes {
                        embedding.subgraphNode.subGraph.delete(node: node, disconnect: false)
                    }
                    // The nodes are in neither graph here, so the boundary ports take
                    // back their publishing silently; addNode then raises it.
                    for state in embedding.publishedPortStates {
                        state.port.setPublishing(state.published, name: state.publishedName)
                    }
                    for node in embedding.nodes {
                        self.addNode(node)
                    }

                    for connection in embedding.internalConnections {
                        embedding.subgraphNode.subGraph.transferConnection(connection, to: self)
                    }

                    for state in embedding.boundaryConnections {
                        let proxy = boundaryProxiesByInnerPortID[state.innerPort.id]

                        if state.usesProxy, let proxy
                        {
                            self.rebindConnection(state.connection, replacing: proxy, with: state.innerPort)
                        }
                        else if !state.usesProxy,
                                let outlet = self.nodePort(forID: state.connection.outletPortID),
                                let inlet = self.nodePort(forID: state.connection.inletPortID)
                        {
                            self.attachConnection(state.connection, outlet: outlet, inlet: inlet)
                            outlet.sendBoxed(outlet.snapshotValue(), force: true)
                        }
                    }

                    self.markConnectionTopologyChanged()
                    embedding.subgraphNode.subGraph.markConnectionTopologyChanged()
                }
            }
        }

        undoManager?.registerUndo(withTarget: self) { graph in
            graph.applyEmbedding(embedding)
        }
        undoManager?.setActionName("Create Subgraph")
    }

    /// Group plugin-owned topology changes under the plugin's own undo operation, without
    /// registering each intermediate port edit as another undo action.
    public func withoutUndoRegistration(_ operation: () -> Void)
    {
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

    /// Recursively collects all UUID-formatted string values from a JSON object
    private static func collectUUIDs(from object: Any, into uuids: inout Set<String>)
    {
        switch object
        {
        case let string as String:
            if isUUIDString(string)
            {
                uuids.insert(string)
            }

        case let array as [Any]:
            for element in array
            {
                collectUUIDs(from: element, into: &uuids)
            }

        case let dict as [String: Any]:
            for (_, value) in dict
            {
                collectUUIDs(from: value, into: &uuids)
            }

        default:
            break
        }
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

    /// Finds all UUID-formatted strings in JSON data by traversing the parsed structure
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
