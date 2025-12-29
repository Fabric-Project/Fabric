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
    private let nodeOffset = CGSize(width: 20, height: 20)
    private var currentNodeOffset = CGSize.zero
    private var lastAddedTime:TimeInterval = .zero
    private var nodeAddedResetTime:TimeInterval = 10.0
    
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
    
    public func addNode(_ node: NodeClassWrapper, initialOffset:CGPoint? ) throws
    {
        let node = try node.initializeNode(context: self.context)
        
        var offset = CGSize.zero
        
        if let initialOffset = initialOffset
        {
            offset =  CGSize(width:  initialOffset.x - node.nodeSize.width / 2.0,
                             height: initialOffset.y - node.nodeSize.height / 4.0)
        }
             
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
        }
        else
        {
            print("Graph: \(self.id) Add Node", node.name)
            self.maybeAddNodeToScene(node)
            self.nodes.append(node)
            node.graph = self

            self.undoManager?.registerUndo(withTarget: self) { graph in
                graph.delete(node: node)
            }
            
            self.undoManager?.setActionName("Add Node")
            self.shouldUpdateConnections = true
        }

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
    
    func selectNode(node:Node, expandSelection:Bool)
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
    
    func selectAllNodes()
    {
        for node in self.nodes
        {
            node.isSelected = true
        }
    }
    
    func deselectAllNodes()
    {
        for node in self.nodes
        {
            node.isSelected = false
        }
    }
    
    func selectDownstreamNodes(fromNode node:Node)
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
    
    func selectUpstreamNodes(fromNode node:Node)
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
}
