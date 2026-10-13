//
//  NodeProtocol.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Metal
import Satin
import Combine
import UniformTypeIdentifiers


/// Runtime lifecycle of a GraphRenderer and of each Node it drives; never serialized with a graph.
public enum ExecutionState {
    case enabled
    case started
    case stopped
    case disabled
}

open class Node : Codable, Equatable, Identifiable, Hashable, Copyable, CustomDebugStringConvertible
{
    // The name this node type is registered and listed under (each subclass
    // overrides). Read it off an instance as `title`.
    open class var name: String {  fatalError("\(String(describing:self)) Must implement name") }

    // User interface organizing principle
    open class var nodeType:Node.NodeType { fatalError("\(String(describing:self)) Must implement nodeType") }

    // Execution mode value is used to determine when this node is evaluated
    open class var nodeExecutionMode: Node.ExecutionMode { fatalError("\(String(describing:self)) Must implement nodeExecutionMode") }

    // Execution mode value is used to determine when this node is evaluated
    open class var nodeTimeMode: Node.TimeMode {  fatalError("\(String(describing:self)) Must implement nodeTimeMode") }

    // User interface description
    open class var nodeDescription: String { fatalError("\(String(describing:self)) Must implement nodeDescription") }

    // Identifiable
    public let id:UUID

