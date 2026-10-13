//
//  SubgraphNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/22/25.
//

import Foundation
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
    /// becomes the stored graph and its siblings are patched to it.
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
                            memberCount: self.cloneMemberCount)
    }

    /// How many members the set has, as of the last membership change
    /// (Graph.cloneSetMembershipChanged): the badge and status read the
    /// count on every refresh, and counting is a walk of the document.
    internal var cloneMemberCount = 1

    /// A member describes itself by its set's name, the way a Strategy node
    /// shows its strategy. The member count lives in the status's message.
    override open func deriveSubtitle() -> String? { self.cloneSetInfo?.name }

    /// A member reports itself linked to its set.
    override open func deriveStatuses() -> [NodeStatus] { self.cloneSetInfo.map { [$0.status] } ?? [] }

    /// The id each proxy this node has made had, by inner port id. A proxy
    /// made again over the same port, as when undo brings it back, takes it,
    /// so the parent's wires find it by id: a member's proxies made before it
    /// joined its set have their inner ports' ids, not the ids it would give
    /// them now.
    private var proxyIDsByInnerPortID: [UUID: UUID] = [:]

    /// The proxies standing for the sub graph's published ports, one each,
    /// as ports of this node in the graph around. Made as the node is built
    /// (see reconcileProxies()); after that, changed only as the sub graph
    /// tells this node of each change to its published set.
    private var proxyPorts: [Port] = []

    override open var ports:[Port] { self.proxyPorts + super.ports }

    override var parameterGroupPorts: [Port] { self.ports }

    /// The id a proxy over `port` stands under: the id of the proxy already
    /// over it, or of the last one this node made over it; otherwise the
    /// port's own, unless this node is a clone set member. A member's
    /// siblings wrap inner ports under the same ids in the same graph
    /// around, so its proxies take ids of their own.
    private func proxyID(for port: Port) -> UUID
    {
        if let existing = self.proxyPorts.first(where: { ($0 as? any ProxyPortProtocol)?.innerPortID == port.id })
        {
            return existing.id
        }
        if let remembered = self.proxyIDsByInnerPortID[port.id] { return remembered }
        guard self.cloneSetID != nil else { return port.id }
        // Kept once made, and encoded with the proxy, so every instance
        // decoded from this member agrees.
        let id = UUID()
        self.proxyIDsByInnerPortID[port.id] = id
        return id
    }

    private func proxy(over port: Port) -> Port?
    {
        let id = self.proxyID(for: port)
        return self.proxyPorts.first { $0.id == id }
    }

    /// `port` has joined the sub graph's published set.
    internal func innerPortDidPublish(_ port: Port)
    {
        guard self.proxy(over: port) == nil,
              let proxy = Self.makeProxy(for: port, id: self.proxyID(for: port))
        else { return }

        proxy.node = self
        self.proxyPorts.append(proxy)
        self.proxiesDidChange()
    }

    /// `port` is about to leave the sub graph's published set. Its proxy takes
    /// its wires off and leaves the published set of the graph around, which
    /// tells the node around that graph in turn, before it goes.
    internal func innerPortWillUnpublish(_ port: Port)
    {
        guard let proxy = self.proxy(over: port) else { return }
        self.dropProxy(proxy)
    }

    private func dropProxy(_ proxy: Port)
    {
        if let typed = proxy as? any ProxyPortProtocol { self.proxyIDsByInnerPortID[typed.innerPortID] = proxy.id }
        if let graph = self.graph
        {
            let undoManager = graph.effectiveUndoManager
            undoManager?.beginUndoGrouping()
            graph.disconnectAll(from: proxy)
            graph.setPublished(false, on: proxy)
            undoManager?.endUndoGrouping()
        }

        self.proxyPorts.removeAll { $0 === proxy }
        proxy.node = nil
        self.proxiesDidChange()
    }

    /// `new` has replaced `old` in the sub graph's published set under its
    /// id. A proxy of the same value type forwards to `new` in place; one of
    /// another type is made again under the same id, published as it was.
    /// Either way the graph around keeps the wires the proxy can still take.
    internal func innerPort(_ old: Port, wasReplacedBy new: Port)
    {
        guard let proxy = self.proxy(over: old) else
        {
            self.innerPortDidPublish(new)
            return
        }

        if let retargeted = proxy as? any ProxyPortProtocol, retargeted.retarget(to: new)
        {
            self.graph?.rebindWires(from: proxy, to: proxy)
            self.proxiesDidChange()
            // A proxy above forwards to this one, and takes its parameter again.
            if proxy.published { self.graph?.port(proxy, wasReplacedBy: proxy) }
            return
        }

        guard let index = self.proxyPorts.firstIndex(where: { $0 === proxy }),
              let remade = Self.makeProxy(for: new, id: proxy.id)
        else
        {
            self.innerPortWillUnpublish(old)
            return
        }

        remade.setPublishing(proxy.published, name: proxy.publishedName)
        remade.node = self
        self.graph?.rebindWires(from: proxy, to: remade)
        self.proxyPorts[index] = remade
        proxy.node = nil
        self.proxiesDidChange()
        if remade.published { self.graph?.port(proxy, wasReplacedBy: remade) }
    }

    /// `port`, published in the sub graph, has a new published name, which
    /// its proxy shows unless it has one of its own.
    internal func innerPortDidRename(_ port: Port)
    {
        guard let proxy = self.proxy(over: port) else { return }

        self.proxiesDidChange()
        if proxy.published { self.graph?.portDidRename(proxy) }
    }

    /// Brings the proxies to the sub graph's published set, once, as the node
    /// is built: a decoded proxy is kept where it forwards to the published
    /// port under its id, made again where that port was replaced, and dropped
    /// where none is published; a published port with no proxy gets one.
    private func reconcileProxies()
    {
        let innerPorts = self.subGraph.getPublishedPorts()
        let innerPortsByProxyID = Dictionary(innerPorts.map { (self.proxyID(for: $0), $0) }, uniquingKeysWith: { first, _ in first })

        var proxies: [Port] = []
        for proxy in self.proxyPorts
        {
            guard let innerPort = innerPortsByProxyID[proxy.id],
                  let typed = proxy as? any ProxyPortProtocol
            else { continue }

            if typed.wraps(innerPort)
            {
                proxies.append(proxy)
            }
            else if let remade = Self.makeProxy(for: innerPort, id: proxy.id)
            {
                remade.setPublishing(proxy.published, name: proxy.publishedName)
                proxies.append(remade)
            }
        }

        for innerPort in innerPorts where !proxies.contains(where: { $0.id == self.proxyID(for: innerPort) })
        {
            if let proxy = Self.makeProxy(for: innerPort, id: self.proxyID(for: innerPort))
            {
                proxies.append(proxy)
            }
        }

        proxies.forEach { $0.node = self }
        self.proxyPorts = proxies
        self.proxiesDidChange()
    }

    /// Makes the proxies over the inner ports `ids` names again under the
    /// ids it gives, where they stand under others: a clone set member's
    /// proxies take ids of their own, and every instance of the member holds
    /// them under the same ones, those its set's stored graph has. A wire
    /// names a proxy by id, so the graph around loses the wires on a proxy
    /// made again; the caller binds the ones it wants. Undoable: on undo, the
    /// step puts the ids back before the steps registered ahead of it run,
    /// which find the proxies by them.
    internal func remakeProxies(withIDs ids: [UUID: UUID])
    {
        var previous: [UUID: UUID] = [:]
        for proxy in self.proxyPorts
        {
            guard let typed = proxy as? any ProxyPortProtocol,
                  let id = ids[typed.innerPortID], proxy.id != id,
                  let innerPort = self.subGraph.nodePort(forID: typed.innerPortID),
                  let remade = Self.makeProxy(for: innerPort, id: id)
            else { continue }

            if let graph = self.graph
            {
                graph.rebindWires(from: proxy, to: remade)
                graph.setPublished(false, on: proxy)
            }
            guard let index = self.proxyPorts.firstIndex(where: { $0 === proxy }) else { continue }
            previous[typed.innerPortID] = proxy.id
            self.proxyIDsByInnerPortID[typed.innerPortID] = id
            remade.node = self
            self.proxyPorts[index] = remade
            proxy.node = nil
        }
        guard !previous.isEmpty else { return }
        self.proxiesDidChange()

        self.graph?.registerUndo(on: self) { node in
            node.remakeProxies(withIDs: previous)
        }
    }

    private func proxiesDidChange()
    {
        self.invalidatePortCaches()
        self.rebuildParameterGroup()

        self.graph?.markConnectionsChanged()
        self.portsChangedSubject.send()
    }

    /// Whether a proxy can stand for `port`, published in a sub graph.
    internal static func canProxy(_ port: Port) -> Bool
    {
        self.makeProxy(for: port, id: port.id) != nil
    }

    /// Type-erase proxy creation — matches the inner port's generic type.
    private static func makeProxy(for port: Port, id: UUID) -> Port?
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
        self.reconcileProxies()
    }

    /// Wrap an existing graph as this node's sub graph, for embedders that
    /// decode a graph separately and then nest it.
    public init(context: Context, subGraph: Graph)
    {
        self.subGraph = subGraph

        super.init(context: context)
        self.wireSubGraphCallback()
        self.reconcileProxies()
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

        // In a set's stored graph, or on its way to being instantiated, a
        // member in step with its set is written as a reference to it and
        // the values that are its own; see Graph.cloneSetReferencesKey. The
        // proxies are the member's face in the parent graph, published and
        // named there per member, so they are written either way.
        try container.encode(self.proxyPorts.map(AnyPort.init), forKey: .proxyPorts)
        if encoder.userInfo[Graph.cloneSetReferencesKey] as? Bool == true, self.isInStepWithCloneSet
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
        self.reconcileProxies()
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
