//
//  NodeProtocol.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Metal
import Satin
import Synchronization
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

    // Runtime-only hint, validated by each renderer against its own planning entries.
    // This is neither serialized identity nor mutable execution state.
    internal final var executionPlanningSlot: Int = -1

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
            namingDidChange()
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

    /// The node's interface, in order, under the keys the registry finds each
    /// port by. A node holds each port it always has in a stored property and
    /// declares that object here, ahead of or after super's, so the property
    /// and the registry name one port: `public let x = ParameterPort(…)`, then
    /// `super.declaredPorts() + [PortDeclaration(key: "x", port: x)]`. Ports
    /// that follow a setting or a source are declared here too, made from the
    /// state they follow. Called at every reconcile, from init and decode
    /// onward, after the subclass's stored properties are set. None by default.
    open func declaredPorts() -> [PortDeclaration] { [] }
    // All port serilization, adding, removing and key value access goes through the port registry
    internal let registry = PortRegistry()

    // Sadly this needs to be observed
    public let parameterGroup:ParameterGroup = ParameterGroup("Parameters", [])

    open var ports:[Port] { self.registry.all()   }
    private var cachedInputPorts: [Port]?
    private var cachedOutputPorts: [Port]?
    internal var deferredResultsBinding: GraphDeferredNodeBinding?
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
        didSet { self.viewModel?.offsetDidChange() }
    }

    // Readable by Node subclasses (e.g. AudioSpectrumNode checks self.showSettings
    // to decide whether to compute visualisation data). Written by NodeViewModel.
    public internal(set) var showSettings: Bool = false

    // MARK: - Telling the view model

    /// The view model the graph made for this node, which sets it. Held here
    /// rather than looked up in the graph so a hop to main reads no graph
    /// state another thread may be editing.
    internal weak var viewModel: NodeViewModel?

    /// Tells the node's view model, where its graph has one, that the port
    /// list changed. Called on the thread that made the change, so the view
    /// model reads the ports where they were written.
    internal func portsDidChange()
    {
        self.viewModel?.portsDidChange()
    }

    /// Call whenever state feeding `title`, `subtitle` or `status` changes,
    /// from any thread. On main the view model refreshes its title row there
    /// and then; from elsewhere, on main once for however many calls arrive
    /// before it gets there. The hop holds the node until it runs, so a call on
    /// main does not take it, or a deleted node would outlive its last turn.
    internal func namingDidChange()
    {
        if Thread.isMainThread
        {
            self.viewModel?.namingDidChange()
            return
        }
        guard !self.namingRefreshPending.exchange(true, ordering: .acquiringAndReleasing) else { return }
        self.performOnMainAsync {
            self.namingRefreshPending.store(false, ordering: .releasing)
            self.viewModel?.namingDidChange()
        }
    }

    private let namingRefreshPending = Atomic<Bool>(false)

    /// Call whenever state an open settings view shows changes, its settings
    /// above all, from any thread. On main the settings model refreshes there
    /// and then; from elsewhere, on main once for however many calls arrive
    /// before it gets there, as namingDidChange() does. The hop does not hold
    /// the node.
    public final func settingsDidChange()
    {
        if Thread.isMainThread
        {
            MainActor.assumeIsolated { self.refreshSettingsModel() }
            return
        }
        guard !self.settingsRefreshPending.exchange(true, ordering: .acquiringAndReleasing) else { return }
        self.performOnMainAsync { [weak self] in
            guard let self else { return }
            self.settingsRefreshPending.store(false, ordering: .releasing)
            self.refreshSettingsModel()
        }
    }

    private let settingsRefreshPending = Atomic<Bool>(false)

    /// Override where the node holds a settings model a view made: bring it
    /// to the node. Called through settingsDidChange(), on main; never call it.
    @MainActor
    open func refreshSettingsModel() { }

    // Dirty Handling
    private var inputsAreDirty = true
    /// Nested execution defers cleanup until its enclosing graph finishes. Only nodes that
    /// actually ran may have their input changes consumed by that cleanup.
    internal var hasPendingExecutionCleanup = false
    /// Whether this processor needs another execution. Plugins may include pending owner-consumed
    /// results in this hook; markDirty()/markClean() still own the underlying input dirty flag.
    open var isDirty: Bool { inputsAreDirty }



    // MARK: - Serialization and Init
    enum CodingKeys : String, CodingKey
    {
        case id
        case nodeOffset
        case ports

        case userName
        case lastCompiledSource

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
        // read its source, and the document contributes only the values of
        // its parameter inlets, by key, applied as each port is made. A key
        // that never matches a declared port surfaces via droppedPortStateKeys.
        // Order is the declarations'.
        let saved = try container.decodeIfPresent([String: LossyPortValue].self, forKey: .ports) ?? [:]
        self.lastCompiledSource = try container.decodeIfPresent(String.self, forKey: .lastCompiledSource)
        self.portHydrationSession = PortHydrationSession(states: saved.compactMap { key, saved in
            saved.value.map { PortState(key: .own(key), value: $0) }
        })
        self.reconcilePorts()
    }

    open func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.id, forKey: .id)
        try container.encode(self.offset, forKey: .nodeOffset)
        var values: [String: PortValue] = [:]
        for state in self.registry.states()
        {
            guard case .own(let key) = state.key, state.value.hasDocumentForm else { continue }
            values[key] = state.value
        }
        try container.encode(values, forKey: .ports)
        if let lastCompiledSource, lastCompiledSource != self.compilableSource
        {
            try container.encode(lastCompiledSource, forKey: .lastCompiledSource)
        }
        try container.encodeIfPresent(self.userName, forKey: .userName)
        try self.settings?.encode(to: encoder)
    }

    public required init(context:Context)
    {
        self.id = UUID()
        self.context = context

        self.reconcilePorts()
    }

    open class func initWithContext(context: Context) throws -> Node
    {
        self.init(context: context)
    }

    deinit
    {
        // Ports reference this node unowned; clear them before they can
        // dangle. Subclass ports are still alive here.
        for port in self.ports { port.node = nil }
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
    }

    // MARK: - Ports

    /// The port under `key`, if the node has one.
    public func port(forKey key: PortKey) -> Port?
    {
        Self.checkLookupOutsideExecute(key.description, on: self)
        return self.registry.port(forKey: key) ?? self.ports.first { $0.key == key }
    }

    /// The port under the node's own key `name`, cast to `T`, trapping when
    /// there is none or it is another type. For dynamic ports, from
    /// bindPorts() or from outside execution; a stored port is read through
    /// its property.
    public func port<T: Port>(named name: String, as type: T.Type = T.self) -> T
    {
        Self.checkLookupOutsideExecute(name, on: self)
        return self.registry.port(named: name) as! T
    }

    /// The port under the node's own key `name`, if there is one of type `T`.
    /// For dynamic ports, from bindPorts() or from outside execution.
    public func findPort<T: Port>(named name: String, as type: T.Type = T.self) -> T?
    {
        Self.checkLookupOutsideExecute(name, on: self)
        return self.registry.port(named: name) as? T
    }

    // MARK: - Port state hydration (declare-then-hydrate decode)

    /// The document's port state for the duration of decode; nil otherwise.
    /// Graph finalizes and clears it once node inits and their dynamic
    /// rebuilds are done, so ports added later in the node's life can never
    /// resurrect stale document state.
    private var portHydrationSession: PortHydrationSession?

    /// Registry keys from the document whose port state found no declared or
    /// rebuilt port to land on. Dropping that state is deliberate — the code
    /// owns the port set — but it is data loss, so Graph reports it after
    /// decode rather than discarding silently.
    internal var droppedPortStateKeys: [String] { self.portHydrationSession?.unconsumedKeys ?? [] }

    /// Whether the node is being decoded: its document's port state is still
    /// waiting for the ports it belongs to.
    internal var isDecoding: Bool { self.portHydrationSession != nil }

    // MARK: - Last compiled source

    /// For a node whose ports come from compiling a source (a script, a
    /// shader, an expression): the last source that compiled, which the node
    /// sets on each compile that succeeds. Saved as `lastCompiledSource` when
    /// it differs from `compilableSource`. A node whose source does not
    /// compile on open declares its ports from this one, read for its
    /// interface only and never run, so its document's wires and values hold
    /// until the source compiles again; it then becomes the last compiled one.
    /// Nil for every other node.
    public var lastCompiledSource: String?

    /// The source the node saves and compiles, where its document carries it,
    /// against which `lastCompiledSource` is saved only when it differs. Nil
    /// for a node without one, or whose source lives outside the document
    /// (a user's shader file).
    open var compilableSource: String? { nil }

    /// The source to read a fallback interface from: the last that compiled,
    /// else, when the document did not save one because it was the source
    /// itself, the source.
    internal var interfaceFallbackSource: String? { self.lastCompiledSource ?? self.compilableSource }

    /// Ends the decode-time hydration window, returning the registry keys
    /// whose state never found a port.
    internal func finalizePortHydration() -> [String]
    {
        let droppedKeys = self.droppedPortStateKeys
        self.portHydrationSession = nil
        return droppedKeys
    }

    // MARK: - Declared ports

    /// Brings the node's ports to declaredPorts(), putting `states` on them. A
    /// port kept under its key and type keeps its wires and value; a retyped
    /// one is made afresh under its runtime id and keeps the wires it can
    /// take; a removed one takes its wires with it, as graph edits. A node
    /// whose interface follows state it holds, a strategy, a source, a device,
    /// calls this once it has changed what declaredPorts() reads. Order is the
    /// declarations'.
    public final func reconcilePorts(applying states: [PortState] = [])
    {
        self.prepareDeclarations()
        let reconciliation = self.registry.reconcile(to: self.declaredPorts(),
                                                     applying: states,
                                                     owner: self,
                                                     hydrating: self.portHydrationSession,
                                                     fileReferenceBase: self.graph?.fileReferenceBaseURL)
        guard !reconciliation.isEmpty else { self.bindPorts(); return }

        let graph = self.graph

        // A retyped port keeps its key, so its address, so its publishing.
        for port in reconciliation.removed
        {
            graph?.setPublished(false, port: port)
            graph?.disconnectAll(fromRetired: port)
        }

        for (old, new) in reconciliation.retyped
        {
            graph?.rebindWires(from: old, to: new)
        }

        // A retired port is detached, so a transient view holding it cannot
        // reconnect it under the id its replacement now has.
        for port in reconciliation.removed + reconciliation.retyped.map(\.old)
        {
            port.node = nil
        }

        self.invalidatePortCaches()
        self.rebuildParameterGroup()
        self.bindPorts()

        if !reconciliation.retyped.isEmpty || !reconciliation.added.isEmpty { graph?.rebuildPublishedParameterGroup() }

        graph?.markConnectionsChanged()
        self.portsDidChange()
    }

    /// Runs before every reconcile, before declaredPorts(): resolve here any
    /// state the declarations and execute read, once, rather than per read.
    open func prepareDeclarations() { }

    /// Resolves references to the node's dynamic ports, those its declarations
    /// make from a strategy, a source, a device or records, once its ports
    /// have changed. The one place a node looks its ports up by key: execute
    /// reads the references this leaves, never the registry. A node whose
    /// ports are all stored properties does not override it. An override
    /// calls super, then assigns its own with findPort(named:).
    open func bindPorts() { }

    /// The parameters of the node's ports, in port order.
    private func rebuildParameterGroup()
    {
        let parameters = self.ports.compactMap(\.parameter)
        let current = self.parameterGroup.params
        guard parameters.count != current.count
                || zip(parameters, current).contains(where: { $0 !== $1 })
        else { return }

        self.parameterGroup.clear()
        self.parameterGroup.append(parameters)
    }

    /// The key the port is registered under: the declared name, where the
    /// port's own `name` is what it displays.
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
        retireDeferredResults()
        self.cachedInputPorts = nil
        self.cachedOutputPorts = nil
    }

    /// The node's ports its graph publishes.
    internal func publishedPorts() -> [Port]
    {
        self.graph?.publishedPorts(of: self) ?? []
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
        inputsAreDirty = false
        hasPendingExecutionCleanup = false

        // See https://github.com/Fabric-Project/Fabric/issues/41
        for port in ports
        {
            port.valueDidChange = false
        }
    }

    public func markDirty()
    {
        inputsAreDirty = true
    }

    open func updateConnectionTopology()
    {
    }

    // MARK: - Execution

    /// Overrides must call super after successful work. Stopped nodes remain enabled.
    /// A throwing callback leaves the state at its last completed transition.
    public private(set) var executionState: ExecutionState = .disabled

    open func startExecution(renderer:GraphRenderer) throws { executionState = .started }
    /// Cancel obsolete asynchronous publications without releasing submitted GPU resources.
    public func cancelPendingCompletions() { deferredResultsBinding?.invalidate() }

    open func stopExecution(renderer:GraphRenderer) throws {
        retireDeferredResults()
        executionState = .stopped
    }

    open func enableExecution(renderer:GraphRenderer) throws {
        executionState = .enabled
    }
    open func disableExecution(renderer:GraphRenderer) throws {
        retireDeferredResults()
        executionState = .disabled
    }

    /// Drops in-flight results and their storage. The renderer also calls this before stopping or
    /// disabling a node, so a subclass callback that throws before reaching super cannot skip it.
    internal func retireDeferredResults() {
        deferredResultsBinding?.retire()
        deferredResultsBinding = nil
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

    /// Override only; setSettings(_:) and init(context:settings:) call it.
    /// Brings the node, its ports included, to `settings`. A port whose
    /// registry key survives the change keeps its identity. A subclass takes
    /// its own type out of the existential, treats a value of any other type
    /// as no change, and calls super with the same value.
    ///
    /// Threads: called on the thread that edits the graph, which a host can
    /// keep off main, and on the render thread as a NumericTypeAgnosticNode
    /// specialises from execute(). A node whose settings reach main-thread
    /// state waits for main, so it is applied only from main. A change reaches
    /// an open settings view's model through settingsDidChange(), from the
    /// observer of the stored setting.
    open func apply(_ settings: any NodeSettings)
    {
    }

    /// The one way a node's settings change: from a settings view, the
    /// procedural API and undo. Brings the node to `settings` unless it holds
    /// them already; a value of another node's settings type is no change.
    public final func setSettings(_ settings: any NodeSettings)
    {
        guard let current = self.settings,
              type(of: current) == type(of: settings),
              !current.isEqual(to: settings)
        else { return }
        self.apply(settings)
        self.recordSettingsChange(from: current)
    }

    /// Override only; setSettings(_:) calls it after apply(_:), with the value
    /// the node held before. A subclass registers the undo step for the
    /// change here, not in apply(_:), which undo itself goes through.
    ///
    /// Temporary. It carries the one settings undo step that predates
    /// NodeSettings, StrategyNode's, until undo records every settings change
    /// around setSettings(_:); that rework removes this hook and its override.
    open func recordSettingsChange(from previous: any NodeSettings)
    {
    }

    // MARK: - Helpers

    func computeNodeSize() -> CGSize
    {
        let inputPorts = self.inputPorts()
        let outputPorts = self.outputPorts()
        
        // The ports' own names: a published name is the graph's, and a view
        // model reads this size on main while the graph may be edited elsewhere.
        let longestInputPortTitle = inputPorts.reduce(into: "") { maxTitle, port in
            maxTitle = (maxTitle.count > port.name.count) ? maxTitle : port.name
        }

        let longestOutputPortTitle = outputPorts.reduce(into: "") { maxTitle, port in
            maxTitle = (maxTitle.count > port.name.count) ? maxTitle : port.name
        }

        let horizontalMax = max(inputPorts.count, outputPorts.count)

        let height:CGFloat = 40 + (CGFloat(horizontalMax) * 25)

        // heuristic to choose width without calculating pixel values from rendering a string
        let width:CGFloat = 20.0 + (6.0 * CGFloat(longestOutputPortTitle.count + longestInputPortTitle.count))

        return CGSize(width: max(width, 150), height: max(height, 60) )
    }

}