    // Hashable
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }

    // Equatable
    public static func == (lhs: Node, rhs: Node) -> Bool
    {
        return lhs.id == rhs.id
    }

    // The instance title. Most nodes use their registered type name; nodes
    // backed by instance-specific resources can override deriveTitle().
    final public var title : String
    {
        let derivedTitle = self.deriveTitle()
        return derivedTitle.isEmpty ? Self.name : derivedTitle
    }

    // Override when an instance has a more specific authoritative title than
    // its registered type name, e.g. a shader-backed BaseImageNode.
    open func deriveTitle() -> String { Self.name }

  
    // The resolved subtitle: the user's rename when present, otherwise the
    // node-generated description. Never empty or equal to the registered title.
    final public var subtitle: String?
    {
        let resolvedSubtitle = self.userName ?? self.deriveSubtitle()
        guard let resolvedSubtitle,
              !resolvedSubtitle.isEmpty,
              resolvedSubtitle != self.title
        else
        {
            return nil
        }
        return resolvedSubtitle
    }

    // Node-generated subtitle, e.g. Math Expression shows its expression.
    // Override where the node describes itself; nil for none. Raw: empty is
    // allowed here and reads as absence. Read `subtitle`, never this.
    open func deriveSubtitle() -> String? { nil }

    // What the node has to tell the person looking at it: Math Expression's
    // parse error, for one. Override where the node has something to report,
    // in any order; empty for nothing. Read `statuses` or `status`, never this.
    open func deriveStatuses() -> [NodeStatus] { [] }

    // The node's statuses, most severe first. The title row shows the first
    // one's glyph and lists them all on hover. Derived afresh on each read, so
    // read it once and hold what comes back.
    final public var statuses: [NodeStatus]
    {
        let derived = self.deriveStatuses()
        return derived.count > 1 ? derived.sorted(by: >) : derived
    }

    // The most severe of the node's statuses; nil for none.
    final public var status: NodeStatus? { self.deriveStatuses().max() }

    // User-supplied rename. Wins over the node-derived subtitle. Empty is
    // absence: a cleared rename must reveal the derived subtitle again.
    final public var userName: String?
    {
        didSet
        {
            if userName?.isEmpty == true { userName = nil }
            subtitleSubject.send()
        }
    }
    
    // CustomDebugStringConvertible: the registered title and resolved subtitle.
    final public var debugDescription: String
    {
        guard let subtitle = self.subtitle else { return self.title }
        return "\(self.title) (\(subtitle))"
    }

    open var nodeType:NodeType
    {
        return Self.nodeType
    }

    open var nodeExecutionMode:ExecutionMode
    {
        return Self.nodeExecutionMode
    }
    
    public var nodeTimeMode: TimeMode
    {
        return Self.nodeTimeMode
    }

    public private(set) var context:Context

    public internal(set) weak var graph:Graph?

    /// The ports every node of the class has, in order, under their registry
    /// keys. The default declaredPorts().
    open class func registerPorts(context: Context) -> [(name: String, port: Port)] { [] }
    // All port serilization, adding, removing and key value access goes through the port registry
    internal let registry = PortRegistry()

    // Sadly this needs to be observed
    public let parameterGroup:ParameterGroup = ParameterGroup("Parameters", [])

    open var ports:[Port] { self.registry.all()   }
    private var cachedInputPorts: [Port]?
    private var cachedOutputPorts: [Port]?
    public private(set) var inputNodes:[Node] = []
    public private(set) var outputNodes:[Node]  = []

    /// How a node answers the renderer's pull for one of its output ports.
    public enum PullResponse
    {
        /// Run this node this pass, after pulling the upstream nodes feeding
        /// these input ports.
        case evaluate(pulling: [Port])

        /// The requested output port is inactive (an unselected route): the
        /// node does not run for this pull and the port's consumers see a
        /// frozen value. The renderer still pulls the upstream nodes feeding
        /// `keepAlive` — the control inputs (Index, map) whose values let the
        /// node select a different route later. A node must never decline a
        /// nil requested port.
        case declined(keepAlive: [Port])
    }

    /// Answer a pull for `requestedOutputPort` (nil when the pull is not for a
    /// specific port, e.g. a consumer root). The default evaluates
    /// unconditionally, depending on every inlet; routing nodes override this
    /// to expose only their active branch's data/control dependencies, or to
    /// decline pulls for unselected outputs.
    open func respondToPull(requestedOutputPort: Port?) -> PullResponse { .evaluate(pulling: inputPorts()) }

    public var nodeSize:CGSize { self.computeNodeSize() }

    public var offset: CGSize = .zero
    {
        didSet { offsetSubject.send(offset) }
    }

    // Readable by Node subclasses (e.g. AudioSpectrumNode checks self.showSettings
    // to decide whether to compute visualisation data). Written by NodeViewModel.
    public internal(set) var showSettings: Bool = false

    // MARK: - Combine subjects for NodeViewModel sync

    /// Fires whenever offset changes so NodeViewModel can update its cached copy.
    internal let offsetSubject = CurrentValueSubject<CGSize, Never>(.zero)

    /// Fires whenever the port list changes.
    internal let portsChangedSubject = PassthroughSubject<Void, Never>()

    /// Fires whenever state feeding `title`, `subtitle` or `status` changes.
    /// NodeViewModel subscribes and refreshes its observable title row mirrors.
    internal let subtitleSubject = PassthroughSubject<Void, Never>()

    // Dirty Handling
    private(set) public var isDirty: Bool = true

    // Input Parameter update tracking:
    var inputParamCancellables: [AnyCancellable] = []


    // MARK: - Serialization and Init
    enum CodingKeys : String, CodingKey
    {
        case id
        case nodeOffset
        case ports

        case userName

        // Depreciated...
        case inputParameters
    }

    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        self.context = decodeContext.documentContext
        self.graph = decodeContext.currentGraph

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.offset = try container.decode(CGSize.self, forKey: .nodeOffset)
        // didSet does not fire during init; normalize the decoded rename here.
        let decodedUserName = try container.decodeIfPresent(String.self, forKey: .userName)
        self.userName = decodedUserName?.isEmpty == true ? nil : decodedUserName

        // Declare, then hydrate: the port set comes from the code's
        // declarations, here and in any reconcile a subclass makes once it has
        // read its source, and the document contributes only the state it
        // owns, applied per registry key as each port registers. Snapshot keys
        // that never match a declared port surface via droppedPortStateKeys
        // instead of resurrecting retired ports. Order is the declarations',
        // whatever order the document lists them in.
        let snaps = try container.decodeIfPresent([PortRegistry.Snapshot].self, forKey: .ports) ?? []
        self.portHydrationSession = PortHydrationSession(snapshots: snaps)

        self.reconcilePorts()
        self.adoptPortsOutsideRegistry()
    }

    open func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.id, forKey: .id)
        try container.encode(self.offset, forKey: .nodeOffset)
        try container.encode(self.registry.encode(), forKey: .ports)
        try container.encodeIfPresent(self.userName, forKey: .userName)
        try self.settings?.encode(to: encoder)
    }

    public required init(context:Context)
    {
        self.id = UUID()
        self.context = context

        self.reconcilePorts()
        self.adoptPortsOutsideRegistry()
    }

    /// A subclass that keeps ports in stored properties of its own, outside the
    /// registry, has them name this node.
    private func adoptPortsOutsideRegistry()
    {
        for port in self.ports where port.node !== self
        {
            port.node = self
        }
    }

    open class func initWithContext(context: Context) throws -> Node
    {
        self.init(context: context)
    }

    deinit
    {
//        print("Deleted node \(id)")
    }


    // This function clears references to other nodes and node ports
    // removing any circular references allowing proper cleanup
    // This must is called by GraphRenderer.
    internal func teardown()
    {
        self.inputNodes.removeAll()
        self.outputNodes.removeAll()

        for port in self.ports
        {
            if let graph = self.graph {
                graph.disconnectAll(from: port)
            }
            port.teardown()
        }

        self.inputParamCancellables.forEach { $0.cancel() }
        self.inputParamCancellables.removeAll()
    }

    // MARK: - Ports

    // Convenience for subclasses: typed lookup (so computed props stay nice)
    public func port<T: Port>(named name: String, as type: T.Type = T.self) -> T
    {
        self.registry.port(named: name) as! T
    }

    // Convenience for subclasses: typed lookup (so computed props stay nice)
    public func findPort<T: Port>(named name: String, as type: T.Type = T.self) -> T?
    {
        self.registry.port(named: name) as? T
    }

    // MARK: - Port state hydration (declare-then-hydrate decode)

    /// The document's port state for the duration of decode; nil otherwise.
    /// Graph finalizes and clears it once node inits, and the reconciles they
    /// make, are done, so ports added later in the node's life can never
    /// resurrect stale document state.
    private var portHydrationSession: PortHydrationSession?

    /// Registry keys from the document whose port state found no declared
    /// port to land on. Dropping that state is deliberate — the code
    /// owns the port set — but it is data loss, so Graph reports it after
    /// decode rather than discarding silently.
    internal var droppedPortStateKeys: [String] { self.portHydrationSession?.unconsumedKeys ?? [] }

    /// Registers the document's remaining port state as ports in their own
    /// right, declared after the node's own. A node whose source cannot
    /// declare its port set at decode time (an unparseable script, a shader
    /// that no longer compiles) would otherwise decode with none of the ports
    /// the document saved, taking every wire with them and making the loss
    /// permanent at the next save. The decoded instances carry their saved
    /// identity, value and published state, so once the node declares again a
    /// declared port under the same key and type is the kept one, and keeps
    /// its wires.
    ///
    /// Only ever does anything mid-decode, and must run inside the node's init
    /// path so Graph still sees the keys as adopted rather than dropped.
    internal func adoptRemainingSnapshotPortsAsFallback()
    {
        guard let session = self.portHydrationSession else { return }

        for (registryKey, port) in session.drainPendingSnapshots()
            where self.registry.port(named: registryKey) == nil
                && !self.ports.contains(where: { $0.id == port.id })
                && !self.undeclaredSnapshotPorts.contains(where: { $0.registryKey == registryKey })
        {
            self.undeclaredSnapshotPorts.append(PortDeclaration(registryKey: registryKey, port: port))
        }
        self.reconcilePorts()
    }

    /// The ports adoptRemainingSnapshotPortsAsFallback() kept, declared after
    /// the node's own until the node can declare its interface again and lets
    /// them go with discardUndeclaredSnapshotPorts().
    private var undeclaredSnapshotPorts: [PortDeclaration] = []

    /// Lets go of the ports kept from the document while the node could not
    /// declare its interface. A kept port the node now declares under the same
    /// key and type stays, as declared ports do; the rest go at the next
    /// reconcilePorts().
    internal func discardUndeclaredSnapshotPorts()
    {
        self.undeclaredSnapshotPorts.removeAll()
    }

    /// Ends the decode-time hydration window, returning the registry keys
    /// whose state never found a port.
    internal func finalizePortHydration() -> [String]
    {
        let droppedKeys = self.droppedPortStateKeys
        self.portHydrationSession = nil
        return droppedKeys
    }

    // MARK: - Declared ports

    /// The node's whole interface, in order: every port it has, under the
    /// registry key it is found by. reconcilePorts() brings the live ports to
    /// it. By default the class's registerPorts(context:). A node whose ports
    /// follow its settings, or a device or source it reads at runtime,
    /// overrides it and computes from that state; fixed and derived ports
    /// interleave freely, and the list is the order. Called for every
    /// reconcile, so it makes no ports it does not return and changes nothing.
    open func declaredPorts() -> [PortDeclaration]
    {
        Self.registerPorts(context: self.context).map { PortDeclaration(registryKey: $0.name, port: $0.port) }
    }

    /// Brings the node's ports to declaredPorts(). A port kept under its key
    /// and type keeps its wires and value; a retyped one is replaced in place
    /// under its id, keeping the wires it can take; a removed one takes its
    /// wires and proxies with it, as undo steps of the edit in progress. A node
    /// with settings has it from apply(_:); a node whose interface changes
    /// outside its settings calls it once it has changed what declaredPorts()
    /// reads.
    public final func reconcilePorts()
    {
        let declarations = self.declaredPorts() + self.directlyAddedPorts + self.undeclaredSnapshotPorts

        let reconciliation = self.registry.reconcile(to: declarations, owner: self, hydrating: self.portHydrationSession)
        guard !reconciliation.isEmpty else { return }

        let graph = self.graph

        for port in reconciliation.removed
        {
            if port.published { graph?.portWillUnpublish(port) }
            graph?.disconnectAll(from: port)
        }

        for (old, new) in reconciliation.replaced
        {
            graph?.rebindWires(from: old, to: new)

            // Hydration may have given the replacement publishing of its own.
            switch (old.published, new.published)
            {
            case (true, true):
                graph?.port(old, wasReplacedBy: new)
            case (true, false):
                graph?.portWillUnpublish(old)
            case (false, true):
                graph?.portDidPublish(new)
            case (false, false):
                break
            }
        }

        for port in reconciliation.added where port.published
        {
            graph?.portDidPublish(port)
        }

        // A retired port is detached, so a transient view holding it cannot
        // reconnect it under the id its replacement now has.
        for port in reconciliation.removed + reconciliation.replaced.map(\.old)
        {
            port.node = nil
        }

        if reconciliation.removed.contains(where: \.published)
            || reconciliation.replaced.contains(where: { $0.old.published && !$0.new.published })
        {
            graph?.rebuildPublishedParameterGroup()
        }

        self.invalidatePortCaches()
        self.rebuildParameterGroup()
        graph?.markConnectionsChanged()
        self.portsChangedSubject.send()
    }

    /// The ports whose parameters make the node's parameter group.
    internal var parameterGroupPorts: [Port] { self.registry.all() }

    /// The parameters of the node's ports, in port order.
    internal func rebuildParameterGroup()
    {
        let parameters = self.parameterGroupPorts.compactMap(\.parameter)
        let current = self.parameterGroup.params
        guard parameters.count != current.count
                || zip(parameters, current).contains(where: { $0 !== $1 })
        else { return }

        self.parameterGroup.clear()
        self.parameterGroup.append(parameters)
        self.synchronizeParameters()
    }

    /// Adds `port` under `name`, or its own name, declared after the node's
    /// own ports for the rest of its life.
    @available(*, deprecated, message: "Declare the port in declaredPorts(); reconcilePorts() makes it, and keeps its order and identity.")
    public func addDynamicPort(_ port: Port, name: String? = nil)
    {
        self.directlyAddedPorts.append(PortDeclaration(registryKey: name ?? port.name, port: port))
        self.reconcilePorts()
    }

    /// The ports addDynamicPort(_:name:) has added.
    private var directlyAddedPorts: [PortDeclaration] = []

    /// The key the port is registered under: the declared or dynamic name, where
    /// the port's own `name` is what it displays.
    internal func registryKey(of port: Port) -> String?
    {
        self.registry.name(of: port)
    }

    internal func replaceParameterOfPort(_ port:Port, withParam param:(any Parameter))
    {
        port.parameter = param
        self.rebuildParameterGroup()
    }

    internal func inputPorts() -> [Port]
    {
        if let cachedInputPorts {
            return cachedInputPorts
        }

        let inputPorts = self.ports.filter { $0.kind == .Inlet }
        self.cachedInputPorts = inputPorts
        return inputPorts
    }

    internal func outputPorts() -> [Port]
    {
        if let cachedOutputPorts {
            return cachedOutputPorts
        }

        let outputPorts = self.ports.filter { $0.kind == .Outlet }
        self.cachedOutputPorts = outputPorts
        return outputPorts
    }

    internal func invalidatePortCaches()
    {
        self.cachedInputPorts = nil
        self.cachedOutputPorts = nil
    }

    internal func publishedPorts() -> [Port]
    {
        return self.ports.filter(\.published)
    }

    internal func publishedInputPorts() -> [Port]
    {
        return self.inputPorts().filter(\.published)
    }

    internal func publishedOutputPorts() -> [Port]
    {
        return self.outputPorts().filter(\.published)
    }

    // MARK: - Connections

    internal func didConnectToNode(_ node: Node)
    {
        self.inputNodes = calcInputNodes()
        self.outputNodes = calcOutputNodes()
    }

    internal func didDisconnectFromNode(_ node: Node)
    {
        self.inputNodes = calcInputNodes()
        self.outputNodes = calcOutputNodes()
    }

    private func calcInputNodes() -> [Node]
    {
        let nodeInputs = self.ports.filter( { $0.kind == .Inlet } )
        let inputNodes = nodeInputs.compactMap { $0.connectedPorts.compactMap(\.node) }.flatMap(\.self)

        return inputNodes
    }

    private func calcOutputNodes() -> [Node]
    {
        let nodeOutputs = self.ports.filter( { $0.kind == .Outlet } )
        let outputNodes = nodeOutputs.compactMap { $0.connectedPorts.compactMap(\.node) }.flatMap(\.self)

        return outputNodes
    }

    public func markClean()
    {
        isDirty = false

        // See https://github.com/Fabric-Project/Fabric/issues/41
        for port in ports
        {
            port.valueDidChange = false
        }
    }

    public func markDirty()
    {
        isDirty = true
    }

    public func synchronizeParameters()
    {
        self.inputParamCancellables.forEach( { $0.cancel() } )
        self.inputParamCancellables.removeAll()

        for parameter in self.parameterGroup.params
        {
            let cancellable = self.makeCancelable(parameter: parameter)

            self.inputParamCancellables.append(cancellable)
        }
    }

    private func makeCancelable(parameter: some Parameter) -> AnyCancellable
    {
        let cancellable = parameter.valuePublisher.eraseToAnyPublisher().sink{ [weak self] _ in
            self?.markDirty()
        }

        return cancellable
    }

    open func updateConnectionTopology()
    {
    }

    // MARK: - Execution

    /// Overrides must call super after successful work. Stopped nodes remain enabled.
    /// A throwing callback leaves the state at its last completed transition.
    public private(set) var executionState: ExecutionState = .disabled

    open func startExecution(renderer:GraphRenderer) throws { executionState = .started }
    open func stopExecution(renderer:GraphRenderer) throws { executionState = .stopped }

    open func enableExecution(renderer:GraphRenderer) throws {
        executionState = .enabled
    }
    open func disableExecution(renderer:GraphRenderer) throws {
        executionState = .disabled
    }

    open func execute(renderer:GraphRenderer,
                      executionInfo:GraphExecutionInfo,
                      renderPassDescriptor: MTLRenderPassDescriptor,
                      commandBuffer: MTLCommandBuffer) throws { }

    open func resize(size: (width: Float, height: Float), scaleFactor: Float) { }

    // MARK: - Node Settings

    public enum SettingsViewSize
    {
        case Mini
        case Small
        case Medium
        case Large
        case Custom(size:CGSize)

        func size() -> CGSize
        {
            switch self
            {
            case .Mini:
                return CGSize(width: 300, height: 100)
            case .Small:
                return CGSize(width: 300, height: 200)
            case .Medium:
                return CGSize(width: 400, height: 300)
            case .Large:
                return CGSize(width: 500, height: 400)
            case .Custom(size: let size):
                return size
            }
        }

    }

    open func providesSettingsView() -> Bool
    {
        return false
    }

    open func settingsView() -> AnyView
    {
        AnyView(EmptyView())
    }

    open var settingsSize:SettingsViewSize { .Small }

    /// The node's settings, nil for a node without. See NodeSettings.
    open var settings: (any NodeSettings)? { nil }

    /// Brings the node, its ports included, to `settings`: from a settings view
    /// through Graph.setSettings(_:on:), from the procedural API, and from undo.
    /// A port whose registry key survives the change keeps its identity. A
    /// subclass takes its own type out of the existential and calls super with
    /// the same value.
    /// The base brings the ports to declaredPorts(), once, after every level
    /// has taken its part.
    open func apply(_ settings: any NodeSettings)
    {
        self.reconcilePorts()
    }

    /// Sent when the node's settings change: as an edit, undo and redo
    /// included, or as a device the node reconnects to sets them. A settings
    /// view holding a draft takes the node's value.
    internal let settingsChangedSubject = PassthroughSubject<Void, Never>()

    // MARK: - Helpers

    func computeNodeSize() -> CGSize
    {
        let inputPorts = self.inputPorts()
        let outputPorts = self.outputPorts()
        
        let longestInputPortTitle = inputPorts.reduce(into: "") { maxTitle, port in
            maxTitle = (maxTitle.count > port.displayName.count) ? maxTitle : port.displayName
        }

        let longestOutputPortTitle = outputPorts.reduce(into: "") { maxTitle, port in
            maxTitle = (maxTitle.count > port.displayName.count) ? maxTitle : port.displayName
        }

        let horizontalMax = max(inputPorts.count, outputPorts.count)

        let height:CGFloat = 40 + (CGFloat(horizontalMax) * 25)

        // heuristic to choose width without calculating pixel values from rendering a string
        let width:CGFloat = 20.0 + (6.0 * CGFloat(longestOutputPortTitle.count + longestInputPortTitle.count))

        return CGSize(width: max(width, 150), height: max(height, 60) )
    }

}

