import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A node whose interface is its settings: a list of ports around one fixed
/// inlet, at the position `fixedIndex` gives.
private final class DeclaredInterfaceNode: Node
{
    struct Entry: Codable, Equatable, Sendable
    {
        var key: String
        var type: String
        var isInlet: Bool
    }

    struct Interface: NodeSettings
    {
        var entries: [Entry]
        var fixedIndex: Int
    }

    override class var name: String { "Declared Interface" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override class var nodeTimeMode: Node.TimeMode { .None }

    private(set) var interface = Interface(entries: [], fixedIndex: 0)

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("fixed", ParameterPort(parameter: FloatParameter("Fixed", 0, .inputfield, "A port every node of the class has"))),
        ]
    }

    required init(context: Context)
    {
        super.init(context: context)
    }

    init(context: Context, settings: Interface)
    {
        self.interface = settings
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }

    override var settings: (any NodeSettings)? { self.interface }

    override func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? Interface else { return }
        self.interface = settings
        super.apply(settings)
    }

    override func declaredPorts() -> [PortDeclaration]
    {
        var declarations = self.interface.entries.map { entry in
            PortDeclaration(registryKey: entry.key,
                            portType: PortType(rawValue: entry.type) ?? .Virtual,
                            kind: entry.isInlet ? .Inlet : .Outlet,
                            name: entry.key)
        }
        declarations.insert(contentsOf: super.declaredPorts(), at: min(max(0, self.interface.fixedIndex), declarations.count))
        return declarations
    }
}