/// A node the canvas can make from a dropped file, found by the file's content
/// type. `init(context:fileURL:)` makes the node from the file, which means one
/// of two things: see NodeMadeFromFile and NodeTakingFile.
///
/// Decoding restores a saved file reference but does not load it. Runtime
/// assets load during execution, so a missing or invalid external file cannot
/// prevent the node itself from deserializing.
public protocol NodeFileLoadingProtocol : Node
{
    init(context:Context, fileURL:URL) throws

    static var supportedContentTypes: [UTType] { get }
}

/// A node whose file is part of what it is, such as a shader effect: the
/// file decides its interface, and the node saves its path itself. Changing
/// the file with `setFileURL(_:)` is a change to the node's settings.
public protocol NodeMadeFromFile : NodeFileLoadingProtocol
{
    func setFileURL(_ url: URL)

    /// The document's folder is known or moved: a file the node could not
    /// find relative to it before may resolve now.
    func fileReferenceBaseDidChange(_ directoryURL: URL?)
}

public extension NodeMadeFromFile
{
    func fileReferenceBaseDidChange(_ directoryURL: URL?) { }
}

/// A node that takes a file through a file-picker inlet, such as an image or
/// movie loader. The file is that inlet's value: a dropped file becomes it.
public protocol NodeTakingFile : NodeFileLoadingProtocol
{
    var fileInlet: ParameterPort<String> { get }
}

public extension NodeTakingFile
{
    /// Puts `url` on the file inlet, relative to the document's folder where
    /// the node's graph has one.
    func takeFile(_ url: URL)
    {
        self.fileInlet.value = url.fileReference(relativeTo: self.graph?.fileReferenceBaseURL)
    }
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
              let url = URL(fileReference: reference, relativeTo: directoryURL)
        else { return }

        let relativeReference = url.fileReference(relativeTo: directoryURL)
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
