import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A node whose interface is a value it holds: a list of ports around one
/// fixed inlet, at the position `fixedIndex` gives.
private final class DeclaredInterfaceNode: Node
{
    struct Entry: Equatable
    {
        var key: String
        var type: PortType
        var isInlet: Bool
    }

    struct Interface: Equatable
    {
        var entries: [Entry]
        var fixedIndex: Int
    }

    override class var name: String { "Declared Interface" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override class var nodeTimeMode: Node.TimeMode { .None }

    var interface = Interface(entries: [], fixedIndex: 0)
    {
        didSet { self.reconcilePorts() }
    }

    var picker: ParameterPort<String>?
    {
        didSet { self.reconcilePorts() }
    }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("fixed", ParameterPort(parameter: FloatParameter("Fixed", 0.5, 0, 1, .slider, "A port every node of the class has"))),
        ]
    }

    required init(context: Context)
    {
        super.init(context: context)
    }

    init(context: Context, interface: Interface)
    {
        self.interface = interface
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }

    override func declaredPorts() -> [PortDeclaration]
    {
        var declarations = self.interface.entries.map { entry in
            PortDeclaration(key: entry.key, portType: entry.type, kind: entry.isInlet ? .Inlet : .Outlet, name: entry.key)
        }
        declarations.insert(contentsOf: super.declaredPorts(), at: min(max(0, self.interface.fixedIndex), declarations.count))
        return declarations + (picker.map { [PortDeclaration(key: "picker", port: $0)] } ?? [])
    }
}