/// A node's port set and order are a function of its declarations: equal
/// settings give equal ports, in equal order, under equal ids for surviving
/// keys, however the node got there.
@Suite("Declared Ports")
@MainActor
struct DeclaredPortsTests
{
    private typealias Entry = DeclaredInterfaceNode.Entry
    private typealias Interface = DeclaredInterfaceNode.Interface

    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(device: device,
                       sampleCount: 1,
                       colorPixelFormat: .bgra8Unorm,
                       depthPixelFormat: .depth32Float,
                       stencilPixelFormat: .invalid)
    }

    private func makeGraph(context: Context) -> (Graph, UndoManager)
    {
        let graph = Graph(context: context)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager
        return (graph, undoManager)
    }

    private func step(_ undoManager: UndoManager, _ edit: () -> Void)
    {
        undoManager.beginUndoGrouping()
        edit()
        undoManager.endUndoGrouping()
    }

    private func keys(of node: Node) -> [String]
    {
        node.ports.compactMap { node.registryKey(of: $0) }
    }

    private func inlet(_ key: String, _ type: PortType) -> Entry { Entry(key: key, type: type.rawValue, isInlet: true) }
    private func outlet(_ key: String, _ type: PortType) -> Entry { Entry(key: key, type: type.rawValue, isInlet: false) }

    @Test("A retyped port keeps its position, its id and the wires it can take")
    func retypedPortKeepsPositionAndID() throws
    {
        guard let context = makeContext() else { return }
        let (graph, undoManager) = makeGraph(context: context)
        let upstream = NumberBinaryOperator(context: context)
        let before = Interface(entries: [inlet("a", .Float), inlet("b", .Float), outlet("out", .Float)], fixedIndex: 1)
        let node = DeclaredInterfaceNode(context: context, settings: before)
        step(undoManager) { graph.addNode(upstream); graph.addNode(node) }
        #expect(keys(of: node) == ["a", "fixed", "b", "out"])

        let a = try #require(node.findPort(named: "a", as: Fabric.Port.self))
        step(undoManager) { graph.connect(upstream.outputNumber, to: a) }
        let wireID = try #require(a.connections.first?.id)

        var after = before
        after.entries[0] = inlet("a", .Virtual)
        step(undoManager) { graph.setSettings(after, on: node) }

        let retyped = try #require(node.findPort(named: "a", as: Fabric.Port.self))
        #expect(retyped !== a)
        #expect(retyped.id == a.id)
        #expect(retyped.portType == .Virtual)
        #expect(keys(of: node) == ["a", "fixed", "b", "out"])
        #expect(retyped.connections.map(\.id) == [wireID])
        #expect(a.node == nil)

        undoManager.undo()
        let restored = try #require(node.findPort(named: "a", as: Fabric.Port.self))
        #expect(restored.portType == .Float)
        #expect(restored.id == a.id)
        #expect(keys(of: node) == ["a", "fixed", "b", "out"])
        #expect(restored.connections.count == 1)
    }

    @Test("The registry reports a retyped port as replaced, not removed")
    func registryReportsReplacement() throws
    {
        guard let context = makeContext() else { return }
        let node = DeclaredInterfaceNode(context: context,
                                         settings: Interface(entries: [inlet("a", .Float), outlet("out", .Float)], fixedIndex: 0))
        let a = try #require(node.findPort(named: "a", as: Fabric.Port.self))
        let declarations = node.declaredPorts().map { declaration in
            declaration.registryKey == "a"
                ? PortDeclaration(registryKey: "a", portType: .Int, kind: .Inlet, name: "a")
                : declaration
        }

        let reconciliation = node.registry.reconcile(to: declarations, owner: node, hydrating: nil)
        #expect(reconciliation.removed.isEmpty)
        #expect(reconciliation.added.isEmpty)
        #expect(reconciliation.replaced.count == 1)
        #expect(reconciliation.replaced.first?.old === a)
        #expect(reconciliation.replaced.first?.new.id == a.id)
        #expect(!reconciliation.reordered)
    }

    @Test("Ports stand in declared order under the ids they had, through edits, undo and redo")
    func portsFollowDeclaredOrder() throws
    {
        guard let context = makeContext() else { return }
        let (graph, undoManager) = makeGraph(context: context)
        let node = DeclaredInterfaceNode(context: context,
                                         settings: Interface(entries: [inlet("x", .Float), inlet("y", .Float), outlet("result", .Float)], fixedIndex: 3))
        step(undoManager) { graph.addNode(node) }
        let ids = Dictionary(uniqueKeysWithValues: node.ports.compactMap { port in node.registryKey(of: port).map { ($0, port.id) } })

        step(undoManager) { graph.setSettings(Interface(entries: [inlet("x", .Float), outlet("result", .Float)], fixedIndex: 0), on: node) }
        #expect(keys(of: node) == ["fixed", "x", "result"])

        undoManager.undo()
        #expect(keys(of: node) == ["x", "y", "result", "fixed"])
        for port in node.ports
        {
            let key = try #require(node.registryKey(of: port))
            #expect(port.id == ids[key], "\(key) came back under another id")
        }
        #expect(node.parameterGroup.params.count == 3)

        undoManager.redo()
        #expect(keys(of: node) == ["fixed", "x", "result"])
        #expect(node.parameterGroup.params.map(\.label) == ["Fixed", "x"])
    }

    @Test("A port no longer declared takes its wires with it, and undo brings both back")
    func undeclaredPortTakesItsWires() throws
    {
        guard let context = makeContext() else { return }
        let (graph, undoManager) = makeGraph(context: context)
        let upstream = NumberBinaryOperator(context: context)
        let node = DeclaredInterfaceNode(context: context,
                                         settings: Interface(entries: [inlet("x", .Float), inlet("y", .Float)], fixedIndex: 2))
        step(undoManager) { graph.addNode(upstream); graph.addNode(node) }
        let y = try #require(node.findPort(named: "y", as: Fabric.Port.self))
        step(undoManager) { graph.connect(upstream.outputNumber, to: y) }

        step(undoManager) { graph.setSettings(Interface(entries: [inlet("x", .Float)], fixedIndex: 1), on: node) }
        #expect(graph.connections.isEmpty)
        #expect(node.findPort(named: "y", as: Fabric.Port.self) == nil)

        undoManager.undo()
        let restored = try #require(node.findPort(named: "y", as: Fabric.Port.self))
        #expect(restored.id == y.id)
        #expect(graph.connections.count == 1)
        #expect(restored.connections.count == 1)
    }

    @Test("A node made with settings has the ports of one brought to them")
    func freshNodeMatchesEditedNode() throws
    {
        guard let context = makeContext() else { return }
        let target = Interface(entries: [outlet("q", .Float), inlet("p", .Vector2), inlet("x", .Float)], fixedIndex: 2)
        let edited = DeclaredInterfaceNode(context: context,
                                           settings: Interface(entries: [inlet("x", .Float), inlet("p", .Float)], fixedIndex: 0))
        edited.apply(target)
        let fresh = DeclaredInterfaceNode(context: context, settings: target)
        #expect(keys(of: edited) == keys(of: fresh))
        #expect(edited.ports.map(\.portType) == fresh.ports.map(\.portType))
    }
}
