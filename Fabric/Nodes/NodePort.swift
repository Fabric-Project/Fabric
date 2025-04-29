//
//  Inlet.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Satin

enum PortKind
{
    case Inlet
    case Outlet
}

// This is subtle, and for the UI
// for reference types, (ie Camera, Mesh, Material etc) we draw top / bottom
// for value types (ie float, simd_float2, bool etc) we draw left / right
// this allows for control params to go horizontal while scene content go vertical

enum PortDirection
{
    case Vertical
    case Horizontal
}

///// uniquely identifies a node’s inlet or outlet
//struct PortID: Hashable
//{
//    let nodeID: UUID
//    let portUUID: UUID
//    //… or however you distinguish each inlet/outlet
//}

struct PortAnchorKey: PreferenceKey
{
    typealias Value = [UUID : Anchor<CGPoint>]
    
    static var defaultValue: [UUID : Anchor<CGPoint>] = [:]
    
    static func reduce(value: inout [UUID : Anchor<CGPoint>],
                       nextValue: () -> [UUID : Anchor<CGPoint>])
    {
        // later writers win
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

protocol AnyPort
{
    var id: UUID { get }
    var name: String { get }
    var connections: [any AnyPort] { get set }
    var kind:PortKind { get }
    var node: Node? { get set }
    
    func connect(to other: any AnyPort)
    func discconnect(from other: any AnyPort)
    
    var color: Color { get }
    var backgroundColor: Color { get }
    var direction:PortDirection { get }
    
    
    func valueType() -> String
}

final class NodePort<Value>: AnyPort, Identifiable, Hashable, Equatable 
{
    public static func == (lhs: NodePort, rhs: NodePort) -> Bool
    {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
    
    let id = UUID()

    let name: String
    private(set) var value: Value? {
        didSet
        {
            self.shouldSendLatestValue = true
        }
    }
    
    // tracks value updates / changes
    private var shouldSendLatestValue:Bool = false
    

    var connections: [any AnyPort] = []
    var kind: PortKind
    weak var node: Node?

    var direction:PortDirection
    var color:Color
    var backgroundColor:Color
    
    init(name: String, kind: PortKind)
    {
        self.kind = kind
        self.name = name
        self.color = Self.calcColor(forType: Value.self)
        self.backgroundColor = Self.calcBackgroundColor(forType: Value.self )
        self.direction = Self.calcDirection(forType: Value.self )
    }
    
    func connect(to other: any AnyPort)
    {
        if let other = other as? NodePort<Value>
        {
            self.connect(to: other)
        }
    }

    func discconnect(from other: any AnyPort)
    {
        if let other = other as? NodePort<Value>
        {
            self.discconnect(from: other)
        }
    }
    
    func discconnect(from other: NodePort<Value>)
    {
        if let index = self.connections.firstIndex(where: { $0.id == other.id } )
        {
            self.connections.remove(at: index)
        }
    }
    
    func connect(to other: NodePort<Value>)
    {
        if self.kind == other.kind
        {
            return
        }
        
        if self.kind == .Inlet && other.kind == .Outlet
        {
            self.connections.forEach {
                $0.discconnect(from: self)
            }
            
            self.connections.removeAll()
            self.connections.append(other)
            
            other.connections.append(self)
        }
        else if self.kind == .Outlet && other.kind == .Inlet
        {
            other.connections.forEach {
                $0.discconnect(from: other)
            }
            
            other.connections.removeAll()
            other.connections.append(self)
            self.connections.append(other)
        }
    }
    
    func send(_ v: Value)
    {
        value = v
        
        for case let p as NodePort<Value> in connections
        {
            p.value = v
        }
        
    }
        
    static func calcColor(forType: Any.Type ) -> Color
    {
        if forType == (MTLTexture & AnyObject).self
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
    
    static func calcBackgroundColor(forType: Any.Type ) -> Color
    {
        return Self.calcColor(forType: forType).opacity(0.7)
    }
   
    
    static func calcDirection(forType: Any.Type ) -> PortDirection
    {
        
        if forType == (MTLTexture & AnyObject).self
        {
            return .Vertical
        }

        else if forType == Satin.Geometry.self
        {
            return .Vertical
        }
        
        else if forType == Satin.Camera.self
        {
            return .Vertical
        }
        
        else if forType == Satin.Material.self
        {
            return .Vertical
        }
        
        else if forType == Satin.Object.self
        {
            return .Vertical
        }
        
        else if forType == Satin.Renderer.self
        {
            return .Vertical
        }
        
        return .Horizontal
    }
    
    func valueType() -> String
    {
        return "\(type(of: self.value))"
    }
}
