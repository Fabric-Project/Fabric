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


// TODO: This should maybe be removed?
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

//public protocol NodePortProtocol : Identifiable, Hashable, Equatable, Codable, AnyObject, CustomDebugStringConvertible
//{
//    var id: UUID { get }
//    var name: String { get }
//    var connections: [AnyPort] { get set }
//    var kind:PortKind { get }
//    
//    var published:Bool { get set }
//    
//    var node: Node? { get set }
//
//    func connect(to other: AnyPort)
//    func disconnect(from other: AnyPort)
//    func disconnectAll()
//
//    var color: Color { get }
//    var backgroundColor: Color { get }
//    var direction:PortDirection { get }
//
////    var value: Any? { get set }
//    var valueType: Any.Type { get }
//    var valueDescription: String { get }
//    var valueDidChange:Bool { get set }
//}

public class AnyPort : Identifiable, Hashable, Equatable, Codable, CustomDebugStringConvertible
{
    public static func == (lhs: AnyPort, rhs: AnyPort) -> Bool
    {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
        hasher.combine(published)
        hasher.combine(name)
    }
    
    public let id:UUID

    public let name: String
    
    public var published: Bool = false
        
    // Maybe a bit too verbose?
//    public var value: Any? { fatalError("override") }
    public var valueType: Any.Type { fatalError("override") }
    public var valueDescription:String { fatalError("override") }
    public var valueDidChange:Bool = true

    public weak var node: Node?
    public var connections: [AnyPort] = []
    public let kind: PortKind
    public let direction:PortDirection = .Horizontal
    public var color:Color
    public var backgroundColor:Color



    public var debugDescription: String
    {
        return "\(self.node?.name ?? "No Node!!") - \(String(describing: type(of: self)))  \(id)"
    }

    
    public init(name: String, kind: PortKind, id:UUID)
    {
        self.id = id
        self.kind = kind
        self.name = name
        self.color = .clear
        self.backgroundColor = .clear
    }
    
    enum CodingKeys : String, CodingKey
    {
        case valueType
        case id
        case name
        case connections
        case kind
        case direction
        case published
    }
    
    required public  init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(PortKind.self, forKey: .kind)
        self.published = try container.decodeIfPresent(Bool.self, forKey: .published) ?? false
        self.color = .clear
        self.backgroundColor = .clear

    }
    
    public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(published, forKey: .published)

        let connectedPortIds = self.connections.map( { $0.id } )
        
        try container.encode(connectedPortIds, forKey: .connections)
    }
    
    
    public func connect(to other: AnyPort) { fatalError("override") }
    public func disconnect(from other: AnyPort) { fatalError("override") }
    public func disconnectAll() { fatalError("override") }

}

public protocol ParameterPortProtocol
{
    associatedtype ParamValue : Codable & Equatable & Hashable
    var parameter:GenericParameter<ParamValue> { get }
}
    
public class ParameterPort<ParamValue : Codable & Equatable & Hashable> : NodePort<ParamValue>, ParameterPortProtocol
{
    public let parameter: GenericParameter<ParamValue>
    
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
    
    override public var valueDidChange: Bool
    {
        didSet
        {
            self.parameter.valueDidChange = self.valueDidChange
        }
    }
    
    override public var value: ParamValue?
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
                    self.valueDidChange = true
                    self.node?.markDirty()
                }
            }
        }
    }
}

public class NodePort<Value : Equatable>: AnyPort
{
    public var value: Value?
    {
        didSet
        {
            if oldValue != self.value
            {
                self.valueDidChange = true
                self.node?.markDirty()
            }
        }
    }
    
    override public init(name: String, kind: PortKind, id:UUID = UUID()) {
        super.init(name: name, kind: kind, id:id)

        self.color = Self.calcColor(forType: Value.self)
        self.backgroundColor = Self.calcBackgroundColor(forType: Value.self)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        self.color = Self.calcColor(forType: Value.self)
        self.backgroundColor = Self.calcBackgroundColor(forType: Value.self)
    }
    
