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

    var needsExecution:Bool {
        self.nodes.reduce(true) { (result, node) -> Bool in
            result || node.isDirty
        }
    }
    
    var scene:Object = Object()
    
    var renderables: [Satin.Renderable] {
        let allNodes = self.nodes
        
        let renderableNodes:[BaseObjectNode] = allNodes.compactMap{ $0 as? BaseObjectNode } //.compactMap( { $0 as? BaseRenderableNode })
            
        return renderableNodes.compactMap { $0.getObject() as? Satin.Renderable }
    }
    
    // Fix for #103 - this now triggers syncNodesToScene() inside of `GraphRenderer`
    public var shouldUpdateConnections = false
  

    var dragPreviewSourcePortID: UUID? = nil
    var dragPreviewTargetPosition: CGPoint? = nil
    @ObservationIgnored var portPositions: [UUID: CGPoint] = [:]

    @ObservationIgnored weak var lastNode:(Node)? = nil
    
    public let publishedParameterGroup:ParameterGroup = ParameterGroup("Published")

    // QOL - this functionally helps auto layout nodes
    // we have:
    // - a last added time
    // - a last offset amount
    // - a last added reset time
    // - an acrued offset if within the added time constraint
    // This effectively means if you add nodes quickly they will be added with offsets
    @ObservationIgnored private let nodeOffset = CGSize(width: 20, height: 20)
    @ObservationIgnored private var currentNodeOffset = CGSize.zero
    @ObservationIgnored private var lastAddedTime:TimeInterval = .zero
    @ObservationIgnored private var nodeAddedResetTime:TimeInterval = 10.0
    
    // This is set from external views which gives us the offset on the canvas we are inserting a node to.
    @ObservationIgnored public var currentScrollOffset:CGPoint = .zero


    // For Macro support
    public weak var activeSubGraph:Graph? = nil
    {
        didSet
        {
            guard let activeSubGraph,
                let undoManager
            else { return }
            
            activeSubGraph.undoManager = undoManager
        }
    }
    
    enum CodingKeys : String, CodingKey
    {
        case id
        case version
        case nodeMap
        case portConnectionMap
        case notes
    }
    
    public init(context:Context)
    {
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

        self.notes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
        
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
                
                if let nodeClass = NodeRegistry.shared.nodeClass(for: anyCodableMap.type)
                {
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(nodeClass, from: jsonData)

                    self.addNode(node)
                }
                
                // This is stupid? Yes, BaseEffectNode should be designed to cover the cases... but this works, today.
                else if anyCodableMap.type == String(describing: type(of: BaseEffectThreeChannelNode.self)).replacing(".Type", with:"")
                {
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseEffectThreeChannelNode.self, from: jsonData)

                    self.addNode(node)
                }
                // This is stupid?
                else if anyCodableMap.type == String(describing: type(of: BaseEffectTwoChannelNode.self)).replacing(".Type", with:"")
                {
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseEffectTwoChannelNode.self, from: jsonData)

                    self.addNode(node)
                }
                // This is stupid?
                else if anyCodableMap.type == String(describing: type(of: BaseEffectNode.self)).replacing(".Type", with:"")
                {
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    
                    let decoder = JSONDecoder()
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseEffectNode.self, from: jsonData)

                    self.addNode(node)
                }

                // This is stupid?
                else if anyCodableMap.type == String(describing: type(of: BaseGeneratorNode.self)).replacing(".Type", with:"")
                {
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    
                    let decoder = JSONDecoder()
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseGeneratorNode.self, from: jsonData)

                    self.addNode(node)
                }
                else
                {
                    print("Failed to find nodeClass for \(anyCodableMap.type)")

                }
            }
            catch
            {
                print("Failed to decode node: \(error)")
            }
        }
        
        decodeContext.currentGraphNodes = self.nodes
        
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

        let nodeMap:[ AnyCodableMap ] = self.nodes.compactMap {
            return AnyCodableMap(type: String(describing: type(of: $0)),
                                   value: AnyCodable($0))
        }
        
        try container.encode(self.notes, forKey: .notes)
        
        try container.encode( nodeMap, forKey: .nodeMap)
        
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
    
    public func addNode(_ node: NodeClassWrapper ) throws
    {
        if let activeSubGraph
        {
            try activeSubGraph.addNode(node)
            return
        }
        
        let node = try node.initializeNode(context: self.context)
        
        var offset = CGSize(width: self.currentScrollOffset.x  - node.nodeSize.width / 2.0,
                            height: self.currentScrollOffset.y - node.nodeSize.height / 4.0)
        
        let deltaTime = Date.now.timeIntervalSinceReferenceDate - self.lastAddedTime
        if deltaTime < self.nodeAddedResetTime
        {
            self.currentNodeOffset += self.nodeOffset
            offset += self.currentNodeOffset
        }
        else
        {
            self.currentNodeOffset = .zero
        }
        
        node.offset = offset
        
        self.addNode(node)

        self.lastAddedTime = Date.now.timeIntervalSinceReferenceDate
    }
    
    
