//
//  NodeGraph.swift
//  v
//
//  Created by Anton Marini on 2/1/25.
//
import SwiftUI
import Satin
import AnyCodable

@Observable class Graph : Codable, Identifiable, Hashable, Equatable
{
    enum Version : Codable
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
    
    let id:UUID
    let version: Graph.Version
    @ObservationIgnored let context:Context
    
    private(set) var nodes: [Node]
    
    var shouldUpdateConnections = false // New property to trigger view update
    
    @ObservationIgnored weak var lastNode:Node? = nil
    
    enum CodingKeys : String, CodingKey
    {
        case id
        case version
        case nodeMap
        case portConnectionMap
    }
    
    init(context:Context)
    {
        print("Init Graph Execution Engine")
        self.id = UUID()
        self.version = .alpha1
        self.context = context
        self.nodes = []
    }
    
    
    required init(from decoder: any Decoder) throws
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
        
        while !nestedContainer.isAtEnd
        {
            do {
                
                let anyCodableMap = try nestedContainer.decode(AnyCodableMap.self)
                
                print(anyCodableMap.type)
                print(anyCodableMap.value)
                
                if let nodeClass = NodeRegistry.shared.nodeClass(for: anyCodableMap.type)
                {
                    // this is stupid but works!
                    // We make a new encoder to re-encode the data
                    // we pass to the intospected types class decoder based initialier
                    // since they all conform to NodeProtocol we can do this
                    // this is better than the alternative switch for each class..
                    
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(anyCodableMap.value)
                    
                    let decoder = JSONDecoder()
                    decoder.context = decodeContext
                    
                    let node = try decoder.decode(nodeClass, from: jsonData)
                    
                    if let node = node as? Node
                    {
                        self.nodes.append(node)
                    }
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

        
    }
    
    func encode(to encoder:Encoder) throws
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
    //
    //
    
    func addNodeType(_ nodeType: any NodeProtocol.Type )
    {
        if let node = nodeType.init(context: self.context) as? Node
        {
            self.addNode(node)
        }
    }
    
    func addNode(_ node:Node)
    {
        print("Add Node", node.name)
        
//        weak var weakSelf = self
        
//        node.delegate = weakSelf
        
        self.nodes.append(node)
        
        //        self.autoConnect(node: node)
    }
    
    func node(forID:UUID) -> Node?
    {
        return self.nodes.first(where: { $0.id == forID })
    }
    
    func nodePort(forID:UUID) -> (any NodePortProtocol)?
    {
        let allPorts = self.nodes.flatMap(\.ports)
        
        return allPorts.first(where: { $0.id == forID })
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
                print("referece node", referenceNode.name)

                self.selectNode(node: closestDistanceDirectionNodeTuples.Node, expandSelection: expandSelection)
            }
        }
    }
    
    func selectNode(node:Node, expandSelection:Bool)
    {
        if !expandSelection
        {
            self.nodes.forEach { $0.isSelected = false }
        }
        
        self.lastNode = node
        self.lastNode?.isSelected = true
//        print("selected node:", self.lastNode?.name ?? "No Node")
        
    }
    
    func deselectAllNodes()
    {
        self.nodes.forEach { $0.isSelected = false }
        
    }
}
//
//// MARK: - NodeDelegate
//
//extension Graph : NodeDelegate
//{
//    func willUpdate(node: Node)
//    {
//  
//    }
//    
//    func didUpdate(node: Node)
//    {
//        self.shouldUpdateConnections.toggle()
//    }
//    
//    func shouldDelete(node: Node)
//    {
//        self.shouldUpdateConnections.toggle()
//    }
//}
