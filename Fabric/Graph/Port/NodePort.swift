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
    }

    public func send(_ v: Value?, force:Bool = false)
    {
        if self.value != v || force
        {
            self.value = v
            
            for connection in connections
            {
                guard connection.outletPortID == id,
                      let inlet = connection.inletPort
                else { continue }

                if let inlet = inlet as? NodePort<Value>
                {
                    self.send(v, to:inlet, force: force)
                }
                
                else if
                    let v = v,
                    v.canConvertTo(other: inlet.portType)
                {
                    if let converted = v.convertTo(other: inlet.portType) as? Bool,
                       let inlet = inlet as? NodePort<Bool>
                    {
                        self.send(converted, to:inlet, force: force)
                    }
                    
                    else if let converted = v.convertTo(other: inlet.portType) as? Int,
                       let inlet = inlet as? NodePort<Int>
                    {
                        self.send(converted, to:inlet, force: force)
                    }
                    
                    else if let converted = v.convertTo(other: inlet.portType) as? Float,
                       let inlet = inlet as? NodePort<Float>
                    {
                        self.send(converted, to:inlet, force: force)
                    }
                    
                    else if let converted = v.convertTo(other: inlet.portType) as? String,
                       let inlet = inlet as? NodePort<String>
                    {
                        self.send(converted, to:inlet, force: force)
                    }
                }

                // Our new boxed virtual
                else if let inlet = inlet as? NodePort<PortValue>
                {
                    self.send(v?.toPortValue(), to:inlet, force: force)
                }

                // Virtual → typed fallback: let the target port unbox via fromPortValue.
                // Handles e.g. NodePort<PortValue> outlet → NodePort<ContiguousArray<T>> inlet.
                else
                {
                    inlet.sendBoxed(v?.toPortValue())
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
