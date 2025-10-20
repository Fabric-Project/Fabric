//
//  Inlet.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Satin
import CoreMedia


public class NodePort<Value>: Port where Value : FabricPort
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
        
    @ObservationIgnored override public var portType: PortType {
        PortType.fromType(Value.self as! any FabricPort)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case valueType
    }
    
    override public init(name: String, kind: PortKind, id:UUID = UUID()) {
        super.init(name: name, kind: kind, id:id)

        self.color = Self.calcColor(forType: Value.self)
        self.backgroundColor = Self.calcBackgroundColor(forType: Value.self)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
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
    
    override public func disconnect(from other: Port)
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
    
    private func validatedDisconnect(from other: Port)
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
    
    override public func connect(to other: Port)
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
    
    private func validatedConnect(to other:  Port)
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
    
    // Send to a loggable (this should eventually turn into a Virtual?
    private func send(_ v:Value?, to other:  NodePort<AnyLoggable>, force:Bool = false)
    {
        if other.value?.asType(Value.self) != v || force
        {
            other.value = AnyLoggable(v)
        }
    }
    
    // if we are a loggable, try casting and sending
//    private func send(_ v:AnyLoggable, to other: NodePort<Value>, force:Bool = false)
//    {
//        if v.asType(type(of:other.value)) != other.value || force
//        {
//            if let otherVal = other.value
//            {
//                other.value = v.asType(type(of: otherVal ))
//            }
//        }
//    }
        
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
}
