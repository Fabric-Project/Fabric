//
//  Inlet.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Satin
import CoreMedia

public enum PortKind : String, Codable
{
    case Inlet
    case Outlet
}

// This is subtle, and for the UI
// for reference types, (ie Camera, Mesh, Material etc) we draw top / bottom
// for value types (ie float, simd_float2, bool etc) we draw left / right
// this allows for control params to go horizontal while scene content go vertical

public enum PortDirection : String, Codable
{
    case Vertical
    case Horizontal
}


public struct PortAnchorKey: PreferenceKey
{
    public typealias Value = [UUID : Anchor<CGPoint>]
    
    public static var defaultValue: [UUID : Anchor<CGPoint>] = [:]
    
    public static func reduce(value: inout [UUID : Anchor<CGPoint>],
                       nextValue: () -> [UUID : Anchor<CGPoint>])
    {
        // later writers win
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

public protocol NodePortProtocol : Identifiable, Hashable, Equatable, Codable
{
    var id: UUID { get }
    var name: String { get }
    var connections: [any NodePortProtocol] { get set }
    var kind:PortKind { get }
    
//    func setPublished(_ value:Bool)
//    func isPublished() -> Bool
    
    var node: (any NodeProtocol)? { get set }

    func connect(to other: any NodePortProtocol)
    func disconnect(from other: any NodePortProtocol)
    func disconnectAll()

    var color: Color { get }
    var backgroundColor: Color { get }
    var direction:PortDirection { get }

    func valueType() -> String
    var valueDidChangeSinceLastGet:Bool { get }
    
}

public protocol ParameterPortProtocol : NodePortProtocol
{
}
    
public class ParameterPort<ParamValue : Codable & Equatable & Hashable> : NodePort<ParamValue>, ParameterPortProtocol
{
    private let parameter: GenericParameter<ParamValue>
    
    public init(parameter: GenericParameter<ParamValue>)
    {
        self.parameter = parameter
        
        super.init(name: parameter.label, kind: .Inlet, id:parameter.id)
    }
    
    required public init(from decoder: any Decoder) throws {
        self.parameter = try GenericParameter(from: decoder)

        try super.init(from: decoder)
    }
    
    override public func encode(to encoder: any Encoder) throws {
        
        try super.encode(to: encoder)
        
        try self.parameter.encode(to: encoder)
    }
    
    public override var value: ParamValue?
    {
        get
        {
            self.parameter.value
        }
        set
        {
            if let newValue = newValue
            {
                if  parameter.value != newValue
                {
                    parameter.value = newValue
                    node?.markDirty()
                }
            }
        }
        
    }
}

public class NodePort<Value : Equatable>: NodePortProtocol
{
    public static func == (lhs: NodePort, rhs: NodePort) -> Bool
    {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
        
    public let id:UUID

    public let name: String
    
    public var valueDidChangeSinceLastGet:Bool = false

    private var internalValue: Value?
    
    public var value: Value?
    {
        get
        {
            if self.valueDidChangeSinceLastGet
            {
                self.valueDidChangeSinceLastGet = false
            }
            
            return self.internalValue
        }
        set
        {
            if self.internalValue != newValue
            {
                self.valueDidChangeSinceLastGet = true
                node?.markDirty()
            }
            
            self.internalValue = newValue
        }
    }

    
//    private var published: Bool = false
//    public func setPublished(_ value:Bool) { self.published = value}
//    public func isPublished() -> Bool { self.published }

    
    public var connections: [any NodePortProtocol] = []
    public var kind: PortKind
    public weak var node: (any NodeProtocol)?

    public var direction:PortDirection
    public var color:Color
    public var backgroundColor:Color
    
    
    enum CodingKeys : String, CodingKey
    {
        case valueType
        case id
        case name
        case connections
        case kind
        case direction
//        case published
    }

    required public  init(from decoder: any Decoder) throws
    {
//        guard let decodeContext = decoder.context else
//        {
//            fatalError("Required Decode Context Not set")
//        }
        
//        guard let currentNodes = decodeContext.currentGraphNodes else
//        {
//            fatalError("Required Current Graph Nodes Not set")
//        }
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(PortKind.self, forKey: .kind)
//        self.published = try container.decode(Bool.self, forKey: .published)

        self.color = Self.calcColor(forType: Value.self)
        self.backgroundColor = Self.calcBackgroundColor(forType: Value.self)
        self.direction = Self.calcDirection(forType: Value.self )

    }
    
    public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
//        try container.encode(published, forKey: .published)

        let connectedPortIds = self.connections.map( { $0.id } )
        
        try container.encode(connectedPortIds, forKey: .connections)
    }
    
    public init(name: String, kind: PortKind, id:UUID = UUID())
    {
        self.id = id
        self.kind = kind
        self.name = name
        self.color = Self.calcColor(forType: Value.self)
        self.backgroundColor = Self.calcBackgroundColor(forType: Value.self )
        self.direction = Self.calcDirection(forType: Value.self )
    }
    
    deinit
    {
        self.disconnectAll()
    }
    
    
    public func disconnectAll()
    {
        self.connections.forEach { self.disconnect(from: $0) }
    }

    public func disconnect(from other: any NodePortProtocol)
    {
        if let other = other as? NodePort<Value>
        {
            self.disconnect(from: other)
        }
    }
    
    public func disconnect(from other: NodePort<Value>)
    {
        self.send(nil)
        
        if let index = self.connections.firstIndex(where: { $0.id == other.id } )
        {
            self.connections.remove(at: index)
        }
        
        self.node?.markDirty()
        other.node?.markDirty()
    }
    
    public func connect(to other: any NodePortProtocol)
    {
        if let other = other as? NodePort<Value>
        {
            self.connect(to: other)
        }
    }
    
    public func connect(to other: NodePort<Value>)
    {
        if self.kind == other.kind
        {
            return
        }
        
        if self.kind == .Inlet && other.kind == .Outlet
        {
            self.connections.forEach {
                $0.disconnect(from: self)
            }
            
            self.connections.removeAll()
            self.connections.append(other)
            other.connections.append(self)
        }
        else if self.kind == .Outlet && other.kind == .Inlet
        {
            other.connections.forEach {
                $0.disconnect(from: other)
            }
            
            other.connections.removeAll()
            other.connections.append(self)
            self.connections.append(other)
        }
        
        self.node?.markDirty()
        other.node?.markDirty()
    }
    
    public func send(_ v: Value?)
    {
        value = v
        
        for case let p as NodePort<Value> in connections
        {
            p.value = v
        }
        
    }
        
    private static func calcColor(forType: Any.Type ) -> Color
    {
        if forType == EquatableTexture.self
        {
            return Color.nodeTexture
        }

        else if forType == Satin.Geometry.self
        {
            return Color.nodeGeometry
        }
        
        else if forType == Satin.Camera.self
        {
            return Color.nodeCamera
        }
        
        else if forType == Satin.Material.self
        {
            return Color.nodeMaterial
        }
        
        else if forType == Satin.Object.self
        {
            return Color.nodeMesh
        }
        
        else if forType == Satin.Renderer.self
        {
            return Color.nodeRender
        }
        
        return Color.gray
    }
    
    private static func calcBackgroundColor(forType: Any.Type ) -> Color
    {
        return Self.calcColor(forType: forType).opacity(0.7)
    }
   
    
    private static func calcDirection(forType: Any.Type ) -> PortDirection
    {
        
//        if forType == EquatableTexture.self
//        {
//            return .Vertical
//        }
//
//        else if forType == Satin.Geometry.self
//        {
//            return .Vertical
//        }
//        
//        else if forType == Satin.Camera.self
//        {
//            return .Vertical
//        }
//        
//        else if forType == Satin.Material.self
//        {
//            return .Vertical
//        }
//        
//        else if forType == Satin.Object.self
//        {
//            return .Vertical
//        }
//        
//        else if forType == Satin.Renderer.self
//        {
//            return .Vertical
//        }
        
        return .Horizontal
    }
    
    public func valueType() -> String
    {
        return "\(type(of: self.value))"
    }
}
