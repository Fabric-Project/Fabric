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

public protocol NodePortProtocol : Identifiable, Hashable, Equatable, Codable, AnyObject, CustomDebugStringConvertible
{
    var id: UUID { get }
    var name: String { get }
    var connections: [any NodePortProtocol] { get set }
    var kind:PortKind { get }
    
    var published:Bool { get set }
    
    var node: (any NodeProtocol)? { get set }

    func connect(to other: any NodePortProtocol)
    func disconnect(from other: any NodePortProtocol)
    func disconnectAll()

    var color: Color { get }
    var backgroundColor: Color { get }
    var direction:PortDirection { get }

    func valueType() -> String
    var valueDidChange:Bool { get set }
    
}

public protocol ParameterPortProtocol : NodePortProtocol
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
        return lhs.hashValue == rhs.hashValue
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
        hasher.combine(published)
        hasher.combine(name)
    }
        
    public var debugDescription: String
    {
        return "\(self.node?.name ?? "No Node!!") - \(String(describing: type(of: self)))  \(id)"
    }
    
    public let id:UUID

    public let name: String
    
    public var published: Bool = false
    
    // Maybe a bit too verbose?
    public var valueDidChange:Bool = true
    
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
        case published
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
        self.published = try container.decodeIfPresent(Bool.self, forKey: .published) ?? false

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
        try container.encode(published, forKey: .published)

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
        print("Disconnect")

        self.send(nil, to:other, force: true)

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

//        self.node?.markDirty()
        
    }
    
    public func connect(to other: any NodePortProtocol)
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
    }
    
    public func connect(to other: NodePort<Value>)
    {
        self.validatedConnect(to:other)
    }
    
    public func connect(to other: NodePort<AnyLoggable>)
    {
        self.validatedConnect(to:other)
    }
    
    private func validatedConnect(to other:  any NodePortProtocol)
    {
        print("Connect")
        
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
            
            for case let p as NodePort<Value> in connections
            {
                self.send(v, to:p, force: force)
            }
            
            for case let p as NodePort<AnyLoggable> in connections
            {
                self.send(v, to:p, force: force)
            }
        }
    }
    
    private func send(_ v:Value?, to other: NodePort<Value>, force:Bool = false)
    {
        if other.value != v || force
        {
//            print("Sending value: \(self.debugDescription) - \(String(describing: v))")
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
