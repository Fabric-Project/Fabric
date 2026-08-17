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


open class Node : Codable, Equatable, Identifiable, Hashable, Copyable
{
    // User interface name — the node's TYPE name (each subclass overrides).
    open class var name: String {  fatalError("\(String(describing:self)) Must implement name") }

    // Node-provided dynamic name, e.g. Math Expression shows its expression.
    // Override THIS (not the instance `name`) to give a node a self-generated
    // title; return nil for none. A user-supplied `userName` always wins over it.
    open var displayName: String? { nil }

    // User-supplied custom name (rename). Overrides any `displayName`.
    public var userName: String?

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

    public var name : String
    {
        let myType = type(of: self)
        return userName ?? displayName ?? myType.name
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

    // Method to register ports
    open class func registerPorts(context: Context) -> [(name: String, port: Port)] { [] }
    // All port serilization, adding, removing and key value access goes through the port registry
    private let registry = PortRegistry()

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

    /// Fires whenever the port list changes (addDynamicPort / removePort).
    internal let portsChangedSubject = PassthroughSubject<Void, Never>()

    /// Fires whenever the node's computed `name` changes (e.g. after a math
    /// expression re-parses). NodeViewModel subscribes and caches the result.
    internal let nameSubject = PassthroughSubject<Void, Never>()

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

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.offset = try container.decode(CGSize.self, forKey: .nodeOffset)
        self.userName = try container.decodeIfPresent(String.self, forKey: .userName)

        // Declare, then hydrate: the port set comes from the code — registerPorts
        // now, subclass rebuilds (strategy, route count, expression, shader) after
        // this initializer — and the document contributes only the state it owns,
        // applied per registry key as each port registers. Snapshot keys that
        // never match a declared or rebuilt port surface via
        // droppedPortStateKeys instead of resurrecting retired ports.
        let snaps = try container.decodeIfPresent([PortRegistry.Snapshot].self, forKey: .ports) ?? []
        self.portHydrationSession = PortHydrationSession(snapshots: snaps,
                                                         legacyKeys: Self.legacyPortStateKeys(forRegistryKey:))

        let declared = Self.registerPorts(context: context)

        for d in declared
        {
            self.portHydrationSession?.hydrate(d.port, registryKey: d.name)
            self.registry.register(d.port, name: d.name, owner: self)
        }

        for port in self.registry.all()
        {
            if let param = port.parameter
            {
                self.parameterGroup.append(param)
            }
        }
        self.synchronizeParameters()

        for port in self.ports
        {
            port.node = self
        }
    }

