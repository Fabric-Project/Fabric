//
//  Inlet.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import CoreFoundation
import SwiftUI
import Satin

// Specialized port which facilitates sending a concrete type supported by Fabric .
public class NodePort<Value : PortValueRepresentable>: Port
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
        
    public var valueType: Any.Type { Value.self }
    
    @ObservationIgnored override public var portType: PortType {
        Value.portType
//        PortType.fromType( self.valueType )
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
        try super.init(from: decoder)

        self.color = Self.calcColor(forType: Value.self)
        self.backgroundColor = Self.calcBackgroundColor(forType: Value.self)
    }
    
    override public func teardown()
    {
        super.teardown()
        self.value = nil
    }
    
    deinit
    {
        self.teardown()
        self.disconnectAll()
        self.connections.removeAll()
    }
    
    override public func disconnectAll()
    {
        self.connections.forEach { [weak self] in  self?.disconnect(from: $0) }
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
            otherNode.didDisconnectFromNode(node)
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

        self.send(nil, force: true)

        
        self.node?.graph?.undoManager?.registerUndo(withTarget: self) { port in
            port.connect(to: other)
        }
        self.node?.graph?.undoManager?.setActionName("Disconnect Ports")
        self.node?.graph?.shouldUpdateConnections.toggle()
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
            self.connections.forEach { [weak self] in
                
                guard let self else { return }
                    
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
        
        // TODO = This isnt QUITE right...
        
//        // We can't be published if we have an input connection...
//        // Output Ports can be published if connected.
//        
//        // So
//        if self.kind == .Inlet
//        {
//            self.published = false
//        }
        
        if let node = self.node,
           let otherNode = other.node
        {
//            // This forces a ping to recompute if we need to
//            node.markDirty()
            node.didConnectToNode(otherNode)
            otherNode.didConnectToNode(node)
        }
        
        print("Connections: \(self.debugDescription)) - \(self.connections)")
        print("Connections: \(other.debugDescription) - \(other.connections)")

        self.send(self.value, force: true)

        self.node?.graph?.undoManager?.registerUndo(withTarget: self) { port in
            port.disconnect(from: other)
        }
        self.node?.graph?.undoManager?.setActionName("Connect Ports")
        self.node?.graph?.shouldUpdateConnections.toggle()
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
        if forType == FabricImage.self
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
