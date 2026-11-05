//
//  Port.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Satin
import Synchronization

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


struct OutletData : Codable
{
    let portID: UUID
    init(portID: UUID)
    {
        self.portID = portID
    }
}

extension OutletData :Transferable
{
    static var transferRepresentation: some TransferRepresentation
    {
        CodableRepresentation(contentType: .outletData)
    }
}

struct InletData : Codable
{
    let portID: UUID
    init(portID: UUID)
    {
        self.portID = portID
    }
}

extension InletData :Transferable
{
    static var transferRepresentation: some TransferRepresentation
    {
        CodableRepresentation(contentType: .inletData)
    }
}

extension UTType
{
    static var outletData: UTType { UTType(exportedAs: "info.vade.v.outlet-data") }
    static var inletData: UTType { UTType(exportedAs: "info.vade.v.inlet-data") }
}


// Non Generic Base Port Class, dont use directly
public class Port : Identifiable, Hashable, Equatable, CustomDebugStringConvertible
{
    public static func == (lhs: Port, rhs: Port) -> Bool
    {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
    
    /// Mutable only via hydrate(from:) during decode, which adopts the
    /// document's saved identity so UUID-keyed connections can rebind.
    public private(set) var id:UUID

    public let name: String

    /// What the port's node finds it by; the registry sets it.
    public internal(set) var key: PortKey

    /// The control the port's declaration gives it; nil for a plain port. The
    /// registry sets it.
    public internal(set) var control: PortControl?

    public var portDescription: String = ""

    // Kind of lame, but necessary to avoid some type based bullshit.
    // TODO: Figure out a way to hide setting this (seems not good)
    // unless its a ParameterPort? 
    public var parameter:(any Parameter)? = nil
        
    // Maybe a bit too verbose?
    public var portType: PortType { fatalError("Must be implemented") }
    
    public var valueDidChange:Bool = true

    /// Runtime-polymorphic read for ports whose concrete type is only known at
    /// runtime — routing nodes' boxed forwarding, Iterator's count resolution,
    /// and layout copying. Pairs with sendBoxed.
    internal func snapshotValue() -> PortValue? { nil }
    internal func restoreValue(from boxed: PortValue?) { }

    /// Unboxes `boxed` into the port's native type and propagates to connected inlets via `send`.
    /// Use this to deliver a PortValue through a port whose concrete type is only known at runtime.
    internal func sendBoxed(_ boxed: PortValue?) { }

    /// Forced variant for stateful nodes that need to publish a new event even when the boxed value
    /// compares equal to the previous value.
    internal func sendBoxed(_ boxed: PortValue?, force: Bool) { sendBoxed(boxed) }
    
    // Unowned, not weak: any weak reference gives Node a Swift side table, which
    // slows every retain and release of it. Cleared on registry removal and Node deinit.
    public unowned var node: Node?
    internal var deferredSendCapture: GraphDeferredSendCapture?
    internal var deferredOutputIndex = 0
    internal var onValueChanged: (() -> Void)?

    /// Watchers of the value from outside the graph, such as a control. The
    /// count lets a send skip the lock while nothing watches.
    internal let valueObservers = Mutex<[PortValueObservation]>([])
    internal let valueObserverCount = Atomic<Int>(0)

    internal var connections: [Connection] = []
    public let kind: PortKind
    public let direction:PortDirection = .Horizontal
    public var color:Color
    public var backgroundColor:Color

    public var debugDescription: String
    {
        return "\(self.node?.debugDescription ?? "No Node!!") - \(String(describing: type(of: self)))  \(id)"
    }
    
    public init(name: String, kind: PortKind, description: String = "", id:UUID)
    {
        self.id = id
        self.kind = kind
        self.name = name
        self.key = .own(name)
        self.portDescription = description
        self.color = .clear
        self.backgroundColor = .clear
    }
    


    
    deinit
    {
        // Connections reference their endpoints unowned. A connection in this
        // port's list points at this port; clear it before it can dangle.
        for connection in self.connections
        {
            if connection.outletPortID == self.id { connection.outletPortReference = nil }
            if connection.inletPortID == self.id { connection.inletPortReference = nil }
        }
        self.connections.removeAll()
//        print("Deinit Port \(self.id)")
    }
    
    /// The display name: the name its graph publishes it under, if it was
    /// given one, otherwise the port's own name.
    public var displayName: String { self.node?.graph?.publishedName(of: self) ?? name }

    public var connectedPorts: [Port]
    {
        connections.compactMap { $0.port(opposite: self) }
    }

    public var connectedInlets: [Port]
    {
        connections.compactMap { connection in
            guard connection.outletPortID == id else { return nil }
            return connection.inletPort
        }
    }

    public var connectedOutlets: [Port]
    {
        connections.compactMap { connection in
            guard connection.inletPortID == id else { return nil }
            return connection.outletPort
        }
    }

    public func connection(to port: Port) -> Connection?
    {
        connections.first { connection in
            connection.port(opposite: self)?.id == port.id
        }
    }

    /// Hover-tooltip string for this port: `displayName: type` plus the
    /// current value when available.
    public var inspectionTooltip: String {
        let head = "\(displayName): \(portType.rawValue)"
        guard let value = snapshotValue() else { return head }

        return "\(head) - \(portType.previewString(for: value))"
    }


    /// Takes `id` as the port's runtime identity.
    internal func adoptID(_ id: UUID)
    {
        self.id = id
    }

    /// Puts a saved or carried value on the port when it fits the port's type,
    /// then lets the port correct it. Returns whether the value fitted.
    @discardableResult
    internal func apply(_ state: PortState, fileReferenceBase: URL? = nil) -> Bool
    {
        guard self.accepts(state.value) else { return false }
        self.restoreValue(from: state.value)
        self.correctAppliedValue(fileReferenceBase: fileReferenceBase)
        return true
    }

    /// Whether `value` is a value of this port's type.
    internal func accepts(_ value: PortValue) -> Bool { false }

    /// A port's own correction of a value put on it from outside the node: a
    /// slider's clamp to its range, a file picker's absolute reference inside
    /// `fileReferenceBase` made relative. Never an edit.
    internal func correctAppliedValue(fileReferenceBase: URL?) { }

    public func canConnect(to other:Port) -> Bool
    {
        if self.kind == .Inlet, self.portType == .Virtual { return true }
        if other.kind == .Inlet, other.portType == .Virtual { return true }
        return self.portType.canConnect(to: other.portType)
    }
    
    public func teardown() { }

}
    
