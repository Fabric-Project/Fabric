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
    }

    /// Port state a document carried for registry keys the node's code no
    /// longer declares or rebuilds. That state (and any wires into those
    /// ports) is dropped on load — deliberately, the code owns the port set —
    /// and surfaced here so hosts can warn instead of losing data silently.
    public struct DroppedPortStateDiagnostic
    {
        public let nodeID: UUID
        public let nodeTitle: String
        public let droppedRegistryKeys: [String]
    }

    /// A saved wire the decode-time connection restore could not re-establish:
    /// an endpoint no longer exists (its port was retired, or its node failed
    /// to decode) or its port's type changed to something incompatible since
    /// the save. Wires are the destructive loss on load, so hosts should
    /// surface these.
    public struct DroppedConnectionDiagnostic
    {
        public enum Reason
        {
            case missingEndpoint
            case incompatibleTypes
        }

        public let portID: UUID
        public let otherPortID: UUID
        public let reason: Reason

        /// Endpoints named as "node.port" where they still resolve.
        public let summary: String
    }
    
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

    /// Populated once at decode; empty for graphs built programmatically.
    @ObservationIgnored public private(set) var droppedPortStateDiagnostics: [DroppedPortStateDiagnostic] = []

    /// Populated once at decode; empty for graphs built programmatically.
    @ObservationIgnored public private(set) var droppedConnectionDiagnostics: [DroppedConnectionDiagnostic] = []

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

    public let publishedParameterGroup:ParameterGroup = ParameterGroup("Published")

    /// Called when the set of published ports changes. SubgraphNode uses
    /// this to rebuild its proxy ports without polling.
    @ObservationIgnored var onPublishedPortsChanged: (() -> Void)?

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
    
    public init(context:Context)
    {
        self.scene = Object(context: context)
        print("Init Graph")
        self.id = UUID()
        self.version = .alpha1
        self.context = context
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
            do {
                
                let anyCodableMap = try nestedContainer.decode(AnyCodableMap.self)
                
//                print(anyCodableMap.type)
//                print(anyCodableMap.value)
                
                let nodeID = Self.qualifiedNodeID(fromSerializedType: anyCodableMap.type)

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
                    throw FabricError(.deserialization(.nodeNotFound),
                                      severity: .fatal,
                                      message: "Could not find node '\(nodeID.nodeID)' in plugin '\(nodeID.pluginID)'")
                }
            }
            catch
            {
                throw error
            }
        }
        
        // Node inits (including their dynamic-port rebuilds) are done; end
        // each node's hydration window. Whatever state remains unconsumed
        // matched nothing the code declares, and closing the window here means
        // ports added later in the document's life cannot resurrect stale
        // snapshot state.
        self.droppedPortStateDiagnostics = self.nodes.compactMap { node in
            let droppedKeys = node.finalizePortHydration()
            guard !droppedKeys.isEmpty else { return nil }
            print("Graph decode: '\(node.title)' dropped port state for retired keys \(droppedKeys)")
            return DroppedPortStateDiagnostic(nodeID: node.id,
                                              nodeTitle: node.title,
                                              droppedRegistryKeys: droppedKeys)
        }

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
            guard reportedDroppedPairs.insert(Set([portID, otherPortID])).inserted else { return }

            func describe(_ id: UUID) -> String
            {
                guard let port = portsByID[id] else { return "missing port \(id)" }
                return "\(port.node?.title ?? "?").\(port.displayName)"
            }

            let diagnostic = DroppedConnectionDiagnostic(portID: portID,
                                                         otherPortID: otherPortID,
                                                         reason: reason,
                                                         summary: "\(describe(portID)) ↔ \(describe(otherPortID))")
            print("Graph decode: dropped connection (\(reason)): \(diagnostic.summary)")
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
        try container.encode(self.version, forKey: .version)
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

        self.undoManager?.registerUndo(withTarget: self) { graph in
            graph.delete(node: node)
        }

        self.undoManager?.setActionName("Add Node")
        self.markConnectionsChanged()

        self.updateRenderingNodes()
        self.rebuildPublishedParameterGroup()
    }

    
    
    public func delete(node:Node, disconnect:Bool = true)
    {
        guard nodes.contains(where: { $0 === node }) else { return }

        let savedOffset = node.offset
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

            self.maybeDeleteNodeFromScene(node)
            self.nodes.removeAll { $0.id == node.id }
            node.graph = nil
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

        self.updateRenderingNodes()
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
            maybeAddNodeToScene(node)

            for connection in connections where connection.graph == nil {
                restore(connection)
            }

            node.markDirty()
            updateRenderingNodes()
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
        }

        if let newNode = newPort.node,
           let oppositeNode = connection.port(opposite: newPort)?.node
        {
            newNode.didConnectToNode(oppositeNode)
            oppositeNode.didConnectToNode(newNode)
            newNode.updateConnectionTopology()
            oppositeNode.updateConnectionTopology()
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
    internal var consumerNodes: [Node] = []
    internal var sceneObjectNodes:[BaseObjectNode] = []
    internal var latestCamera:Camera? = nil
    
    func updateRenderingNodes()
    {
        self.consumerNodes = self.nodes.filter( { $0.nodeExecutionMode == .Consumer } )
        
        self.latestCamera = Self.latestCamera(in:self)
    }
    
    /// The camera a graph renders with: the last one added to it, so a camera
    /// added to a graph that has one takes control rather than joining a queue
    /// behind it. One camera is active at a time; the rest are in the scene and
    /// inert.
    static func latestCamera(in graph:Graph) -> Camera?
    {
        let sceneObjectNodes:[BaseObjectNode] = graph.consumerNodes.compactMap({ $0 as? BaseObjectNode})

        let latestCameraNode = sceneObjectNodes.last(where: { $0.nodeType == .Object(objectType: .Camera)})

        let camera = latestCameraNode?.getObject() as? Camera
        
        // Only recurse if we need to
        guard let camera else
        {
            let subGraphNodes:[SubgraphNode] = graph.consumerNodes.compactMap({
                
                // We dont want to leak a Deferred Rendering camera out
                if let _ =  $0 as? DeferredSubgraphNode
                {
                    return nil
                }
                
                return $0 as? SubgraphNode
            })
                
            let subGraphs = subGraphNodes.map({ $0.subGraph } )
            
            for subGraph in subGraphs.reversed() {
                if let camera = latestCamera(in: subGraph) {
                    return camera
                }
            }
            
            return nil
        }

        return camera
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

                    for state in embedding.publishedPortStates {
                        state.port.published = true
                    }
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

                    for state in embedding.publishedPortStates {
                        state.port.published = state.published
                        state.port.publishedName = state.publishedName
                    }
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

    internal func withoutUndoRegistration(_ operation: () -> Void)
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
