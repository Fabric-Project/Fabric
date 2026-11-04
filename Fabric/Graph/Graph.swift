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
        /// Ports named by address, values by key, publishing on the graph; no
        /// port ids or envelopes. See GraphFormatMigration for the older forms.
        case addressedPorts
    }
    
    static let currentVersion = Version.addressedPorts

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
    @ObservationIgnored private var nodesWithPublishedPortsAtLastReview: Set<Node> = []
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
        case connections
        case published
        case notes
    }

    /// A wire as the document holds it: its endpoints' addresses.
    private struct SavedConnection: Codable
    {
        let from: PortAddress
        let to: PortAddress
        var active: Bool = true
    }

    /// A published port as the document holds it.
    private struct SavedPublishing: Codable
    {
        let port: PortAddress
        let name: String?
    }

    /// Lets one malformed element be skipped rather than fail its array.
    private struct Lossy<Element: Decodable>: Decodable
    {
        let element: Element?
        init(from decoder: any Decoder) throws { self.element = try? Element(from: decoder) }
    }

    /// Captures a decoder's top-level container, to decode a graph from data
    /// the migration produced.
    private struct ContainerCapture: Decodable
    {
        let container: KeyedDecodingContainer<CodingKeys>
        init(from decoder: any Decoder) throws { self.container = try decoder.container(keyedBy: CodingKeys.self) }
    }
    
    public init(context:Context, fileReferenceBaseURL: URL? = nil)
    {
        self.scene = Object(context: context)
        print("Init Graph")
        self.id = UUID()
        self.version = Self.currentVersion
        self.context = context
        self.fileReferenceBaseURL = fileReferenceBaseURL?.standardizedFileURL
        self.nodes = []
        self.notes = []
    }
    
    public required convenience init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Graph.Version.self, forKey: .version)

        guard version != Self.currentVersion else
        {
            try self.init(decoding: container, context: decodeContext)
            return
        }

        // An older form is read into the current one first, inner graphs with it.
        let saved = try decoder.singleValueContainer().decode(AnyCodable.self)
        guard let json = saved.value as? [String: Any] else
        {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A graph is an object"))
        }
        let currentVersion = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.currentVersion), options: [.fragmentsAllowed])
        let migrated = GraphFormatMigration.migrate(json, to: currentVersion)

        let migratedDecoder = JSONDecoder()
        migratedDecoder.context = decodeContext
        let capture = try migratedDecoder.decode(ContainerCapture.self, from: JSONSerialization.data(withJSONObject: migrated))
        try self.init(decoding: capture.container, context: decodeContext)
    }

    private init(decoding container: KeyedDecodingContainer<CodingKeys>, context decodeContext: DecoderContext) throws
    {
        self.context = decodeContext.documentContext
        self.fileReferenceBaseURL = decodeContext.fileReferenceBaseURL?.standardizedFileURL

        self.id = try container.decode(UUID.self, forKey: .id)
        self.version = Self.currentVersion

        self.nodes = []
        self.scene = Object(context: context)

        self.notes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
        let requiredPlugins = try container.decodeIfPresent([PluginRequirement].self, forKey: .requiredPlugins) ?? []
        let nodeRegistry = try NodeRegistry.shared
        try nodeRegistry.validatePluginRequirements(requiredPlugins)

        // Nodes decoding under this graph see it as the graph they join.
        let previousGraph = decodeContext.currentGraph
        decodeContext.currentGraph = self
        defer { decodeContext.currentGraph = previousGraph }

        var nestedContainer = try container.nestedUnkeyedContainer(forKey: .nodeMap)

        // Each node decodes from its own encoding, with the class the registry
        // names for its type.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        decoder.context = decodeContext

        while !nestedContainer.isAtEnd
        {
            let anyCodableMap = try nestedContainer.decode(AnyCodableMap.self)
            let nodeID = Self.qualifiedNodeID(fromSerializedType: anyCodableMap.type)

            do
            {
                guard let nodeClass = Self.nodeClass(forSerializedType: anyCodableMap.type, registry: nodeRegistry) else
                {
                    self.missingNodeDiagnostics.append(
                        self.makeMissingNodeDiagnostic(serializedType: anyCodableMap.type,
                                                       reason: .typeNotRegistered,
                                                       summary: "Could not find \(nodeID.nodeID)")
                    )
                    continue
                }

                let node = try decoder.decode(nodeClass, from: try encoder.encode(anyCodableMap.value))
                self.addNode(node)
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

        // Node inits are done; whatever saved state found no port to land on
        // matched nothing the code declares.
        self.droppedPortStateDiagnostics = self.makeDroppedPortStateDiagnostics()

        let savedConnections = (try container.decodeIfPresent([Lossy<SavedConnection>].self, forKey: .connections) ?? []).compactMap(\.element)
        for saved in savedConnections
        {
            guard let outlet = self.port(at: saved.from), let inlet = self.port(at: saved.to) else
            {
                self.droppedConnectionDiagnostics.append(self.makeDroppedConnectionDiagnostic(from: saved.from, to: saved.to, reason: .missingEndpoint))
                continue
            }

            // Attach bypasses validatedConnect, so the type check and its
            // diagnostic live here.
            guard outlet.kind == .Outlet, inlet.kind == .Inlet, outlet.canConnect(to: inlet) else
            {
                self.droppedConnectionDiagnostics.append(self.makeDroppedConnectionDiagnostic(from: saved.from, to: saved.to, reason: .incompatibleTypes))
                continue
            }

            let connection = Connection(outletPortID: outlet.id, inletPortID: inlet.id, active: saved.active)
            attachConnection(connection, outlet: outlet, inlet: inlet)
        }

        let savedPublishing = (try container.decodeIfPresent([Lossy<SavedPublishing>].self, forKey: .published) ?? []).compactMap(\.element)
        self.restorePublishedEntries(savedPublishing.map { PublishedPort(address: $0.port, name: $0.name) })

        self.rebuildPublishedParameterGroup()
    }

    /// The class a serialized node type decodes as: the registry's, or a
    /// retired base type's successor.
    private static func nodeClass(forSerializedType serializedType: String, registry: NodeRegistry) -> Node.Type?
    {
        let nodeID = Self.qualifiedNodeID(fromSerializedType: serializedType)
        if let nodeClass = registry.nodeClass(pluginID: nodeID.pluginID, nodeID: nodeID.nodeID) { return nodeClass }

        switch serializedType
        {
        // MARK: - Deprecated Node Types -> BaseImageNode
        case "BaseImageNode", "BaseEffectThreeChannelNode", "BaseEffectTwoChannelNode", "BaseEffectNode", "BaseGeneratorNode":
            return BaseImageNode.self
        case "LiveEffectNode":
            return LiveImageNode.self
        default:
            return nil
        }
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
        try container.encode(self.connections.compactMap { connection -> SavedConnection? in
            guard let outlet = connection.outletPort.flatMap(self.address(of:)),
                  let inlet = connection.inletPort.flatMap(self.address(of:))
            else { return nil }
            return SavedConnection(from: outlet, to: inlet, active: connection.active)
        }, forKey: .connections)
        try container.encode(self.publishedPortEntries.map { SavedPublishing(port: $0.address, name: $0.name) }, forKey: .published)
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

            for port in node.ports where port.control == .filePicker
            {
                port.valueDidChange = true
                hasFileReference = true
            }

            if hasFileReference
            {
                node.markDirty()
            }

            (node as? any NodeMadeFromFile)?.fileReferenceBaseDidChange(standardizedURL)

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
                      filePort.control == .filePicker,
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
        guard nodes.contains(where: { $0 === node }) else { return }

        let savedOffset = node.offset
        let savedPublishing = self.removePublishedEntries(of: node)
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
                                     connections: savedConnections,
                                     publishing: savedPublishing)
        }

        self.undoManager?.setActionName("Delete Node")
        self.markConnectionsChanged()

        self.updateCameraSelection()
        self.rebuildPublishedParameterGroup()
    }

    private func restoreDeletedNode(_ node: Node,
                                    offset: CGSize,
                                    connections: [Connection],
                                    publishing: [PublishedPort])
    {
        withoutUndoRegistration {
            node.offset = offset
            restorePublishedEntries(publishing)
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
            rebuildPublishedParameterGroup()
            syncNodesToScene()
            markConnectionsChanged()
        }

        undoManager?.registerUndo(withTarget: self) { graph in
            graph.delete(node: node)
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

    /// Takes the wires off a port its node has just retired from its registry,
    /// as undo steps of the edit in progress.
    internal func disconnectAll(fromRetired port: Port)
    {
        guard port.node?.graph === self else { return }

        for connection in port.connections where connection.graph === self
        {
            disconnect(connection)
        }
    }

    /// Moves every wire on `old` that `new`, its retyped replacement under the
    /// same key, can take onto `new`, and disconnects the rest as undo steps.
    internal func rebindWires(from old: Port, to new: Port)
    {
        let wires = old.connections.filter { $0.graph === self }
        guard !wires.isEmpty else { return }

        for connection in wires
        {
            guard let opposite = connection.port(opposite: old),
                  new.kind == .Outlet ? new.canConnect(to: opposite) : opposite.canConnect(to: new)
            else
            {
                self.disconnect(connection)
                continue
            }

            self.rebindConnection(connection, replacing: old, with: new)
            if let outlet = connection.outletPort { outlet.sendBoxed(outlet.snapshotValue(), force: true) }
        }
        self.markConnectionTopologyChanged()
    }

    /// A control's edit of a port's value. The one way a control writes a
    /// port: the edit context attaches here to record value edits.
    public func setControlValue<Value>(_ value: Value, on port: NodePort<Value>)
    {
        guard port.node?.graph === self else { return }
        port.value = value
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

    private func attachConnection(_ connection: Connection, outlet: Port, inlet: Port)
    {
        connection.graph = self
        connection.outletPortReference = outlet
        connection.inletPortReference = inlet
        connections.append(connection)

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

    /// One published port: where it is, and the name the boundary shows for it,
    /// nil for the port's own.
    public struct PublishedPort: Hashable
    {
        public let address: PortAddress
        public let name: String?
    }

    /// The ports this graph publishes to the graph around it, in the order they
    /// were published. A relation from address to name, as wires are: the port
    /// carries none of it.
    public private(set) var publishedPortEntries: [PublishedPort] = []

    /// Where `port` is in this graph; nil for a port on no node of it.
    public func address(of port: Port) -> PortAddress?
    {
        guard let node = port.node, node.graph === self else { return nil }
        return PortAddress(node: node.id, key: port.key)
    }

    /// The port at `address`, if its node is in this graph and declares it.
    public func port(at address: PortAddress) -> Port?
    {
        self.node(forID: address.node)?.port(forKey: address.key)
    }

    public func isPublished(_ port: Port) -> Bool
    {
        guard let address = self.address(of: port) else { return false }
        return self.publishedPortEntries.contains { $0.address == address }
    }

    /// The name the boundary shows for `port`, where one was given.
    public func publishedName(of port: Port) -> String?
    {
        guard let address = self.address(of: port) else { return nil }
        return self.publishedPortEntries.first { $0.address == address }?.name
    }

    /// Publishes or unpublishes `port`, a port of a node in this graph, as an
    /// undo step. Publishing gives it `name`; unpublishing forgets its name.
    public func setPublished(_ published: Bool, port: Port, name: String? = nil)
    {
        guard let address = self.address(of: port) else { return }
        self.setPublished(published, at: address, name: name)
    }

    /// Renames a published port as an undo step; nil restores its own name.
    public func setPublishedName(_ name: String?, port: Port)
    {
        guard let address = self.address(of: port),
              let index = self.publishedPortEntries.firstIndex(where: { $0.address == address }),
              self.publishedPortEntries[index].name != name
        else { return }

        let previous = self.publishedPortEntries[index].name
        self.publishedPortEntries[index] = PublishedPort(address: address, name: name)
        self.rebuildPublishedParameterGroup()

        self.undoManager?.registerUndo(withTarget: self) { graph in
            guard let port = graph.port(at: address) else { return }
            graph.setPublishedName(previous, port: port)
        }
        self.undoManager?.setActionName("Rename Published Port")
    }

    private func setPublished(_ published: Bool, at address: PortAddress, name: String?)
    {
        let existing = self.publishedPortEntries.firstIndex { $0.address == address }
        switch (published, existing)
        {
        case (true, nil):
            self.publishedPortEntries.append(PublishedPort(address: address, name: name))
            self.undoManager?.registerUndo(withTarget: self) { graph in graph.setPublished(false, at: address, name: nil) }
            self.undoManager?.setActionName("Publish Port")
        case (false, let index?):
            let removed = self.publishedPortEntries.remove(at: index)
            self.undoManager?.registerUndo(withTarget: self) { graph in graph.setPublished(true, at: address, name: removed.name) }
            self.undoManager?.setActionName("Unpublish Port")
        default:
            return
        }
        self.rebuildPublishedParameterGroup()
    }



    /// Takes the entries for `node` out of the relation, handing them back in
    /// order for a restore. Not an undo step: the caller's own step restores.
    private func removePublishedEntries(of node: Node) -> [PublishedPort]
    {
        let removed = self.publishedPortEntries.filter { $0.address.node == node.id }
        guard !removed.isEmpty else { return [] }
        self.publishedPortEntries.removeAll { $0.address.node == node.id }
        return removed
    }

    private func restorePublishedEntries(_ entries: [PublishedPort])
    {
        for entry in entries where !self.publishedPortEntries.contains(where: { $0.address == entry.address })
        {
            self.publishedPortEntries.append(entry)
        }
    }

    /// All ports in this graph that have been published, in publishing order,
    /// resolved from their addresses when publishing or the ports change, so
    /// a frame reads them without a lookup.
    public func getPublishedPorts() -> [Port]
    {
        self.resolvedPublishedPorts
    }

    @ObservationIgnored private var resolvedPublishedPorts: [Port] = []

    public func publishedInputPorts() -> [Port]
    {
        self.getPublishedPorts().filter { $0.kind == .Inlet }
    }

    public func publishedOutputPorts() -> [Port]
    {
        if cachedPublishedOutputPortsRevision == connectionRevision {
            return cachedPublishedOutputPorts
        }

        cachedPublishedOutputPorts = self.getPublishedPorts().filter { $0.kind == .Outlet }
        cachedPublishedOutputPortsRevision = connectionRevision

        return cachedPublishedOutputPorts
    }

    public func rebuildPublishedParameterGroup()
    {
        self.resolvedPublishedPorts = self.publishedPortEntries.compactMap { self.port(at: $0.address) }
        self.cachedPublishedOutputPortsRevision = nil
        self.publishedParameterGroup.clear()
        self.publishedParameterGroup.append(self.getPublishedPorts().compactMap(\.parameter))

        // A published port connects its node through the enclosing subgraph node.
        let nodesWithPublishedPorts = Set(self.nodesWithPublishedPorts())
        for node in nodesWithPublishedPorts.symmetricDifference(self.nodesWithPublishedPortsAtLastReview)
        {
            self.markNodeForLifecycleReview(node)
        }
        self.nodesWithPublishedPortsAtLastReview = nodesWithPublishedPorts

        self.markConnectionsChanged()
        self.onPublishedPortsChanged?()
    }

    internal func nodesWithPublishedPorts() -> [Node]
    {
        let nodeIDs = Set(self.publishedPortEntries.map(\.address.node))
        return self.nodes.filter { nodeIDs.contains($0.id) }
    }

    internal func publishedPorts(of node: Node) -> [Port]
    {
        self.resolvedPublishedPorts.filter { $0.node === node }
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
        /// What the graph around published of the moved nodes, before the move.
        let outerPublishing: [PublishedPort]

        init(nodes: [Node],
             subgraphNode: SubgraphNode,
             internalConnections: [Connection],
             boundaryConnections: [BoundaryConnectionState],
             outerPublishing: [PublishedPort])
        {
            self.nodes = nodes
            self.subgraphNode = subgraphNode
            self.internalConnections = internalConnections
            self.boundaryConnections = boundaryConnections
            self.outerPublishing = outerPublishing
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
        let outerPublishing = self.publishedPortEntries.filter { selectedNodeIDs.contains($0.address.node) }

        let subgraphNode = subgraphClass.init(context: context)
        subgraphNode.offset = node.offset
        subgraphNode.subGraph.undoManager = undoManager
        let embedding = SubgraphEmbedding(nodes: nodes,
                                          subgraphNode: subgraphNode,
                                          internalConnections: internalConnections,
                                          boundaryConnections: boundaryConnections,
                                          outerPublishing: outerPublishing)

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

                    // The moved nodes keep what they published, and every port a
                    // boundary wire ran to is published so a proxy can carry it.
                    let innerGraph = embedding.subgraphNode.subGraph
                    innerGraph.restorePublishedEntries(embedding.outerPublishing)
                    innerGraph.restorePublishedEntries(embedding.boundaryConnections.compactMap { state in
                        innerGraph.address(of: state.innerPort).map { PublishedPort(address: $0, name: nil) }
                    })
                    embedding.subgraphNode.subGraph.rebuildPublishedParameterGroup()

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

                    self.restorePublishedEntries(embedding.outerPublishing)
                    self.rebuildPublishedParameterGroup()
                    embedding.subgraphNode.subGraph.rebuildPublishedParameterGroup()

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

    /// Decodes a single node from an AnyCodableMap, as Graph.init(from:) does,
    /// and closes its decode window: a port it declares later takes no saved
    /// state.
    private func decodeNode(from map: AnyCodableMap) -> Node?
    {
        do
        {
            let decoder = JSONDecoder()
            decoder.context = DecoderContext(documentContext: self.context)

            guard let nodeClass = Self.nodeClass(forSerializedType: map.type, registry: try NodeRegistry.shared) else
            {
                print("decodeNode: Failed to find nodeClass for \(map.type)")
                return nil
            }

            let node = try decoder.decode(nodeClass, from: try JSONEncoder().encode(map.value))
            _ = node.finalizePortHydration()
            return node
        }
        catch
        {
            print("decodeNode: Failed to decode node of type \(map.type): \(error)")
            return nil
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

    // MARK: - Copies

    /// Nodes as a copy holds them: their encodings, and the wires and
    /// publishing among them, by address.
    private struct NodeCopies: Codable
    {
        let nodeEntries: [AnyCodableMap]
        let connections: [SavedConnection]
        let published: [SavedPublishing]
    }

    private func copies(of nodes: [Node]) throws -> NodeCopies
    {
        let nodeIDs = Set(nodes.map(\.id))
        let entries = try nodes.map { node in
            AnyCodableMap(type: try self.qualifiedNodeID(for: type(of: node)).description, value: AnyCodable(node))
        }
        let connections = self.connections.compactMap { connection -> SavedConnection? in
            guard let outlet = connection.outletPort.flatMap(self.address(of:)),
                  let inlet = connection.inletPort.flatMap(self.address(of:)),
                  nodeIDs.contains(outlet.node), nodeIDs.contains(inlet.node)
            else { return nil }
            return SavedConnection(from: outlet, to: inlet, active: connection.active)
        }
        let published = self.publishedPortEntries
            .filter { nodeIDs.contains($0.address.node) }
            .map { SavedPublishing(port: $0.address, name: $0.name) }
        return NodeCopies(nodeEntries: entries, connections: connections, published: published)
    }

    /// Adds `copies` to the graph as new nodes, offset, under fresh node ids:
    /// node ids are rewritten wherever the copy names them, inner graphs'
    /// included, and nothing else is. One undo group.
    private func insert(_ copies: NodeCopies, offset: CGSize, actionName: String) throws -> [Node]
    {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(copies))

        var nodeIDs = Set<String>()
        Self.collectNodeIDs(in: json, into: &nodeIDs)
        let remap = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, UUID().uuidString) })
        let rewritten = try JSONDecoder().decode(NodeCopies.self,
                                                 from: JSONSerialization.data(withJSONObject: Self.remapStrings(in: json, remap: remap)))

        let newNodes = rewritten.nodeEntries.compactMap { self.decodeNode(from: $0) }
        for node in newNodes { node.offset = node.offset + offset }

        self.undoManager?.beginUndoGrouping()
        for node in newNodes { self.addNode(node) }
        for connection in rewritten.connections
        {
            guard let outlet = self.port(at: connection.from), let inlet = self.port(at: connection.to) else { continue }
            if let wire = self.connect(outlet, to: inlet), !connection.active { self.setConnection(wire, active: false) }
        }
        for entry in rewritten.published
        {
            guard let port = self.port(at: entry.port) else { continue }
            self.setPublished(true, port: port, name: entry.name)
        }
        self.undoManager?.endUndoGrouping()
        self.undoManager?.setActionName(actionName)

        self.deselectAllNodes()
        for node in newNodes { nodeViewModels[node.id]?.isSelected = true }
        self.markConnectionsChanged()
        return newNodes
    }

    /// The id of every node in an encoded graph or copy, inner graphs' too.
    private static func collectNodeIDs(in object: Any, into ids: inout Set<String>)
    {
        if let entries = object as? [Any]
        {
            for entry in entries { collectNodeIDs(in: entry, into: &ids) }
        }
        guard let dictionary = object as? [String: Any] else { return }

        if let value = dictionary["value"] as? [String: Any], dictionary["type"] is String
        {
            if let id = value["id"] as? String { ids.insert(id) }
            if let subGraph = value["subGraph"] { collectNodeIDs(in: subGraph, into: &ids) }
        }
        if let entries = dictionary["nodeEntries"] { collectNodeIDs(in: entries, into: &ids) }
        if let nodeMap = dictionary["nodeMap"] { collectNodeIDs(in: nodeMap, into: &ids) }
    }

    /// `object` with every string `remap` names replaced.
    private static func remapStrings(in object: Any, remap: [String: String]) -> Any
    {
        switch object
        {
        case let string as String:
            return remap[string] ?? string
        case let array as [Any]:
            return array.map { remapStrings(in: $0, remap: remap) }
        case let dictionary as [String: Any]:
            return dictionary.mapValues { remapStrings(in: $0, remap: remap) }
        default:
            return object
        }
    }

    /// Duplicates the given nodes, preserving the wires and publishing among
    /// them, and adds them to the graph.
    @discardableResult
    public func duplicateNodes(_ nodesToDuplicate: [Node], offset: CGSize = CGSize(width: 20, height: 20)) -> [Node]
    {
        guard !nodesToDuplicate.isEmpty else { return [] }

        do
        {
            return try self.insert(try self.copies(of: nodesToDuplicate), offset: offset, actionName: "Duplicate Nodes")
        }
        catch
        {
            print("duplicateNodes: Failed: \(error)")
            return []
        }
    }
}

#if os(macOS)
extension Graph
{
    // MARK: - Copy / Paste / Duplicate

    public static let nodeClipboardType = NSPasteboard.PasteboardType("info.vade.fabric.nodes")

    /// Copies selected nodes and the wires and publishing among them to the
    /// system pasteboard.
    public func copyNodesToPasteboard(_ nodes: [Node])
    {
        guard !nodes.isEmpty else { return }

        do
        {
            let data = try JSONEncoder().encode(try self.copies(of: nodes))
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
            return try self.insert(try JSONDecoder().decode(NodeCopies.self, from: data), offset: offset, actionName: "Paste Nodes")
        }
        catch
        {
            print("pasteNodesFromPasteboard: Failed: \(error)")
            return []
        }
    }
}
#endif