//    public func addNodeType(_ nodeType: any NodeProtocol.Type, initialOffset:CGPoint? )
//    {
//        let node = nodeType.init(context: self.context)
//        
//        if let initialOffset = initialOffset
//        {
//            node.offset = CGSize(width:  initialOffset.x - node.nodeSize.width / 2.0,
//                                 height: initialOffset.y - node.nodeSize.height / 4.0)
//        }
//        
//        self.addNode(node)
//        
//    }
    
    public func addNode(_ node:Node)
    {
        if let activeSubGraph
        {
            activeSubGraph.addNode(node)
            return
        }
        
        print("Graph: \(self.id) Add Node", node.name)
        self.maybeAddNodeToScene(node)
        self.nodes.append(node)
        node.graph = self
        
        self.undoManager?.registerUndo(withTarget: self) { graph in
            graph.delete(node: node)
        }
        
        self.undoManager?.setActionName("Add Node")
        self.shouldUpdateConnections = true

        self.updateRenderingNodes()
        //        self.autoConnect(node: node)
    }
    
    func delete(node:Node, disconnect:Bool = true)
    {
        let savedOffset = node.offset
        let savedConnections = node.ports.flatMap { port in
            port.connections.map { (port, $0) }
        }

        if disconnect
        {
            node.ports.forEach { $0.disconnectAll() }
        }

        if let activeSubGraph
        {
            activeSubGraph.delete(node: node, disconnect: disconnect)
        }
        else
        {
            self.maybeDeleteNodeFromScene(node)
            self.nodes.removeAll { $0.id == node.id }

            self.undoManager?.registerUndo(withTarget: self) { graph in
                node.offset = savedOffset
                graph.nodes.append(node)
                node.graph = graph
                graph.maybeAddNodeToScene(node)
                graph.shouldUpdateConnections = true

                for (port, connectedPort) in savedConnections {
                    port.connect(to: connectedPort)
                }
            }
            
            self.undoManager?.setActionName("Delete Node")
            self.shouldUpdateConnections = true
        }

        self.updateRenderingNodes()
    }
    
    public func node(forID:UUID) -> Node?
    {
        if let activeSubGraph
        {
            return activeSubGraph.nodes.first(where: { $0.id == forID })
        }
        else
        {
            return self.nodes.first(where: { $0.id == forID })
        }
    }
    
    public func nodePort(forID:UUID) -> Port?
    {
        if let activeSubGraph
        {
            let allPorts = activeSubGraph.nodes.flatMap(\.ports)
            return allPorts.first(where: { $0.id == forID })
        }
        else
        {
            let allPorts = self.nodes.flatMap(\.ports)
            return allPorts.first(where: { $0.id == forID })
        }
    }
    
    public func rebuildPublishedParameterGroup()
    {
        self.publishedParameterGroup.clear()
        
        let params = self.publishedParameters()
        self.publishedParameterGroup.append( params )
        self.shouldUpdateConnections = true
    }
    
    // This could be more nicely done.
    public func publishedParameters() -> [any Parameter]
    {
        // id's of ports match id's of params for convenience
        let publishedPortIds = self.nodes.flatMap( { $0.publishedPorts().map { $0.id } } )
        
        // expose only params that are published
        return self.nodes.flatMap( { $0.parameterGroup.params } ).filter { publishedPortIds.contains($0.id) }
    }
    
    // This could be more nicely done.
    public func publishedPorts() -> [Port]
    {
        return  self.nodes.flatMap( { $0.publishedPorts() } )
    }
    
    public func nodesWithPublishedOutputs() -> [Node]
    {
        return  self.nodes.filter( { $0.publishedOutputPorts().isEmpty == false } )
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
            for node in self.nodes
            {
                node.isSelected = false
            }
        }
        
        self.lastNode = node
        self.lastNode?.isSelected = true
