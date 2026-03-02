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
    // BARF
    override internal func boxedValue() -> PortValue? { self.value?.toPortValue() }
    
    override  internal func setBoxedValue(_ boxed: PortValue?)
    {
//        guard let boxed else { self.send(nil, force: true); return }
//        
//        self.send(Value.fromPortValue(boxed), force: true)

        
        // Assign w/o propogating via send
        if let boxed
        {
            self.value = Value.fromPortValue(boxed)
        }
        else
        {
            self.value = nil
        }

        // Force execution to see this value even if Equatable says “same”
        self.valueDidChange = true
        self.node?.markDirty()
    }
    
    public var value: Value?
    {
        didSet
        {
            // We no longer check for equality
            // 1 - send( .. ) has equality checks
            // 2 - send( .. ) support force
            // 3 - we need to be able to have force work!
            //   - it wont if we do an additional equality check here!
            self.valueDidChange = true
            self.node?.markDirty()
        }
    }
        
    public var valueType: Any.Type { Value.self }
    
    @ObservationIgnored override public var portType: PortType {
        Value.portType
    }
    
    enum CodingKeys : String, CodingKey
    {
        case valueType
    }
    
    override public init(name: String, kind: PortKind, description: String = "", id:UUID = UUID()) {
        super.init(name: name, kind: kind, description: description, id:id)

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
        else if let other = other as? NodePort<PortValue>
        {
            self.send(nil, to:other, force: true)
            self.validatedDisconnect(from: other)
        }
        else
        {
//            print("Disconnect Port \(self) Unable to Send Nil to \(other)")
//            self.send(nil, to:other, force: true)
            self.validatedDisconnect(from: other)

        }
    }
    
    private func validatedDisconnect(from other: Port)
    {
//        print("Port \(self) Disconnect from \(other)")

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
        
//        print("Connections: \(self.debugDescription)) - \(self.connections)")
//        print("Connections: \(other.debugDescription) - \(other.connections)")
        
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
        else if let other = other as? NodePort<PortValue>
        {
            self.connect(to: other)
        }
      
        else
        {
//            print("Port \(self) Unable to connect to \(other)")
            self.validatedConnect(to: other)
        }
    }
    
    public func connect(to other: NodePort<Value>)
    {
        self.validatedConnect(to:other)
    }
    
    public func connect(to other: NodePort<PortValue>)
    {
        self.validatedConnect(to:other)
    }
        
    private func validatedConnect(to other:  Port)
    {
//        print("Port \(self) Connect to \(other)")

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
        
//        print("Connections: \(self.debugDescription)) - \(self.connections)")
//        print("Connections: \(other.debugDescription) - \(other.connections)")

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
            
            for p in connections.filter( { $0.kind == .Inlet })
            {
                if let p = p as? NodePort<Value>
                {
                    self.send(v, to:p, force: force)
                }
                
                else if
                    let v = v,
                    v.canConvertTo(other: p.portType)
                {
                    if let converted = v.convertTo(other: p.portType) as? Bool,
                       let p = p as? NodePort<Bool>
                    {
                        self.send(converted, to:p, force: force)
                    }
                    
                    else if let converted = v.convertTo(other: p.portType) as? Int,
                       let p = p as? NodePort<Int>
                    {
                        self.send(converted, to:p, force: force)
                    }
                    
                    else if let converted = v.convertTo(other: p.portType) as? Float,
                       let p = p as? NodePort<Float>
                    {
                        self.send(converted, to:p, force: force)
                    }
                    
                    else if let converted = v.convertTo(other: p.portType) as? String,
                       let p = p as? NodePort<String>
                    {
                        self.send(converted, to:p, force: force)
                    }
                }

                // Our new boxed virtual
                else if let p = p as? NodePort<PortValue>
                {
                    self.send(v?.toPortValue(), to:p, force: force)
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
    
    private func send(_ v:Bool?, to other: NodePort<Bool>, force:Bool = false)
    {
        if other.value != v || force
        {
            other.value = v
        }
    }
    
    private func send(_ v:Int?, to other: NodePort<Int>, force:Bool = false)
    {
        if other.value != v || force
        {
            other.value = v
        }
    }
    
    private func send(_ v:Float?, to other: NodePort<Float>, force:Bool = false)
    {
        if other.value != v || force
        {
            other.value = v
        }
    }
    
    private func send(_ v:String?, to other: NodePort<String>, force:Bool = false)
    {
        if other.value != v || force
        {
            other.value = v
        }
    }
    
    private func send(_ v:PortValue?, to other: NodePort<PortValue>, force:Bool = false)
    {
        if other.value != v || force
        {
            other.value = v
        }
    }
        
    private static func calcColor(forType: Any.Type ) -> Color
    {
        if forType == FabricImage.self
        {
            return Color.nodeTexture
        }

        else if forType == Satin.SatinGeometry.self
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
