//
//  SubgraphNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/22/25.
//

import Foundation
import CryptoKit
import Satin
import simd
import Metal

open class SubgraphNode: BaseObjectNode
{
    override open class var name:String { "Sub Graph" }
    override open class var nodeType:Node.NodeType { Node.NodeType.Subgraph }
    override open class var nodeExecutionMode: Node.ExecutionMode { .Consumer } // TODO: ??
    override open class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override open class var nodeDescription: String { "A Sub Graph of Nodes, useful for organizing or encapsulation"}

    public private(set) var subGraph:Graph

    /// The clone set this node belongs to, nil outside any set. Members of a
    /// set are instances of one stored graph: the same nodes, ports and wires
    /// under the same ids, each executing on its own. The member edited last
    /// becomes the stored graph and its siblings are decoded from it afresh.
    /// Published inlet values are the per-member exception: the parent graph
    /// sets them through the proxy. Mutate through Graph.duplicateAsClone /
    /// unlinkClone so the change is undoable. See CloneSet.
    public internal(set) var cloneSetID: UUID?

    /// The one place membership is written, with the badge refreshed. Not
    /// undoable; Graph.setCloneMembership wraps it with undo.
    internal func setCloneMembership(setID: UUID?)
    {
        self.cloneSetID = setID
        self.subtitleSubject.send()
    }

    /// The set as seen from this member, nil outside a set. Refreshed through
    /// subtitleSubject whenever membership or the name changes.
    public var cloneSetInfo: CloneSetInfo?
    {
        guard let graph = self.graph, let setID = self.cloneSetID, let set = graph.cloneSet(for: setID)
        else { return nil }
        return CloneSetInfo(setID: setID,
                            name: set.name,
                            memberCount: graph.cloneSiblings(of: self).count + 1)
    }

    /// A member describes itself by its set's name, the way a Strategy node
    /// shows its strategy. The member count lives in the status's message.
    override open func deriveSubtitle() -> String? { self.cloneSetInfo?.name }

    /// A member reports itself linked to its set.
    override open func deriveStatuses() -> [NodeStatus] { self.cloneSetInfo.map { [$0.status] } ?? [] }

    /// What a proxy keeps across its member re-instantiating: its id in the
    /// parent graph, and whether and as what the parent publishes it on.
    private struct ProxyIdentity
    {
        let id: UUID
        let published: Bool
        let publishedName: String?
    }

    /// Identities to give proxies as they are rebuilt, by inner port id; set
    /// around a rebuild that replaces every proxy. See replaceSubGraph.
    private var reusableProxyIdentities: [UUID: ProxyIdentity] = [:]

    /// The renderer this node last started or enabled under, so a sub graph
    /// it retires can be stopped through it before it is released.
    private weak var lifecycleRenderer: GraphRenderer?

    /// ProxyPorts wrapping the sub graph's published ports.
    /// Each proxy has node = self (the SubgraphNode) and published = false.
    /// The parent graph independently decides whether to publish them further.
    /// Lazily rebuilt when the sub graph's published ports change.
    private var proxyPorts: [Port] = []

    override open var ports:[Port] { self.proxyPorts + super.ports }