//        print("selected node:", self.lastNode?.name ?? "No Node")
        
    }
    
    public func selectAllNodes()
    {
        for node in self.nodes
        {
            node.isSelected = true
        }
    }
    
    public func deselectAllNodes()
    {
        for node in self.nodes
        {
            node.isSelected = false
        }
    }
    
    public func selectDownstreamNodes(fromNode node:Node)
    {
        var visitedNodes:[Node] = []

        self.selectDownstreamNodesRecursive(fromNode: node, visitedNodes:&visitedNodes)
    }
    
    private func selectDownstreamNodesRecursive(fromNode node:Node,  visitedNodes: inout [Node])
    {
        if !visitedNodes.contains(node)
        {
            visitedNodes.append( node )
            node.isSelected = true

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
    
    private func selectUpstreamNodesRecursive(fromNode node:Node,  visitedNodes: inout [Node])
    {
        if !visitedNodes.contains(node)
        {
            visitedNodes.append( node )
            node.isSelected = true

            node.inputNodes.forEach( {
                self.selectUpstreamNodesRecursive(fromNode: $0, visitedNodes: &visitedNodes )
            } )
        }
    }
    
    func createSubgraphFromSelection(centeredOnNode node:Node, usingClass subgraphClass:SubgraphNode.Type)
    {
        let selectedNodes = self.nodes.filter( { $0.isSelected } )
        
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
            print("scene added \(objectNode.name)")
            self.scene.add( object )
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

        let objects = self.nodes.compactMap { $0 as? BaseObjectNode }
            .compactMap { $0.getObject() }

        for object in objects
        {
            self.scene.add(object)
        }
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

            if let nodeClass = NodeRegistry.shared.nodeClass(for: map.type)
            {
                return try decoder.decode(nodeClass, from: jsonData)
            }
            else if map.type == String(describing: type(of: BaseEffectThreeChannelNode.self)).replacing(".Type", with:"")
            {
                return try decoder.decode(BaseEffectThreeChannelNode.self, from: jsonData)
            }
            else if map.type == String(describing: type(of: BaseEffectTwoChannelNode.self)).replacing(".Type", with:"")
            {
                return try decoder.decode(BaseEffectTwoChannelNode.self, from: jsonData)
            }
            else if map.type == String(describing: type(of: BaseEffectNode.self)).replacing(".Type", with:"")
            {
                return try decoder.decode(BaseEffectNode.self, from: jsonData)
            }
            else if map.type == String(describing: type(of: BaseGeneratorNode.self)).replacing(".Type", with:"")
            {
                return try decoder.decode(BaseGeneratorNode.self, from: jsonData)
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
        let targetGraph = self.activeSubGraph ?? self
        guard !nodesToDuplicate.isEmpty else { return [] }

        // 1. Capture internal connections before anything changes
        let internalConnections = targetGraph.buildInternalConnectionMap(for: nodesToDuplicate)

        // 2. Encode all nodes and build a unified UUID remap table
        let encoder = JSONEncoder()
        var uuidRemap: [String: String] = [:]
        var encodedEntries: [Data] = []

        for node in nodesToDuplicate
        {
            let map = AnyCodableMap(
                type: String(describing: type(of: node)),
                value: AnyCodable(node)
            )

            do
            {
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

                if let newNode = targetGraph.decodeNode(from: rewrittenMap)
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
        targetGraph.undoManager?.beginUndoGrouping()

        for newNode in newNodes
        {
            targetGraph.addNode(newNode)
        }

        // 5. Restore internal connections using remapped port IDs
        for (oldPortID, oldConnectedIDs) in internalConnections
        {
            guard let newPortIDString = uuidRemap[oldPortID.uuidString],
                  let newPortID = UUID(uuidString: newPortIDString),
                  let newPort = targetGraph.nodePort(forID: newPortID)
            else { continue }

            for oldConnectedID in oldConnectedIDs
            {
                guard let newConnectedIDString = uuidRemap[oldConnectedID.uuidString],
                      let newConnectedID = UUID(uuidString: newConnectedIDString),
                      let newConnectedPort = targetGraph.nodePort(forID: newConnectedID)
                else { continue }

                newPort.connect(to: newConnectedPort)
            }
        }

        targetGraph.undoManager?.endUndoGrouping()
        targetGraph.undoManager?.setActionName("Duplicate Nodes")

        // 6. Select only the new nodes
        targetGraph.deselectAllNodes()
        for newNode in newNodes { newNode.isSelected = true }

        targetGraph.shouldUpdateConnections = true

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

        let nodeEntries: [AnyCodableMap] = nodes.map {
            AnyCodableMap(
                type: String(describing: type(of: $0)),
                value: AnyCodable($0)
            )
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
        let targetGraph = self.activeSubGraph ?? self

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

                if let newNode = targetGraph.decodeNode(from: rewrittenMap)
                {
                    newNode.offset = newNode.offset + offset
                    newNodes.append(newNode)
                }
            }

            // Add nodes and restore connections
            targetGraph.undoManager?.beginUndoGrouping()

            for newNode in newNodes
            {
                targetGraph.addNode(newNode)
            }

            // Restore internal connections using remapped IDs
            for (oldPortIDString, oldConnectedIDStrings) in clipboardData.internalConnectionMap
            {
                guard let newPortIDString = uuidRemap[oldPortIDString],
                      let newPortID = UUID(uuidString: newPortIDString),
                      let newPort = targetGraph.nodePort(forID: newPortID)
                else { continue }

                for oldConnectedIDString in oldConnectedIDStrings
                {
                    guard let newConnectedIDString = uuidRemap[oldConnectedIDString],
                          let newConnectedID = UUID(uuidString: newConnectedIDString),
                          let newConnectedPort = targetGraph.nodePort(forID: newConnectedID)
                    else { continue }

                    newPort.connect(to: newConnectedPort)
                }
            }

            targetGraph.undoManager?.endUndoGrouping()
            targetGraph.undoManager?.setActionName("Paste Nodes")

            targetGraph.deselectAllNodes()
            for newNode in newNodes { newNode.isSelected = true }

            targetGraph.shouldUpdateConnections = true

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
