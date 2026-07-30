//
//  NodeGraph.swift
//  v
//
//  Created by Anton Marini on 2/1/25.
//
import SwiftUI
import Satin
import os
internal import AnyCodable

public struct Connection: Codable, Identifiable, Hashable
{
    public let id: UUID
    public let outletPortID: UUID
    public let inletPortID: UUID
    public var active: Bool

    public init(id: UUID = UUID(), outletPortID: UUID, inletPortID: UUID, active: Bool = true)
    {
        self.id = id
        self.outletPortID = outletPortID
        self.inletPortID = inletPortID
        self.active = active
    }
}

@Observable public class Graph : Codable, Identifiable, Hashable, Equatable
{
    public enum Version : Codable
    {
        case alpha1
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
    internal var connections: [Connection] = []

    /// The cached execution plan. Written only from rebuildNodesInExecutionOrderIfNeeded,
    /// which GraphRenderer calls at the top of each execute pass — on the execute thread,
    /// never mid-frame. @ObservationIgnored: SwiftUI must not track state that mutates on
    /// the execute thread.
    @ObservationIgnored internal private(set) var nodesInExecutionOrder: [Node] = []

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

    var needsExecution:Bool {
        self.nodes.reduce(false) { (result, node) -> Bool in
            result || node.isDirty
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

    /// Topology marks only set this flag; the plan rebuild is deferred to
    /// rebuildNodesInExecutionOrderIfNeeded at the top of the next execute pass.
    /// Routing nodes mark from inside execute() on the execute thread while the UI
    /// marks from the main thread, so this flag is the one piece of cross-thread
    /// state and is lock-protected.
    @ObservationIgnored private let executionPlanIsStale = OSAllocatedUnfairLock(initialState: true)

    @ObservationIgnored private var cachedPublishedOutputPortsRevision: Int?
    @ObservationIgnored private var cachedPublishedOutputPorts: [Port] = []


    @ObservationIgnored weak var lastNode:(Node)? = nil

    public func markConnectionTopologyChanged()
    {
        connectionRevision += 1
        pendingConnectionSceneSync = true
        executionPlanIsStale.withLock { $0 = true }
    }

    public func markExecutionTopologyChanged()
    {
        executionPlanIsStale.withLock { $0 = true }
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
        
        let decodedConnections = try container.decodeIfPresent([Connection].self, forKey: .connections)
        let portMap = try container.decode([UUID:[UUID]].self, forKey: .portConnectionMap)
        
        for portID in portMap.keys
        {
            if let port = self.nodePort(forID: portID)
            {
                let portConnections = portMap[portID] ?? []
                
                for connectedPortID in portConnections
                {
                    if let connectedPort = self.nodePort(forID: connectedPortID)
                    {
                        port.connect(to: connectedPort)
                    }
                }
            }
        }

        if let decodedConnections {
            self.connections = decodedConnections.filter {
                self.nodePort(forID: $0.outletPortID) != nil &&
                self.nodePort(forID: $0.inletPortID) != nil
            }
        }
        
        self.rebuildPublishedParameterGroup()
        self.rebuildNodesInExecutionOrderIfNeeded()
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
        
        // encode a connection map for each port
        
        let allPorts = self.nodes.flatMap( { $0.ports } )
        
        let allPortConnections:[UUID:[UUID]] = allPorts.reduce(into: [:]) { map, port in
            
            if port.connections.isEmpty { return }
            
            map[port.id] = port.connections.map( { $0.id } )
        }
        
        try container.encode(allPortConnections, forKey: .portConnectionMap)
    }

    public func addNote(_ note: Note)
    {
        self.notes.append(note)
    }
    
    public func deleteNote(_ note:Note)
    {
        self.notes.removeAll(where: { $0.id == note.id })
    }
    
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
        print("Graph: \(self.id) Add Node", node.name)
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
    
    public func delete(node:Node, disconnect:Bool = true)
    {
        let savedOffset = node.offset
        let savedConnections = node.ports.flatMap { port in
            port.connections.map { (port, $0) }
        }

        if disconnect
        {
            node.ports.forEach { $0.disconnectAll() }
        }

        self.maybeDeleteNodeFromScene(node)
        self.nodes.removeAll { $0.id == node.id }
        // Remove ViewModel after removing from nodes so any in-flight
        // ForEach evaluation still finds it.
        self.nodeViewModels[node.id] = nil

        self.undoManager?.registerUndo(withTarget: self) { graph in
            node.offset = savedOffset
            // Recreate the ViewModel before appending to nodes (same ordering
            // as addNode) so SwiftUI always finds it during re-render.
            graph.nodeViewModels[node.id] = NodeViewModel(node: node)
            graph.nodes.append(node)
            node.graph = graph
            graph.maybeAddNodeToScene(node)
            graph.markConnectionsChanged()

            for (port, connectedPort) in savedConnections {
                port.connect(to: connectedPort)
            }

            node.markDirty()
            graph.updateRenderingNodes()
            graph.rebuildPublishedParameterGroup()
            graph.syncNodesToScene()
            graph.markConnectionsChanged()
        }

        self.undoManager?.setActionName("Delete Node")
        self.markConnectionsChanged()

        self.updateRenderingNodes()
        self.rebuildPublishedParameterGroup()
    }
    
    public func node(forID:UUID) -> Node?
    {
        return self.nodes.first(where: { $0.id == forID })
    }

    public func nodePort(forID:UUID) -> Port?
    {
        let allPorts = self.nodes.flatMap(\.ports)
        return allPorts.first(where: { $0.id == forID })
    }

    private func normalizedConnectionPorts(_ portA: Port, _ portB: Port) -> (outlet: Port, inlet: Port)?
    {
        if portA.kind == .Outlet, portB.kind == .Inlet {
            return (portA, portB)
        }

        if portA.kind == .Inlet, portB.kind == .Outlet {
            return (portB, portA)
        }

        return nil
    }

    func registerConnection(between portA: Port, and portB: Port)
    {
        guard let normalized = normalizedConnectionPorts(portA, portB) else { return }
        guard !connections.contains(where: {
            $0.outletPortID == normalized.outlet.id && $0.inletPortID == normalized.inlet.id
        }) else { return }

        connections.append(Connection(outletPortID: normalized.outlet.id,
                                      inletPortID: normalized.inlet.id))
        markConnectionTopologyChanged()
    }

    @discardableResult
    func unregisterConnection(between portA: Port, and portB: Port) -> Bool
    {
        guard let normalized = normalizedConnectionPorts(portA, portB) else { return false }
        let oldCount = connections.count
        connections.removeAll {
            $0.outletPortID == normalized.outlet.id && $0.inletPortID == normalized.inlet.id
        }

        if connections.count != oldCount {
            markConnectionTopologyChanged()
            return true
        }

        return false
    }

    public func setConnectionActive(_ active: Bool, connectionID: UUID)
    {
        guard let index = connections.firstIndex(where: { $0.id == connectionID }),
              connections[index].active != active
        else { return }

        connections[index].active = active
        markExecutionTopologyChanged()
    }

    public func setActiveInletPorts(forNodeID nodeID: UUID, inletPortIDs: Set<UUID>)
    {
        guard let node = node(forID: nodeID) else { return }
        let nodeInletIDs = Set(node.inputPorts().map(\.id))
        var changed = false

        for index in connections.indices where nodeInletIDs.contains(connections[index].inletPortID) {
            let active = inletPortIDs.contains(connections[index].inletPortID)
            if connections[index].active != active {
                connections[index].active = active
                changed = true
            }
        }

        if changed {
            markExecutionTopologyChanged()
        }
    }

    func outletPortsConnectedToActiveConnection(for inlet: Port) -> [Port]
    {
        connections.compactMap { connection in
            guard connection.active,
                  connection.inletPortID == inlet.id
            else { return nil }

            return nodePort(forID: connection.outletPortID)
        }
    }

    /// The single point where the cached execution plan is rebuilt. GraphRenderer calls
    /// this at the top of each execute pass, so the plan never changes mid-frame and
    /// rebuilds at most once per frame however many topology marks arrived since the
    /// last pass — an animated route index costs a flag set, not a planning walk.
    func rebuildNodesInExecutionOrderIfNeeded()
    {
        let wasStale = executionPlanIsStale.withLock { isStale in
            defer { isStale = false }
            return isStale
        }

        guard wasStale else { return }

        rebuildNodesInExecutionOrder()
    }

    private func rebuildNodesInExecutionOrder()
    {
        var ordered: [Node] = []
        ordered.reserveCapacity(nodes.count)

        var processingStates: [UUID: GraphExecutionPlanningState] = [:]

        for root in executionRoots() {
            pullNodeForExecutionPlan(node: root.node,
                                     requestedOutputPort: root.requestedOutputPort,
                                     processingStates: &processingStates,
                                     orderedNodes: &ordered)
        }

        nodesInExecutionOrder = ordered
    }

    private enum GraphExecutionPlanningState
    {
        case processing
        case processed
        case keepAliveWalked
        case declined
    }

    private func executionRoots() -> [(node: Node, requestedOutputPort: Port?)]
    {
        var roots: [(node: Node, requestedOutputPort: Port?)] = nodes
            .filter { $0.nodeExecutionMode == .Consumer }
            .map { ($0, nil) }

        for outputPort in publishedOutputPorts() {
            guard let node = outputPort.node else { continue }
            roots.append((node, outputPort))
        }

        return roots
    }

    @discardableResult
    private func pullNodeForExecutionPlan(node: Node,
                                          requestedOutputPort: Port?,
                                          processingStates: inout [UUID: GraphExecutionPlanningState],
                                          orderedNodes: inout [Node]) -> Bool
    {
        switch node.respondToPull(requestedOutputPort: requestedOutputPort) {
        case .declined(let keepAlivePorts):
            if processingStates[node.id] == nil {
                processingStates[node.id] = .keepAliveWalked
                for inputPort in keepAlivePorts {
                    pullInletConnectionsForExecutionPlan(inputPort,
                                                         processingStates: &processingStates,
                                                         orderedNodes: &orderedNodes)
                }
            }
            return false

        case .evaluate(let pullingPorts):
            switch processingStates[node.id] {
            case .processed, .processing:
                return true
            case .declined:
                return false
            case .keepAliveWalked, nil:
                break
            }

            processingStates[node.id] = .processing

            var attemptedPullCount = 0
            var activePullCount = 0

            for inputPort in pullingPorts {
                let pulled = pullInletConnectionsForExecutionPlan(inputPort,
                                                                  processingStates: &processingStates,
                                                                  orderedNodes: &orderedNodes)
                attemptedPullCount += pulled.attempted
                activePullCount += pulled.active
            }

            if attemptedPullCount > 0 && activePullCount == 0 {
                processingStates[node.id] = .declined
                return false
            }

            orderedNodes.append(node)
            processingStates[node.id] = .processed
            return true
        }
    }

    @discardableResult
    private func pullInletConnectionsForExecutionPlan(_ inputPort: Port,
                                                      processingStates: inout [UUID: GraphExecutionPlanningState],
                                                      orderedNodes: inout [Node]) -> (attempted: Int, active: Int)
    {
        var attempted = 0
        var active = 0

        for outletPort in outletPortsConnectedToActiveConnection(for: inputPort) {
            guard let node = outletPort.node else { continue }

            attempted += 1
            if pullNodeForExecutionPlan(node: node,
                                        requestedOutputPort: outletPort,
                                        processingStates: &processingStates,
                                        orderedNodes: &orderedNodes) {
                active += 1
            }
        }

        return (attempted, active)
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
    internal var firstCamera:Camera? = nil
    
    func updateRenderingNodes()
    {
        self.consumerNodes = self.nodes.filter( { $0.nodeExecutionMode == .Consumer } )
        
        self.firstCamera = Self.getFirstCamera(graph:self)
    }
    
    static func getFirstCamera(graph:Graph) -> Camera?
    {
        let sceneObjectNodes:[BaseObjectNode] = graph.consumerNodes.compactMap({ $0 as? BaseObjectNode})

        let firstCameraNode = sceneObjectNodes.first(where: { $0.nodeType == .Object(objectType: .Camera)})

        let camera = firstCameraNode?.getObject() as? Camera
        
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
            
            for subGraph in subGraphs {
                if let camera = getFirstCamera(graph: subGraph) {
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
                
                print(referenceNode.name, referenceNode.offset, angle, direction, "to:", $0.name, $0.offset)
                return (distance, direction, $0 )
            }
            
            let relevantDistanceDirectionNodeTuples = distanceDirectionNodeTuples.filter { $0.Direction == direction }
            
            if let closestDistanceDirectionNodeTuples = relevantDistanceDirectionNodeTuples.sorted(by: { $0.Distance < $1.Distance }).first
            {
                print("reference node", referenceNode.name)

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

    func createSubgraphFromSelection(centeredOnNode node:Node, usingClass subgraphClass:SubgraphNode.Type)
    {
        let selectedNodes = self.selectedNodes
        
        let subGraphNode = subgraphClass.init(context: self.context)
        subGraphNode.offset = node.offset
        
        // remove the node from our graph, but maintain connections
        // add to new graph
        
        self.undoManager?.beginUndoGrouping()

        // add the new subgraph
        self.addNode(subGraphNode)
        self.undoManager?.registerUndo(withTarget: subGraphNode) { self.delete(node:$0) }
        
        for node in selectedNodes
        {
            self.delete(node: node, disconnect: false)
            subGraphNode.subGraph.addNode(node)
            
            // Register Undo for node adding
            self.undoManager?.registerUndo(withTarget: node) { node in
                subGraphNode.subGraph.delete(node: node, disconnect: false)
                self.addNode(node)
            }
        }
                
        self.undoManager?.endUndoGrouping()
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
//            print("Graph: \(self.id) Scene: Added Child", objectNode.name)
            self.scene.add( object )
        }
        else
        {
//            print("Graph: \(self.id) Scene: Skipped Child", node.name)
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

    /// Decodes a single node from an AnyCodableMap, replicating the type resolution from Graph.init(from:)
    private func decodeNode(from map: AnyCodableMap) -> Node?
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
                let internalConnections = port.connections
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
                print("duplicateNodes: Failed to encode \(node.name): \(error)")
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

                newPort.connect(to: newConnectedPort)
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

                    newPort.connect(to: newConnectedPort)
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