    deinit
    {
        self.disconnectAll()
    }
    
    override public func disconnectAll()
    {
        self.connections.forEach { self.disconnect(from: $0) }
    }
    
    override public func disconnect(from other: AnyPort)
    {
        if let other = other as? NodePort<Value>
        {
            self.send(nil, to:other, force: true)
            self.validatedDisconnect(from: other)
        }
        // In theory we can use this for type casting port to port?
        else if let other = other as? NodePort<AnyLoggable>
        {
            self.send(nil, to:other, force: true)
            self.validatedDisconnect(from: other)
        }
        else
        {
            print("Port \(self) Unable to Disconnect from \(other)")
        }
    }
    
    private func validatedDisconnect(from other: AnyPort)
    {
        print("Port \(self) Disconnect from \(other)")

        if let node = self.node,
           let otherNode = other.node
        {
            node.didDisconnectFromNode(otherNode)
        }
        
        if other.kind == .Inlet
        {
            other.connections.removeAll()
        }
        else
        {
            while let index = other.connections.firstIndex(where: { $0.id == other.id } )
            {
                other.connections.remove(at: index)
            }
        }
        
        if self.kind == .Inlet
        {
            self.connections.removeAll()
        }
        else
        {
            while let index = self.connections.firstIndex(where: { $0.id == other.id } )
            {
                self.connections.remove(at: index)
            }
        }
        
        print("Connections: \(self.debugDescription)) - \(self.connections)")
        print("Connections: \(other.debugDescription) - \(other.connections)")
    }
    
    override public func connect(to other: AnyPort)
    {
        if let other = other as? NodePort<Value>
        {
            self.connect(to: other)
        }
        
        // In theory we can use this for type casting port to port?
        else if let other = other as? NodePort<AnyLoggable>
        {
            self.connect(to: other)
        }
        
        else if self.value is AnyLoggable?
        {
            self.validatedConnect(to: other)
        }
        else
        {
            print("Port \(self) Unable to connect to \(other)")
        }
    }
    
    public func connect(to other: NodePort<Value>)
    {
        self.validatedConnect(to:other)
    }
    
    public func connect(to other: NodePort<AnyLoggable>)
    {
        self.validatedConnect(to:other)
    }
    
    private func validatedConnect(to other:  AnyPort)
    {
        print("Port \(self) Connect to \(other)")

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
        
        // We can't be published if we have an input connection...
        // Output Ports can be published if connected.
        if self.kind == .Inlet
        {
            self.published = false
        }
        
        if let node = self.node,
           let otherNode = other.node
        {
            node.didConnectToNode(otherNode)
        }
        
        print("Connections: \(self.debugDescription)) - \(self.connections)")
        print("Connections: \(other.debugDescription) - \(other.connections)")

//        self.node?.markDirty()
//        other.node?.markDirty()
        
        self.send(self.value, force: true)
    }

    
    public func send(_ v: Value?, force:Bool = false)
    {
        if self.value != v || force
        {
            self.value = v
            
            for p in connections
            {
                if let p = p as? NodePort<Value>
                {
                    self.send(v, to:p, force: force)
                }
                
                else if let p = p as? NodePort<AnyLoggable>
                {
                    self.send(v, to:p, force: force)
                }
            }
        }
    }
    
    private func send(_ v:Value?, to other: NodePort<Value>, force:Bool = false)
    {
        if other.value != v || force
        {
            other.value = v
        }
    }
    
    private func send(_ v:Value?, to other:  NodePort<AnyLoggable>, force:Bool = false)
    {
        if other.value?.asType(Value.self) != v || force
        {
            other.value = AnyLoggable(v)
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
        return .Horizontal
    }
    
    public func valueType() -> String
    {
        return "\(type(of: self.value))"
    }
}
