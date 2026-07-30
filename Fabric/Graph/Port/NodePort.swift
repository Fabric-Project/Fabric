//
//  Inlet.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import CoreFoundation
import SwiftUI
import Satin
import simd

// Specialized port which facilitates sending a concrete type supported by Fabric .

public class NodePort<Value : PortValueRepresentable>: Port
{
    override internal func snapshotValue() -> PortValue? { self.value?.toPortValue() }

    override internal func restoreValue(from boxed: PortValue?)
    {
        if let boxed
        {
            self.value = Value.fromPortValue(boxed)
        }
        else
        {
            self.value = nil
        }

        self.valueDidChange = true
        self.node?.markDirty()
        self.onValueChanged?()
    }

    override internal func sendBoxed(_ boxed: PortValue?)
    {
        sendBoxed(boxed, force: false)
    }

    override internal func sendBoxed(_ boxed: PortValue?, force: Bool)
    {
        if let boxed
        {
            if let value = Value.fromPortValue(boxed) { self.send(value, force: force) }
            // Type mismatch — don't send anything.
        }
        else
        {
            self.send(nil, force: force)
        }
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
            self.onValueChanged?()
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
    }
    
    override public func disconnectAll()
    {
        for port in connectedPorts
        {
            disconnect(from: port)
        }
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

        let graph = self.node?.graph ?? other.node?.graph
        let removedGraphConnection = graph?.unregisterConnection(between: self, and: other) ?? false

//        print("Connections: \(self.debugDescription)) - \(self.connections)")
//        print("Connections: \(other.debugDescription) - \(other.connections)")
        
        self.node?.graph?.undoManager?.registerUndo(withTarget: self) { port in
            port.connect(to: other)
        }
        self.node?.graph?.undoManager?.setActionName("Disconnect Ports")
        if !removedGraphConnection {
            graph?.markConnectionsChanged()
        }
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

        // A dynamic port can remain alive briefly in a transient SwiftUI view
        // after the registry has replaced it. Removed ports are detached from
        // their node, so reject gestures involving those stale instances.
        guard self.node != nil, other.node != nil else
        {
            return
        }

        if self.kind == other.kind
        {
            return
        }

        // Connecting an already-connected pair is a no-op. Graph decoding
        // restores connections from a map keyed by both endpoints, so each
        // connection gets connected twice; without this guard the second call
        // would disconnect the pair first, force-sending nil into the inlet
        // and destroying the freshly decoded parameter value.
        if self.connection(to: other) != nil,
           other.connection(to: self) != nil
        {
            return
        }


        if self.kind == .Inlet && other.kind == .Outlet
        {
            for connectedPort in connectedPorts
            {
                connectedPort.disconnect(from: self)
            }
        }
        else if self.kind == .Outlet && other.kind == .Inlet
        {
            for connectedPort in other.connectedPorts
            {
                connectedPort.disconnect(from: other)
            }
        }

        let graph = self.node?.graph ?? other.node?.graph
        graph?.registerConnection(between: self, and: other)
        self.node?.updateConnectionTopology()
        other.node?.updateConnectionTopology()
        
        // TODO = This isnt QUITE right...
        
//        // We can't be published if we have an input connection...
//        // Output Ports can be published if connected.
//        
//        // So
//        if self.kind == .Inlet
//        {
//            self.published = false
//        }
        
//        print("Connections: \(self.debugDescription)) - \(self.connections)")
//        print("Connections: \(other.debugDescription) - \(other.connections)")

        // Only propagate if the source port has a value.
        // During graph decoding, output NodePorts have nil (value is not
        // persisted) and sending nil would overwrite decoded ParameterPort
        // values on connected inlets. The first execution pass will
        // propagate the real computed value through the connection.
        if self.value != nil
        {
            self.send(self.value, force: true)
        }

        self.node?.graph?.undoManager?.registerUndo(withTarget: self) { port in
            port.disconnect(from: other)
        }
        self.node?.graph?.undoManager?.setActionName("Connect Ports")
    }

    public func send(_ v: Value?, force:Bool = false)
    {
        if self.value != v || force
        {
            self.value = v
            
            for p in connectedInlets
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

                // Virtual → typed fallback: let the target port unbox via fromPortValue.
                // Handles e.g. NodePort<PortValue> outlet → NodePort<ContiguousArray<T>> inlet.
                else
                {
                    p.sendBoxed(v?.toPortValue())
                }
            }
        }
    }
    
    private func send(_ v:Value?, to other: NodePort<Value>, force:Bool = false)
    {
        // Specialized version
       _send(v, to: other, force: force)
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
        let isNotNan = !(v?.isNaN ?? false)
        let isNotInf = !(v?.isInfinite ?? false)

        let safe = other.value != v && isNotInf && isNotNan
        if  safe || force
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

        else if forType == Satin.Geometry.self || forType == Satin.SatinGeometry.self
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

extension NodePort
{
    @_specialize(exported: true, where Value == Bool)
    @_specialize(exported: true, where Value == Int)
    @_specialize(exported: true, where Value == Float)
    @_specialize(exported: true, where Value == String)
    @_specialize(exported: true, where Value == matrix_float4x4)
    @_specialize(exported: true, where Value == simd_float3)
    @_specialize(exported: true, where Value == simd_float3)
    @_specialize(exported: true, where Value == simd_float4)
    @_specialize(exported: true, where Value == simd_quatf)
    @usableFromInline
    func _send(_ v: Value?, to other: NodePort<Value>, force: Bool = false) {
        let v = Value.normalizePortValueForSend(v)

        if other.value != v || force
        {
            other.value = v
        }
    }
}
