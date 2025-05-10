//
//  NodeGraph.swift
//  v
//
//  Created by Anton Marini on 2/1/25.
//
import SwiftUI
import Satin
@Observable class Graph : Codable, Identifiable, Hashable, Equatable
{
    public static func == (lhs: Graph, rhs: Graph) -> Bool
    {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
    
    let id:UUID
    
    @ObservationIgnored let context:Context
    
    private(set) var nodes: [Node]
    
    var shouldUpdateConnections = false // New property to trigger view update
    
    @ObservationIgnored weak var lastNode:Node? = nil
    
    enum CodingKeys : String, CodingKey {
        case id
        case nodes
    }
    
    init(context:Context)
    {
        print("Init Graph Execution Engine")
        self.id = UUID()
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

        self.nodes = try container.decode([Node].self, forKey: .nodes)
        self.id = try container.decode(UUID.self, forKey: .id)
        
        decodeContext.currentGraphNodes = self.nodes

        
        
    }
    
    func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.id, forKey: .id)
        try container.encode(self.nodes, forKey: .nodes)
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
    
    func nodePort(forID:UUID) -> (any AnyPort)?
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
