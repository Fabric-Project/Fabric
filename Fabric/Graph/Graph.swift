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

    public private(set) var nodes: [Node]

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
    
    public var shouldUpdateConnections = false // New property to trigger view update
    {
        didSet
        {
            // Side Effect - try to synchronize the scene with any new objects
            // Due to connections being enabled.
            self.syncNodesToScene()
        }
    }

    var dragPreviewSourcePortID: UUID? = nil
    var dragPreviewTargetPosition: CGPoint? = nil
    @ObservationIgnored var portPositions: [UUID: CGPoint] = [:]

    @ObservationIgnored weak var lastNode:(Node)? = nil

    public let publishedParameterGroup:ParameterGroup = ParameterGroup("Published")

    // For Macro support
    public weak var activeSubGraph:Graph? = nil
    
    enum CodingKeys : String, CodingKey
    {
        case id
        case version
        case nodeMap
        case portConnectionMap
    }
    
    public init(context:Context)
    {
        print("Init Graph")
        self.id = UUID()
        self.version = .alpha1
        self.context = context
        self.nodes = []
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
                else if anyCodableMap.type == String(describing: type(of: BaseEffectThreeChannelNode.self)).replacingOccurrences(of: ".Type", with:"")
                {
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseEffectThreeChannelNode.self, from: jsonData)

                    self.addNode(node)
                }
                // This is stupid?
                else if anyCodableMap.type == String(describing: type(of: BaseEffectTwoChannelNode.self)).replacingOccurrences(of: ".Type", with:"")
                {
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseEffectTwoChannelNode.self, from: jsonData)

                    self.addNode(node)
                }
                // This is stupid?
                else if anyCodableMap.type == String(describing: type(of: BaseEffectNode.self)).replacingOccurrences(of: ".Type", with:"")
                {
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    
                    let decoder = JSONDecoder()
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseEffectNode.self, from: jsonData)

                    self.addNode(node)
                }

                // This is stupid?
                else if anyCodableMap.type == String(describing: type(of: BaseGeneratorNode.self)).replacingOccurrences(of: ".Type", with:"")
                {
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    
                    let decoder = JSONDecoder()
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(BaseGeneratorNode.self, from: jsonData)

                    self.addNode(node)
                }                else
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
        
        try container.encode( nodeMap, forKey: .nodeMap)
        
        // encode a connection map for each port
        
        let allPorts = self.nodes.flatMap( { $0.ports } )
        
        let allPortConnections:[UUID:[UUID]] = allPorts.reduce(into: [:]) { map, port in
            
            if port.connections.isEmpty { return }
            
            map[port.id] = port.connections.map( { $0.id } )
        }
        
        try container.encode(allPortConnections, forKey: .portConnectionMap)
    }
    
    public func addNode(_ node: NodeClassWrapper, initialOffset:CGPoint? ) throws
    {
        let node = try node.initializeNode(context: self.context)
        if let initialOffset = initialOffset
        {
            node.offset = CGSize(width:  initialOffset.x - node.nodeSize.width / 2.0,
                                 height: initialOffset.y - node.nodeSize.height / 4.0)
        }
        
        
        
        self.addNode(node)
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
        }
        
        self.updateRenderingNodes()
        //        self.autoConnect(node: node)
    }
    
    func delete(node:Node)
    {
        node.ports.forEach { $0.disconnectAll() }
        
        if let activeSubGraph
        {
            activeSubGraph.delete(node: node)
        }
        else
        {
            self.maybeDeleteNodeFromScene(node)
            self.nodes.removeAll { $0.id == node.id }
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
        self.shouldUpdateConnections.toggle()
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
     
    // MARK: -Rendering Helpers
    internal var consumerNodes: [Node] = []
    internal var sceneObjectNodes:[BaseObjectNode] = []
    internal var firstCamera:Camera? = nil
    
    func updateRenderingNodes()
    {
        self.consumerNodes = self.nodes.filter( { $0.nodeExecutionMode == .Consumer } )
        
        self.firstCamera = self.getFirstCamera()
    }
    
    func getFirstCamera() -> Camera?
    {
        let sceneObjectNodes:[BaseObjectNode] = self.consumerNodes.compactMap({ $0 as? BaseObjectNode})
        let firstCameraNode = sceneObjectNodes.first(where: { $0.nodeType == .Object(objectType: .Camera)})

        return firstCameraNode?.getObject() as? Camera
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
//                case .UpLeft:
//                    direction = .DownLeft
//                case .UpRight:
//                    direction = .DownRight
//                case .DownLeft:
//                    direction = .UpLeft
//                case .DownRight:
//                    direction = .UpRight
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
    
    func deselectAllNodes()
    {
        for node in self.nodes
        {
            node.isSelected = false
        }
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