    /// Rebuild proxy ports from the sub graph's current published ports.
    /// Called via callback when the sub graph's published ports change.
    open func rebuildProxyPorts()
    {
        self.invalidatePortCaches()

        let innerPorts = self.subGraph.getPublishedPorts()
        let publishedByID = Dictionary(innerPorts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Remove proxies whose inner port is no longer published, or was
        // replaced under its id: the proxy forwards to the port it was made
        // over, so it is made again over the replacement, published as it was
        // in the graph around, as the replacement is in its own. Where a
        // proxy that goes was published there too, the proxy over it a level
        // up goes the same way.
        let dropped = self.proxyPorts.filter { proxy in
            guard let typed = proxy as? any ProxyPortProtocol else { return true }
            return publishedByID[typed.innerPortID] == nil
        }
        var replaced: [UUID: (published: Bool, publishedName: String?)] = [:]
        self.proxyPorts.removeAll { proxy in
            guard let typed = proxy as? any ProxyPortProtocol,
                  let innerPort = publishedByID[typed.innerPortID]
            else { return true }
            guard !typed.wraps(innerPort) else { return false }
            replaced[typed.innerPortID] = (proxy.published, proxy.publishedName)
            return true
        }

        // Add proxies for newly published ports
        let existingInnerIDs = Set(self.proxyPorts.compactMap { ($0 as? any ProxyPortProtocol)?.innerPortID })
        var replacements: [Port] = []
        // A member's proxies carry ids of their own: its siblings wrap inner
        // ports under the same ids in the same parent graph. A proxy that is
        // being rebuilt keeps the id and published state it had.
        for innerPort in innerPorts where !existingInnerIDs.contains(innerPort.id)
        {
            let identity = self.reusableProxyIdentities[innerPort.id]
            let proxyID = identity?.id ?? (self.cloneSetID == nil ? nil : self.memberProxyID(for: innerPort.id))
            if let proxy = Self.makeProxy(for: innerPort, id: proxyID)
            {
                proxy.node = self
                if let identity
                {
                    proxy.published = identity.published
                    proxy.publishedName = identity.publishedName
                }
                else if let state = replaced[innerPort.id]
                {
                    proxy.published = state.published
                    proxy.publishedName = state.publishedName
                    replacements.append(proxy)
                }
                self.proxyPorts.append(proxy)
            }
        }
        
        // Ensure parameter group is updated
        self.parameterGroup.clear()

        for port in self.ports
        {
            if let param = port.parameter
            {
                self.parameterGroup.append(param)
            }
        }

        self.synchronizeParameters()

        self.invalidatePortCaches()

        // A proxy dropped and rebuilt is a new object under the same id, so
        // the containing graph's wires onto it have to be bound to it again,
        // but for those a replacement of another type cannot take.
        if let graph = self.graph
        {
            graph.reattachConnections(to: self.proxyPorts)
            let incompatible = replacements.flatMap(\.connections).filter { connection in
                guard let outlet = connection.outletPort, let inlet = connection.inletPort else { return true }
                return !outlet.canConnect(to: inlet)
            }
            graph.withoutUndoRegistration {
                for connection in incompatible { _ = graph.disconnect(connection) }
            }
        }

        self.graph?.markConnectionsChanged()
        // A replacement published further up is a replaced port there too,
        // and a dropped one published there a removed one.
        if (replacements + dropped).contains(where: \.published) { self.graph?.rebuildPublishedParameterGroup() }
        self.portsChangedSubject.send()
    }

    /// The id a member gives a proxy it makes: derived from its own id and the
    /// inner port's, so the same every time it is made. Instances of a nested
    /// member share both and so agree, keeping the members around them in
    /// step; members side by side in one graph have ids of their own and so
    /// differ.
    private func memberProxyID(for innerPortID: UUID) -> UUID
    {
        var hash = SHA256()
        hash.update(data: Data(self.id.uuidString.utf8))
        hash.update(data: Data(innerPortID.uuidString.utf8))
        var bytes = Array(hash.finalize().prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80     // version 8: custom
        bytes[8] = (bytes[8] & 0x3F) | 0x80     // RFC 4122 variant
        return bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }

    /// Type-erase proxy creation — matches the inner port's generic type.
    private static func makeProxy(for port: Port, id: UUID?) -> Port?
    {
        switch port
        {
        case let p as NodePort<Float>:                              return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Int>:                                return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Bool>:                               return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<String>:                             return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<simd_float2>:                        return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<simd_float3>:                        return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<simd_float4>:                        return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<FabricImage>:                        return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Geometry>:                           return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Material>:                           return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<PortValue>:                          return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<simd_quatf>:                         return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<simd_float4x4>:                      return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<Float>>:             return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<Int>>:               return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<Bool>>:              return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<String>>:            return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<simd_float2>>:       return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<simd_float3>>:       return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<simd_float4>>:       return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<simd_float4x4>>:     return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<simd_quatf>>:        return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<Geometry>>:          return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<Material>>:          return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<FabricImage>>:       return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<ContiguousArray<PortValue>>:         return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, Float>>:          return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, Int>>:            return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, Bool>>:           return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, String>>:         return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, simd_float2>>:    return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, simd_float3>>:    return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, simd_float4>>:    return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, simd_float4x4>>:  return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, simd_quatf>>:     return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, Geometry>>:       return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, Material>>:       return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, FabricImage>>:    return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<Float>>>:         return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<Int>>>:           return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<Bool>>>:          return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<String>>>:        return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float2>>>:   return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float3>>>:   return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float4>>>:   return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float4x4>>>: return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_quatf>>>:    return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<Geometry>>>:      return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<Material>>>:      return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, ContiguousArray<FabricImage>>>:   return ProxyPort(wrapping: p, id: id)
        case let p as NodePort<Dictionary<String, PortValue>>:       return ProxyPort(wrapping: p, id: id)
        default:
            print("ProxyPort: unsupported port type for \(port.name): \(type(of: port))")
            return nil
        }
    }

    override open var nodeExecutionMode:ExecutionMode
    {
        let publishedInputPorts = self.proxyPorts.filter { $0.kind == .Inlet }
        let publishedOutputPorts = self.proxyPorts.filter { $0.kind == .Outlet }

        // If we have no inputs or outputs, assume we have shit to 'render'
        if publishedInputPorts.isEmpty && publishedOutputPorts.isEmpty
        {
            return .Consumer
        }
        
        // if we have no inputs, but have an output we provide
        if publishedInputPorts.isEmpty && !publishedOutputPorts.isEmpty
        {
            return .Provider
        }
        
        // if we have inputs, and outputs we process
        if !publishedInputPorts.isEmpty && !publishedOutputPorts.isEmpty
        {
            return .Processor
        }

        // Safety ?
        return Self.nodeExecutionMode
    }

    override open func getObject() -> Object?
    {
        return self.object
    }

    open var object:Object? {
        self.subGraph.scene
    }
    
    public required init(context: Context)
    {
        self.subGraph = Graph(context: context)

        super.init(context: context)
        self.wireSubGraphCallback()
        self.rebuildProxyPorts()
    }

    /// Wrap an existing graph as this node's sub graph, for embedders that
    /// decode a graph separately and then nest it.
    public init(context: Context, subGraph: Graph)
    {
        self.subGraph = subGraph

        super.init(context: context)
        self.wireSubGraphCallback()
        self.rebuildProxyPorts()
    }

    enum CodingKeys : String, CodingKey
    {
        case subGraph
        case proxyPorts
        case cloneSetID
        case memberValues
    }
    
    open override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(self.cloneSetID, forKey: .cloneSetID)

        // A member in step with its set is written as a reference to it and
        // the values that are its own; the set holds the graph once. The
        // proxies are the member's face in the parent graph, published and
        // named there per member, so they are written either way.
        try container.encode(self.proxyPorts.map(AnyPort.init), forKey: .proxyPorts)
        if encoder.userInfo[Graph.compactCloneMembersKey] as? Bool == true, self.isInStepWithCloneSet
        {
            try container.encode(self.memberValues, forKey: .memberValues)
        }
        else
        {
            try container.encode(self.subGraph, forKey: .subGraph)
        }

        try super.encode(to: encoder)
    }

    /// The values that are this member's own, by path: what it keeps when it
    /// is written as a reference to its set. See Graph.memberOwnInlets.
    private var memberValues: [String: AnyPort]
    {
        self.subGraph.memberOwnInlets().mapValues(AnyPort.init)
    }

    /// True when the sub graph encodes to the set's stored graph, the state
    /// every member is in once syncs have run. A member that does not is
    /// written in full, so nothing is lost.
    internal var isInStepWithCloneSet: Bool
    {
        guard let graph = self.graph, let setID = self.cloneSetID, let set = graph.cloneSet(for: setID),
              let json = try? Graph.cloneSetJSON(of: self.subGraph)
        else { return false }
        return Graph.designComparableJSON(json) == set.comparableGraphJSON
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.cloneSetID = try container.decodeIfPresent(UUID.self, forKey: .cloneSetID)

        if container.contains(.subGraph)
        {
            self.subGraph = try container.decode(Graph.self, forKey: .subGraph)
        }
        else
        {
            // A member written as a reference to its set: an instance of the
            // set's stored graph.
            guard let decodeContext = decoder.context, let setID = self.cloneSetID else
            {
                throw DecodingError.dataCorruptedError(forKey: .subGraph, in: container,
                                                       debugDescription: "A clone set member saved without its sub graph needs its set to be instantiated.")
            }
            self.subGraph = try Graph.instantiateCloneSetGraph(of: setID, decodeContext: decodeContext)
        }
        
        // We set the current graph to the subgraph
        // to allow proxy ports and any other decode contexts to work correctly
        
        if let decodeContext = decoder.context
        {
            let previousGraph = decodeContext.currentGraph

            decodeContext.currentGraph = self.subGraph

            defer
            {
                decodeContext.currentGraph = previousGraph
            }

            self.proxyPorts = Self.decodeProxyPortsIfPossible(from: container, forKey: .proxyPorts)
        }
        else
        {
            self.proxyPorts = Self.decodeProxyPortsIfPossible(from: container, forKey: .proxyPorts)
        }

        Self.applyMemberValues(from: container, to: self.subGraph)

        try super.init(from: decoder)
        self.wireSubGraphCallback()
        self.proxyPorts.forEach { $0.node = self }
        self.rebuildProxyPorts()
    }

    /// The per-member values a reference wrote, put back on the ports they
    /// name: the same paths in every instance of the stored graph.
    private static func applyMemberValues(from container: KeyedDecodingContainer<CodingKeys>,
                                          to subGraph: Graph)
    {
        guard let values = Self.decodeMemberValues(from: container) else { return }
        Self.restore(values: values.mapValues { ($0.base.portType, $0.base.snapshotValue()) }, in: subGraph)
    }

    private static func restore(values: [String: (portType: PortType, value: PortValue?)], in subGraph: Graph)
    {
        let portsByPath = subGraph.memberOwnInlets()
        for (path, saved) in values
        {
            guard let port = portsByPath[path], port.portType == saved.portType else { continue }
            port.restoreValue(from: saved.value)
        }
    }

    // MARK: - Clone set sync

    /// Replaces the sub graph with a fresh instance of the set's stored
    /// graph. See replaceSubGraph.
    internal func reinstantiateSubGraph() throws
    {
        guard let graph = self.graph, let setID = self.cloneSetID else
        {
            throw FabricError(.graph(.notACloneMember), severity: .recoverable, message: "\(self) is not in a clone set.")
        }
        let instance = try Graph.instantiateCloneSetGraph(of: setID, decodeContext: graph.makeDecoderContext())
        self.replaceSubGraph(with: instance)
    }

    /// Swaps the sub graph for `newGraph`, keeping what is this node's own:
    /// its published inlet values, and its proxies, which follow their ports
    /// into the new instance so the parent's wires onto them, and any proxy
    /// wrapping them further up, stay as they are. The old graph is retired:
    /// its nodes are stopped through the renderer they ran under, and the
    /// edits made in it can no longer be undone, since they would act on
    /// nodes no longer in the document. Everything else the old graph held at
    /// runtime goes with it. The new graph's nodes start at the renderer's
    /// next lifecycle review, as nodes added to any graph do.
    internal func replaceSubGraph(with newGraph: Graph)
    {
        let old = self.subGraph
        let parent = self.graph
        let values = old.memberOwnInlets().mapValues { (portType: $0.portType, value: $0.snapshotValue()) }

        parent?.nodeObjectWillChange(self)
        self.forgetUndo(for: old)
        old.ownerNode = nil
        old.onPublishedPortsChanged = nil
        old.onCameraSelectionChanged = nil
        if let renderer = self.childGraphRenderer ?? self.lifecycleRenderer
        {
            do { try renderer.reconcileAllNodes(in: old, ceiling: .disabled, startsAllNodes: false) }
            catch { print("Graph lifecycle: \(self): \(error)") }
        }

        self.subGraph = newGraph
        newGraph.undoManager = old.undoManager
        self.wireSubGraphCallback()
        self.subGraphDidChange()
        Self.restore(values: values, in: newGraph)

        self.rebindProxyPorts()
        parent?.nodeObjectDidChange(self)
        parent?.updateCameraSelection()

        self.markDirty()
    }

    /// Points every proxy at its port in the current sub graph. A proxy whose
    /// port is gone, or is of another type now, is remade by the rebuild that
    /// follows; a retyped one keeps its id and published state, though the
    /// parent's wires onto it are re-made only where its new type allows.
    private func rebindProxyPorts()
    {
        let parent = self.graph
        let innerByID = Dictionary(self.subGraph.getPublishedPorts().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var retyped: [(identity: ProxyIdentity, wires: [(outletID: UUID, inletID: UUID, active: Bool)])] = []

        for proxy in self.proxyPorts
        {
            guard let typed = proxy as? any ProxyPortProtocol, let inner = innerByID[typed.innerPortID] else { continue }
            if typed.rebindInnerPort(to: inner) { continue }

            let wires = (parent?.connections ?? []).filter { $0.outletPortID == proxy.id || $0.inletPortID == proxy.id }
            retyped.append((ProxyIdentity(id: proxy.id, published: proxy.published, publishedName: proxy.publishedName),
                            wires.map { (outletID: $0.outletPortID, inletID: $0.inletPortID, active: $0.active) }))
            parent?.withoutUndoRegistration { for wire in wires { _ = parent?.disconnect(wire) } }
            self.reusableProxyIdentities[typed.innerPortID] = retyped.last?.identity
            self.proxyPorts.removeAll { $0 === proxy }
        }

        self.rebuildProxyPorts()
        self.reusableProxyIdentities = [:]

        guard let parent, !retyped.isEmpty else { return }
        parent.withoutUndoRegistration {
            for wire in retyped.flatMap(\.wires)
            {
                guard let outlet = parent.nodePort(forID: wire.outletID),
                      let inlet = parent.nodePort(forID: wire.inletID),
                      let connection = parent.connect(outlet, to: inlet)
                else { continue }
                _ = parent.setConnection(connection, active: wire.active)
            }
        }
    }

    /// The sub graph was swapped for another instance; a subclass that holds
    /// something per graph, a renderer or a scene, remakes it here.
    internal func subGraphDidChange() { }

    /// Drops every undo step that would act on `graph` or what is in it.
    private func forgetUndo(for graph: Graph)
    {
        guard let undoManager = graph.undoManager ?? self.graph?.undoManager else { return }
        undoManager.removeAllActions(withTarget: graph)
        for node in graph.nodes
        {
            undoManager.removeAllActions(withTarget: node)
            // A value set through its control is undone against its parameter.
            for parameter in node.ports.compactMap(\.parameter)
            {
                undoManager.removeAllActions(withTarget: parameter)
            }
            if let viewModel = graph.viewModelIfPresent(for: node)
            {
                undoManager.removeAllActions(withTarget: viewModel)
            }
            if let subgraphNode = node as? SubgraphNode
            {
                self.forgetUndo(for: subgraphNode.subGraph)
            }
        }
    }


    /// The saved per-member values, each read on its own, so one that cannot
    /// be read, of a plugin's port type that is not loaded say, costs only
    /// itself.
    private static func decodeMemberValues(from container: KeyedDecodingContainer<CodingKeys>) -> [String: AnyPort]?
    {
        guard let values = try? container.nestedContainer(keyedBy: MemberValueKey.self, forKey: .memberValues) else { return nil }
        var decoded: [String: AnyPort] = [:]
        for key in values.allKeys
        {
            do { decoded[key.stringValue] = try values.decode(AnyPort.self, forKey: key) }
            catch { print("SubgraphNode: member value \(key.stringValue) not read: \(error)") }
        }
        return decoded
    }

    private struct MemberValueKey: CodingKey
    {
        let stringValue: String
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    private static func decodeProxyPortsIfPossible(from container: KeyedDecodingContainer<CodingKeys>,
                                                   forKey key: CodingKeys) -> [Port]
    {
        do
        {
            return try container.decodeIfPresent([AnyPort].self, forKey: key)?.map(\.base) ?? []
        }
        catch
        {
            print("Failed to decode saved subgraph proxy ports: \(error)")
            return []
        }
    }

    private func wireSubGraphCallback()
    {
        self.subGraph.ownerNode = self
        self.subGraph.onPublishedPortsChanged = { [weak self] in
            self?.rebuildProxyPorts()
        }

        self.subGraph.onCameraSelectionChanged = { [weak self] in
            guard let self, !(self is DeferredSubgraphNode) else { return }
            self.graph?.updateCameraSelection()
        }
    }
     
    // Ensure we always render!
//    override public var isDirty:Bool { get {  true /*self.subGraph.needsExecution*/  } set { } }
    override open var isDirty:Bool { get {  self.subGraph.needsExecution  } set { } }


    override open func markClean()
    {
        for node in self.subGraph.nodes
        {
            node.markClean()
        }
        
        super.markClean()
    }
         
    override open func markDirty()
    {
        for node in self.subGraph.nodes
        {
            node.markDirty()
        }
        
        super.markDirty()
    }
    
    /// Ordinary subgraphs run on their parent's renderer; a deferred subgraph owns one.
    internal var childGraphRenderer: GraphRenderer? { nil }

    /// Iterator evaluates every inner node, connected or not.
    internal var startsAllChildNodes: Bool { false }

    override open func startExecution(renderer:GraphRenderer) throws
    {
        self.lifecycleRenderer = renderer
        self.transitionSubgraph(to: .started, renderer: renderer)
        try super.startExecution(renderer: renderer)
    }

    override open func stopExecution(renderer:GraphRenderer) throws
    {
        self.transitionSubgraph(to: .stopped, renderer: renderer)
        try super.stopExecution(renderer: renderer)
    }

    override open func enableExecution(renderer:GraphRenderer) throws
    {
        self.lifecycleRenderer = renderer
        self.transitionSubgraph(to: .enabled, renderer: renderer)
        try super.enableExecution(renderer: renderer)
    }

    override open func disableExecution(renderer:GraphRenderer) throws
    {
        self.transitionSubgraph(to: .disabled, renderer: renderer)
        try super.disableExecution(renderer: renderer)
    }

    /// An inner node's failure is reported, not thrown: it is that node's
    /// failure, not the subgraph node's, which still reaches its own state.
    private func transitionSubgraph(to state: ExecutionState, renderer: GraphRenderer)
    {
        do
        {
            if let childGraphRenderer = self.childGraphRenderer
            {
                try childGraphRenderer.transitionExecution(to: state)
            }
            else
            {
                try renderer.reconcileAllNodes(in: self.subGraph, ceiling: state, startsAllNodes: self.startsAllChildNodes)
            }
        }
        catch
        {
            renderer.errorDelegate?.renderer(renderer, didFailWith: error)
        }
    }

    open func forwardPortValues(force:Bool = false)
    {
        // Forward outlet values from inner ports to proxy ports so the
        // parent graph receives sub graph outputs.
        for port in self.proxyPorts where port.kind == .Outlet
        {
            (port as? any ProxyPortProtocol)?.forwardFromInner(force:force)
        }
    }
    
    override open func execute(renderer:GraphRenderer,
                                  executionInfo:GraphExecutionInfo,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer) throws    {
        
        // The inner pass runs every node it can and rethrows the first failure
        // afterwards, so outlets of the nodes that did run must still reach the
        // parent graph — the parent's markClean cascade clears their flags
        // whether or not this call threw.
        defer { self.forwardPortValues(force:true) }

        try renderer.execute(graph: self.subGraph,
                             executionInfo: executionInfo,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer,
                             clearFlags: false)
    }
}