/// A node's port set and order are a function of its declarations: equal
/// declarations give equal ports, in equal order, however the node got there.
@Suite("Declared Ports")
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

    private func keys(of node: Node) -> [String]
    {
        node.ports.map(\.key.description)
    }

    private func inlet(_ key: String, _ type: PortType) -> Entry { Entry(key: key, type: type, isInlet: true) }
    private func outlet(_ key: String, _ type: PortType) -> Entry { Entry(key: key, type: type, isInlet: false) }

    @Test("A retyped port keeps its position, its runtime id and the wires it can take")
    func retypedPortKeepsPositionAndWires() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let upstream = NumberBinaryOperator(context: context)
        let node = DeclaredInterfaceNode(context: context,
                                         interface: Interface(entries: [inlet("a", .Float), inlet("b", .Float), outlet("out", .Float)], fixedIndex: 1))
        graph.addNode(upstream)
        graph.addNode(node)
        #expect(keys(of: node) == ["a", "fixed", "b", "out"])

        let a = try #require(node.findPort(named: "a", as: Fabric.Port.self))
        let b = try #require(node.findPort(named: "b", as: Fabric.Port.self))
        graph.connect(upstream.outputNumber, to: a)
        graph.connect(upstream.outputNumber, to: b)
        let wireID = try #require(a.connections.first?.id)

        node.interface.entries[0] = inlet("a", .Virtual)
        node.interface.entries[1] = inlet("b", .Image)

        let retyped = try #require(node.findPort(named: "a", as: Fabric.Port.self))
        #expect(retyped !== a)
        #expect(retyped.id == a.id)
        #expect(retyped.portType == .Virtual)
        #expect(keys(of: node) == ["a", "fixed", "b", "out"])
        #expect(retyped.connections.map(\.id) == [wireID])
        #expect(a.node == nil)

        // An Image inlet cannot take a Float outlet's wire.
        let retypedB = try #require(node.findPort(named: "b", as: Fabric.Port.self))
        #expect(retypedB.connections.isEmpty)
        #expect(graph.connections.count == 1)
    }

    @Test("The registry reports a retyped port as retyped, not removed and added")
    func registryReportsRetype() throws
    {
        guard let context = makeContext() else { return }
        let node = DeclaredInterfaceNode(context: context,
                                         interface: Interface(entries: [inlet("a", .Float), outlet("out", .Float)], fixedIndex: 0))
        let a = try #require(node.findPort(named: "a", as: Fabric.Port.self))
        let declarations = node.declaredPorts().map { declaration in
            declaration.key == .own("a")
                ? PortDeclaration(key: "a", portType: .Int, kind: .Inlet, name: "a")
                : declaration
        }

        let reconciliation = node.registry.reconcile(to: declarations, applying: [], owner: node, hydrating: nil)
        #expect(reconciliation.removed.isEmpty)
        #expect(reconciliation.added.isEmpty)
        #expect(reconciliation.retyped.count == 1)
        #expect(reconciliation.retyped.first?.old === a)
        #expect(reconciliation.retyped.first?.new.id == a.id)
        #expect(!reconciliation.reordered)
    }

    @Test("Ports stand in declared order, a kept port keeping its object and value")
    func portsFollowDeclaredOrder() throws
    {
        guard let context = makeContext() else { return }
        let node = DeclaredInterfaceNode(context: context,
                                         interface: Interface(entries: [inlet("x", .Float), inlet("y", .Float), outlet("result", .Float)], fixedIndex: 3))
        let x = try #require(node.findPort(named: "x", as: ParameterPort<Float>.self))
        x.value = 7

        node.interface = Interface(entries: [inlet("x", .Float), outlet("result", .Float)], fixedIndex: 0)
        #expect(keys(of: node) == ["fixed", "x", "result"])
        #expect(node.findPort(named: "x", as: ParameterPort<Float>.self) === x)
        #expect(x.value == 7)
        #expect(node.parameterGroup.params.map(\.label) == ["Fixed", "x"])

        node.interface = Interface(entries: [outlet("result", .Float), inlet("y", .Float), inlet("x", .Float)], fixedIndex: 1)
        #expect(keys(of: node) == ["result", "fixed", "y", "x"])
        #expect(node.parameterGroup.params.map(\.label) == ["Fixed", "y", "x"])
    }

    @Test("A port no longer declared takes its wires with it, as an undoable disconnect")
    func undeclaredPortTakesItsWires() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager

        let upstream = NumberBinaryOperator(context: context)
        let node = DeclaredInterfaceNode(context: context,
                                         interface: Interface(entries: [inlet("x", .Float), inlet("y", .Float)], fixedIndex: 2))
        undoManager.beginUndoGrouping()
        graph.addNode(upstream)
        graph.addNode(node)
        let y = try #require(node.findPort(named: "y", as: Fabric.Port.self))
        graph.connect(upstream.outputNumber, to: y)
        undoManager.endUndoGrouping()

        undoManager.beginUndoGrouping()
        node.interface = Interface(entries: [inlet("x", .Float)], fixedIndex: 1)
        undoManager.endUndoGrouping()
        #expect(graph.connections.isEmpty)
        #expect(upstream.outputNumber.connections.isEmpty)
        #expect(node.findPort(named: "y", as: Fabric.Port.self) == nil)
        #expect(y.node == nil)
        #expect(undoManager.canUndo)
    }

    @Test("A node made with an interface has the ports of one brought to it")
    func freshNodeMatchesEditedNode() throws
    {
        guard let context = makeContext() else { return }
        let target = Interface(entries: [outlet("q", .Float), inlet("p", .Vector2), inlet("x", .Float)], fixedIndex: 2)
        let edited = DeclaredInterfaceNode(context: context,
                                           interface: Interface(entries: [inlet("x", .Float), inlet("p", .Float)], fixedIndex: 0))
        edited.interface = target
        let fresh = DeclaredInterfaceNode(context: context, interface: target)
        #expect(keys(of: edited) == keys(of: fresh))
        #expect(edited.ports.map(\.portType) == fresh.ports.map(\.portType))
        #expect(edited.ports.map(\.control) == fresh.ports.map(\.control))
    }

    @Test("A state goes onto the port at its key when it fits, and a slider clamps it")
    func statesApplyWhenTheyFit() throws
    {
        guard let context = makeContext() else { return }
        let node = DeclaredInterfaceNode(context: context,
                                         interface: Interface(entries: [inlet("x", .Float), inlet("n", .Int)], fixedIndex: 0))

        node.reconcilePorts(applying: [
            PortState(key: .own("x"), value: .Float(3)),
            PortState(key: .own("n"), value: .Float(2)),
            PortState(key: .own("fixed"), value: .Float(4)),
            PortState(key: .own("missing"), value: .Float(1)),
        ])

        #expect(node.findPort(named: "x", as: ParameterPort<Float>.self)?.value == 3)
        #expect(node.findPort(named: "n", as: ParameterPort<Int>.self)?.value == 0)
        #expect(node.findPort(named: "fixed", as: ParameterPort<Float>.self)?.value == 1)
    }

    @Test("A file picker's absolute reference inside the document folder comes back relative")
    func filePickerStateIsNormalised() throws
    {
        guard let context = makeContext() else { return }
        let folder = URL(fileURLWithPath: "/tmp/FabricDocument", isDirectory: true)
        let graph = Graph(context: context, fileReferenceBaseURL: folder)
        let node = DeclaredInterfaceNode(context: context, interface: Interface(entries: [], fixedIndex: 0))
        graph.addNode(node)
        node.picker = ParameterPort(parameter: StringParameter("File", "", .filepicker, "A file"))

        node.reconcilePorts(applying: [PortState(key: .own("picker"), value: .String(folder.appending(path: "a.png").absoluteString))])

        #expect(node.picker?.value == "a.png")
    }

    @Test("The registry's states are the values of its parameter inlets")
    func statesAreParameterInletValues() throws
    {
        guard let context = makeContext() else { return }
        let node = DeclaredInterfaceNode(context: context,
                                         interface: Interface(entries: [inlet("x", .Float), inlet("img", .Image), outlet("out", .Float)], fixedIndex: 0))
        node.findPort(named: "x", as: ParameterPort<Float>.self)?.value = 2
        node.findPort(named: "out", as: NodePort<Float>.self)?.send(9)

        #expect(node.registry.states() == [
            PortState(key: .own("fixed"), value: .Float(0.5)),
            PortState(key: .own("x"), value: .Float(2)),
        ])
    }

    @Test("A fresh port's declared control is the control the factory gives it")
    func freshControlMatchesFactory()
    {
        let types: [PortType] = [.Bool, .Int, .Float, .String, .Vector2, .Vector3, .Vector4, .Color, .Quaternion, .Transform,
                                 .Geometry, .Material, .Image, .Virtual, .NumericVirtual, .Array(portType: .Float), .Dictionary(valueType: .Int)]
        for type in types
        {
            for kind in [PortKind.Inlet, .Outlet]
            {
                let made = type.makeFreshPort(name: "p", kind: kind)
                #expect(type.freshPortControl(kind: kind) == made.parameter.map { PortControl($0.controlType) }, "\(type) \(kind)")
            }
        }
    }
}