/// Nodes that are constructed from a file (e.g. Metal shader effect nodes),
/// or accept a user-dropped file via a file-path parameter port. Conformers
/// declare which UTTypes they handle and receive the URL after normal
/// construction via ``setFileURL(_:)``.
///
/// For conformers that expose a user-editable file-path parameter, decoding
/// restores the saved reference but does not load it. Runtime assets load
/// during execution, so a missing or invalid external file cannot prevent the
/// node itself from deserializing.
public protocol NodeFileLoadingProtocol : Node
{
    init(context:Context, fileURL:URL) throws
    func setFileURL(_ url: URL)

    static var supportedContentTypes: [UTType] { get }
}

public extension NodeFileLoadingProtocol
{
    /// Consume a picker URL during changed-input handling, outside parameter
    /// publisher delivery. Connected inputs and unfinished text paths stay as-is;
    /// the graph also normalizes file references when saving.
    func normalizeFileReference(_ port: ParameterPort<String>)
    {
        guard port.connectedOutlets.isEmpty,
              let directoryURL = self.graph?.fileReferenceBaseURL,
              let reference = port.value, reference.hasPrefix("file://"),
              let url = DocumentFileReference.resolve(reference, relativeTo: directoryURL)
        else { return }

        let relativeReference = DocumentFileReference.reference(for: url, relativeTo: directoryURL)
        if reference != relativeReference
        {
            port.value = relativeReference
        }
    }

    /// A file that ships inside the package bundle is persisted by its path
    /// below the bundle's resource root, not its URL: the bundle sits somewhere
    /// different on every machine and in every build, so an absolute path would
    /// bind the document to the machine that wrote it. Nil for a URL outside
    /// the bundle, which has no bundle-relative spelling — the encode site
    /// decides what such a file persists as.
    static func bundleRelativeResourcePath(for url: URL) -> String?
    {
        guard let resourceRoot = Bundle.module.resourceURL else { return nil }

        let base = resourceRoot.absoluteURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let full = url.absoluteURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents

        guard full.count > base.count, full.starts(with: base) else { return nil }

        return full.dropFirst(base.count).joined(separator: "/")
    }

    static func resolveBundleResource(path: String) -> URL?
    {
        Bundle.module.resourceURL?.absoluteURL.appending(path: path)
    }
}