    open func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.id, forKey: .id)
        try container.encode(self.offset, forKey: .nodeOffset)
        try container.encode(self.registry.encode(), forKey: .ports)
        try container.encodeIfPresent(self.userName, forKey: .userName)
    }

    public required init(context:Context)
    {
        self.id = UUID()
        self.context = context

        let declared = Self.registerPorts(context: context)
        for (name, p) in declared {
            self.registry.register(p, name: name, owner: self)
        }

        for port in self.registry.all()
        {
            if let param = port.parameter
            {
                self.parameterGroup.append(param)
            }
        }

        self.synchronizeParameters()

        for port in self.ports
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
            port.disconnectAll()
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
    /// Graph finalizes and clears it once node inits and their dynamic
    /// rebuilds are done, so ports added later in the node's life can never
    /// resurrect stale document state.
    private var portHydrationSession: PortHydrationSession?

    /// Registry keys from the document whose port state found no declared or
    /// rebuilt port to land on. Dropping that state is deliberate — the code
    /// owns the port set — but it is data loss, so Graph reports it after
    /// decode rather than discarding silently.
    internal var droppedPortStateKeys: [String] { self.portHydrationSession?.unconsumedKeys ?? [] }

    /// Registers the document's remaining port state as ports in their own
    /// right — the one thing a document-owns-ports decode got right, kept for
    /// the case that needs it. A node whose source cannot rebuild its port set
    /// at decode time (an unparseable script, a shader that no longer compiles)
    /// would otherwise decode with none of the ports the document saved, taking
    /// every wire with them and making the loss permanent at the next save. The
    /// decoded instances already carry their saved identity, value and
    /// published state, so a later successful rebuild reconciles against them
    /// by name and keeps the wires whose names and types still agree.
    ///
    /// Only ever does anything mid-decode, and must run inside the node's init
    /// path so Graph still sees the keys as adopted rather than dropped.
    internal func adoptRemainingSnapshotPortsAsFallback()
    {
        guard let session = self.portHydrationSession else { return }

        for (registryKey, port) in session.drainPendingSnapshots()
        {
            self.addDynamicPort(port, name: registryKey)
        }
    }

    /// Ends the decode-time hydration window, returning the registry keys
    /// whose state never found a port.
    internal func finalizePortHydration() -> [String]
    {
        let droppedKeys = self.droppedPortStateKeys
        self.portHydrationSession = nil
        return droppedKeys
    }

    /// Legacy registry keys whose document state should hydrate the port now
    /// registered under `registryKey`. Nodes that renamed dynamic ports
    /// override this so documents saved under the old names keep port identity
    /// (and therefore wires) across the rename.
    open class func legacyPortStateKeys(forRegistryKey registryKey: String) -> [String] { [] }

    // Dynamic add/remove (kept by serialization automatically)
    public func addDynamicPort(_ p: Port, name:String? = nil)
    {
        // Dynamic ports created after decode (rebuildPorts and friends) adopt
        // their persisted state here, before the registry indexes their id.
        self.portHydrationSession?.hydrate(p, registryKey: name ?? p.name)

        self.registry.addDynamic(p, owner: self, name:name)
        self.invalidatePortCaches()
        if let param = p.parameter
        {
            self.parameterGroup.append(param)
        }

        self.graph?.markConnectionsChanged()
        self.portsChangedSubject.send()
    }

    public func removePort(_ p: Port)
    {
        self.portHydrationSession?.relinquish(p)

        self.registry.remove(p)
        self.invalidatePortCaches()
        if let param = p.parameter
        {
            self.parameterGroup.remove(param)
        }

        self.graph?.markConnectionsChanged()
        self.portsChangedSubject.send()
    }

    internal func replaceParameterOfPort(_ port:Port, withParam param:(any Parameter))
    {
        // Remove existing param from group
        if let existingParam = port.parameter
        {
            self.parameterGroup.remove(existingParam)
        }

        // Add new param to group
        self.parameterGroup.append(param)

        port.parameter = param
    }

    internal func reorderPorts(_ reordered: [Port])
    {
        self.registry.reorder(reordered)
        self.invalidatePortCaches()
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

    open func startExecution(renderer:GraphRenderer) throws { }
    open func stopExecution(renderer:GraphRenderer) throws { }

    open func enableExecution(renderer:GraphRenderer) throws { }
    open func disableExecution(renderer:GraphRenderer) throws { }

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

    // MARK: - Helpers

    func computeNodeSize() -> CGSize
    {
        let horizontalInputsCount = self.ports.filter { $0.direction == .Horizontal && $0.kind != .Inlet  }.count
        let horizontalOutputsCount = self.ports.filter { $0.direction == .Horizontal && $0.kind != .Outlet  }.count

        let verticalInputsCount = self.ports.filter { $0.direction == .Vertical && $0.kind != .Inlet  }.count
        let verticalOutputsCount = self.ports.filter { $0.direction == .Vertical && $0.kind != .Outlet  }.count

        let horizontalMax = max(horizontalInputsCount, horizontalOutputsCount)
        let verticalMax = max(verticalInputsCount, verticalOutputsCount)

        let height:CGFloat = 40 + (CGFloat(horizontalMax) * 25)
        let width:CGFloat = 20 + (CGFloat(verticalMax) * 25)

        return CGSize(width: max(width, 150), height: max(height, 60) )
    }

    // Mark - Private helper

    private func parametersGroupToPorts(_ parameters:[(any Parameter)]) -> [Port]
    {
        return parameters.compactMap( {
            self.parameterToPort(parameter:$0) })
    }

    private func parameterToPort(parameter:(any Parameter)) -> Port?
    {
        switch parameter.type
        {

        case .generic:

            if let genericParam = parameter as? GenericParameter<Float>
            {
                return ParameterPort(parameter: genericParam)
            }

            if let genericParam = parameter as? GenericParameter<simd_float3>
            {
                return ParameterPort(parameter: genericParam)
            }

            if let genericParam = parameter as? GenericParameter<simd_float4>
            {
                return ParameterPort(parameter: genericParam)
            }

            if let genericParam = parameter as? GenericParameter<simd_quatf>
            {
                return ParameterPort(parameter: genericParam)
            }

        case .string:

            if let genericParam = parameter as? StringParameter
            {
                return ParameterPort(parameter: genericParam)
            }

        case .bool:

            if let genericParam = parameter as? BoolParameter
            {
                return ParameterPort(parameter: genericParam)
            }

        case .float:

            if let genericParam = parameter as? FloatParameter
            {
                return ParameterPort(parameter: genericParam)
            }

            else if let genericParam = parameter as? GenericParameter<Float>
            {
                return ParameterPort(parameter: genericParam)
            }

        case .float2:
            if let genericParam = parameter as? Float2Parameter
            {
                return ParameterPort(parameter: genericParam)
            }

        case .float3:
            if let genericParam = parameter as? Float3Parameter
            {
                return ParameterPort(parameter: genericParam)
            }

        case .float4:
            if let genericParam = parameter as? Float4Parameter
            {
                return ParameterPort(parameter: genericParam)
            }

            else if let genericParam = parameter as? GenericParameter<simd_float4>
            {
                return ParameterPort(parameter: genericParam)
            }

        case .float4x4:
            if let genericParam = parameter as? Float4x4Parameter
            {
                return ParameterPort(parameter: genericParam)
            }

        default:
            return nil

        }

        return nil
    }
}

/// Nodes that are constructed from a file (e.g. Metal shader effect nodes).
/// Nodes that accept a user-dropped file via a file-path parameter port.
/// Conformers declare which UTTypes they handle and receive the URL after
/// normal construction via ``setFileURL(_:)``.
public protocol NodeFileLoadingProtocol : Node
{
    init(context:Context, fileURL:URL) throws
    func setFileURL(_ url: URL)

    static var supportedContentTypes: [UTType] { get }
}

public extension NodeFileLoadingProtocol
{
    /// A file that ships inside the package bundle is persisted by its trailing
    /// path components, not its URL: the bundle sits somewhere different on
    /// every machine and in every build, so an absolute path would bind the
    /// document to the machine that wrote it.
    static func bundleRelativeResourcePath(for url: URL) -> String
    {
        url.pathComponents.suffix(3).joined(separator: "/")
    }

    static func resolveBundleResource(path: String) -> URL?
    {
        Bundle.module.resourceURL?.appending(path: path)
    }
}
