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

protocol AnyPort: Identifiable
{
    var id: UUID { get }
    var name: String { get }
    var connections: [any AnyPort] { get set }
    var kind:PortKind { get }
    var node: Node? { get set }
    
    func color() -> Color
    func direction() -> PortDirection
}

@Observable final class NodePort<Value>: AnyPort,  Hashable, Equatable
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
    private(set) var value: Value?
    var connections: [any AnyPort] = []
    var kind: PortKind
    weak var node: Node?

    init(name: String, kind: PortKind)
    {
        self.kind = kind
        self.name = name
    }
    
    func connect(to other: NodePort<Value>)
    {
        if self.kind == other.kind
        {
            return
        }
        
        if self.kind == .Inlet && other.kind == .Outlet
        {
            self.connections.removeAll()
            self.connections.append(other)
            other.connections.append(self)
        }
        else if self.kind == .Outlet && other.kind == .Inlet
        {
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
    
    func color() -> Color
    {
        if type(of: value) == Satin.Geometry?.self
        {
            return Color.nodeGeometry
        }
        
        else if type(of: value) == Satin.Camera?.self
        {
            return Color.nodeCamera
        }
        
        else if type(of: value) == Satin.Material?.self
        {
            return Color.nodeMaterial
        }
        
        else if type(of: value) == Satin.Object?.self
        {
            return Color.nodeMesh
        }
        
        else if type(of: value) == Satin.Renderer?.self
        {
            return Color.nodeRender
        }
        
        return Color.gray
    }
    
    func direction() -> PortDirection {
        
        if type(of: value) == Satin.Geometry?.self
        {
            return .Vertical
        }
        
        else if type(of: value) == Satin.Camera?.self
        {
            return .Vertical
        }
        
        else if type(of: value) == Satin.Material?.self
        {
            return .Vertical
        }
        
        else if type(of: value) == Satin.Object?.self
        {
            return .Vertical
        }
        
        else if type(of: value) == Satin.Renderer?.self
        {
            return .Vertical
        }
        
        return .Horizontal
    }
}
