import Testing
import Foundation
import Metal
import Satin
@testable import Fabric

private final class PlanningTestNode: Node {
    override class var name: String { "Planning Test" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Exercises graph pull planning." }

    var selectedInput = 0
    var declines = false
    var keepControlAlive = false
    var onPull: (() -> Void)?
    var first: NodePort<Float> { port(named: "first") }
    var second: NodePort<Float> { port(named: "second") }
    var output: NodePort<Float> { port(named: "output") }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)] {
        super.registerPorts(context: context) + [
            ("first", NodePort<Float>(name: "First", kind: .Inlet)),
            ("second", NodePort<Float>(name: "Second", kind: .Inlet)),
            ("output", NodePort<Float>(name: "Output", kind: .Outlet)),
        ]
    }

    override func respondToPull(requestedOutputPort: Fabric.Port?) -> PullResponse {
        onPull?()
        if declines { return .declined(keepAlive: keepControlAlive ? [second] : []) }
        return .evaluate(pulling: selectedInput == 0 ? [first] : [second])
    }
}

@Suite("Dense graph execution planning")
struct GraphExecutionPlanningTests {
    private func context() throws -> Context {
        Context(device: try #require(MTLCreateSystemDefaultDevice()), sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    @Test("Forced nodes are dependency ordered and scheduled nodes are excluded")
    func forcedDependencies() throws {
        let context = try context()
        let graph = Graph(context: context)
        let source = PlanningTestNode(context: context)
        let middle = PlanningTestNode(context: context)
        let sink = PlanningTestNode(context: context)
        for node in [sink, middle, source] { graph.addNode(node) }
        graph.connect(source.output, to: middle.first)
        graph.connect(middle.output, to: sink.first)
        let planner = GraphExecutionPlanner(nodes: graph.nodes)
        let result = planner.plan(roots: [], alreadyScheduledNodes: [source], forcedNodes: [sink, middle, source])
        #expect(result.map(\.id) == [middle.id, sink.id])
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [source.id, middle.id, sink.id])
    }

    @Test("Pull decisions are reevaluated between forced passes")
    func dynamicRouting() throws {
        let context = try context()
        let graph = Graph(context: context)
        let left = PlanningTestNode(context: context)
        let right = PlanningTestNode(context: context)
        let route = PlanningTestNode(context: context)
        for node in [route, left, right] { graph.addNode(node) }
        graph.connect(left.output, to: route.first)
        graph.connect(right.output, to: route.second)
        let planner = GraphExecutionPlanner(nodes: graph.nodes)
        #expect(planner.plan(roots: [], forcedNodes: [route]).map(\.id) == [left.id, route.id])
        route.selectedInput = 1
        #expect(planner.plan(roots: [], forcedNodes: [route]).map(\.id) == [right.id, route.id])
    }

    @Test("Declined forced nodes still run after their keep-alive dependencies")
    func declinedAndKeepAlive() throws {
        let context = try context()
        let graph = Graph(context: context)
        let control = PlanningTestNode(context: context)
        let route = PlanningTestNode(context: context)
        graph.addNode(route)
        graph.addNode(control)
        graph.connect(control.output, to: route.second)
        route.declines = true
        route.keepControlAlive = true
        let planner = GraphExecutionPlanner(nodes: graph.nodes)
        #expect(planner.plan(roots: [(route, route.output)]).map(\.id) == [control.id])
        #expect(planner.plan(roots: [], forcedNodes: [route]).map(\.id) == [control.id, route.id])
    }

    @Test("Unknown forced nodes get independent slots without replacing existing entries")
    func foreignNodes() throws {
        let context = try context()
        let first = PlanningTestNode(context: context)
        let second = PlanningTestNode(context: context)
        let planner = GraphExecutionPlanner(nodes: [first])
        #expect(planner.plan(roots: [], forcedNodes: [second, first]).map(\.id) == [second.id, first.id])
        #expect(planner.plan(roots: [], forcedNodes: [first, second]).map(\.id) == [first.id, second.id])
    }

    @Test("One-off forced nodes outside the topology are not retained by planning scratch")
    func foreignNodeLifetime() throws {
        let context = try context()
        let planner = GraphExecutionPlanner(nodes: [])
        var forced: PlanningTestNode? = PlanningTestNode(context: context)
        weak var retired = forced
        _ = planner.plan(roots: [], forcedNodes: [try #require(forced)])
        forced = nil
        #expect(retired == nil)
    }

    @Test("Renderers with different layouts cannot reuse the wrong node slot")
    func independentLayouts() throws {
        let context = try context()
        let first = PlanningTestNode(context: context)
        let second = PlanningTestNode(context: context)
        let forward = GraphExecutionPlanner(nodes: [first, second])
        let reverse = GraphExecutionPlanner(nodes: [second, first])
        for _ in 0..<3 {
            #expect(forward.plan(roots: [], alreadyScheduledNodes: [first], forcedNodes: [second, first]).map(\.id) == [second.id])
            #expect(reverse.plan(roots: [], alreadyScheduledNodes: [second], forcedNodes: [first, second]).map(\.id) == [first.id])
        }
    }

    @Test("New topology replaces old slots and old planning ownership can retire")
    func replacementLayout() throws {
        let context = try context()
        var removed: PlanningTestNode? = PlanningTestNode(context: context)
        weak var retired = removed
        let survivor = PlanningTestNode(context: context)
        var oldPlanner: GraphExecutionPlanner? = GraphExecutionPlanner(nodes: [try #require(removed), survivor])
        _ = oldPlanner?.plan(roots: [], forcedNodes: [survivor])
        let replacement = GraphExecutionPlanner(nodes: [survivor])
        removed = nil
        oldPlanner = nil
        #expect(retired == nil)
        #expect(replacement.plan(roots: [], forcedNodes: [survivor]).map(\.id) == [survivor.id])
    }

    @Test("A renderer releases deleted nodes when its topology cache is rebuilt")
    func rendererRetiresDeletedNode() throws {
        let harness = try #require(GraphExecutionTestHarness(renderWidth: 8, renderHeight: 8))
        let graph = Graph(context: harness.context)
        var removed: PlanningTestNode? = PlanningTestNode(context: harness.context)
        weak var retired = removed
        graph.addNode(try #require(removed))
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try harness.execute(graph, frameNumber: 0)
        graph.delete(node: try #require(removed))
        removed = nil
        try harness.execute(graph, frameNumber: 1)
        #expect(retired == nil)
        try renderer.stopExecution()
    }

    @Test("Cycles terminate and each reachable node appears once")
    func cycleGuard() throws {
        let context = try context()
        let graph = Graph(context: context)
        let first = PlanningTestNode(context: context)
        let second = PlanningTestNode(context: context)
        graph.addNode(first)
        graph.addNode(second)
        graph.connect(first.output, to: second.first)
        graph.connect(second.output, to: first.first)
        let planner = GraphExecutionPlanner(nodes: graph.nodes)
        #expect(planner.plan(roots: [], forcedNodes: [first, second]).map(\.id) == [second.id, first.id])
    }

    @Test("Distinct decoded instances with the same saved UUID share planning state")
    func savedIdentity() throws {
        let context = try context()
        let first = PlanningTestNode(context: context)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let alias = try decoder.decode(PlanningTestNode.self, from: JSONEncoder().encode(first))
        let planner = GraphExecutionPlanner(nodes: [first, alias])
        #expect(planner.plan(roots: [], forcedNodes: [first, alias]).count == 1)
        #expect(planner.plan(roots: [], alreadyScheduledNodes: [first], forcedNodes: [alias]).isEmpty)
    }

    // Multiple inlet connections can appear in restored graphs and custom port
    // arrangements. Wire them directly here because Graph.connect intentionally
    // replaces an inlet's previous connection in the ordinary editing API.
    @discardableResult
    private func connectForPlanning(_ output: Fabric.Port, to input: Fabric.Port,
                                    active: Bool = true) -> Connection {
        let connection = Connection(outletPortID: output.id, inletPortID: input.id, active: active)
        connection.outletPortReference = output
        connection.inletPortReference = input
        output.connections.append(connection)
        input.connections.append(connection)
        return connection
    }

    @Test("Single connections respect activity and disconnection between passes")
    func singleConnectionChanges() throws {
        let context = try context()
        let graph = Graph(context: context)
        let source = PlanningTestNode(context: context)
        let sink = PlanningTestNode(context: context)
        graph.addNode(source)
        graph.addNode(sink)
        let connection = try #require(graph.connect(source.output, to: sink.first))
        let planner = GraphExecutionPlanner(nodes: graph.nodes)
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [source.id, sink.id])
        connection.active = false
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [sink.id])
        connection.active = true
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [source.id, sink.id])
        graph.disconnect(connection)
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [sink.id])
    }

    @Test("Connection activity is checked when visited after upstream hooks")
    func activityCheckedWhenVisited() throws {
        let context = try context()
        let first = PlanningTestNode(context: context)
        let second = PlanningTestNode(context: context)
        let inactive = PlanningTestNode(context: context)
        let sink = PlanningTestNode(context: context)
        connectForPlanning(first.output, to: sink.first)
        let secondConnection = connectForPlanning(second.output, to: sink.first)
        let inactiveConnection = connectForPlanning(inactive.output, to: sink.first, active: false)
        first.onPull = {
            secondConnection.active = false
            inactiveConnection.active = true
        }
        let planner = GraphExecutionPlanner(nodes: [first, second, inactive, sink])
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [first.id, inactive.id, sink.id])
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [first.id, inactive.id, sink.id])
    }

    @Test("Removing connections during an upstream pull does not invalidate traversal")
    func removalDuringPull() throws {
        let context = try context()
        let first = PlanningTestNode(context: context)
        let second = PlanningTestNode(context: context)
        let sink = PlanningTestNode(context: context)
        connectForPlanning(first.output, to: sink.first)
        connectForPlanning(second.output, to: sink.first)
        first.onPull = { [weak sink] in sink?.first.connections.removeAll() }
        let planner = GraphExecutionPlanner(nodes: [first, second, sink])
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [first.id, second.id, sink.id])
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [sink.id])
    }

    @Test("Multiple connections preserve nested dependency order across repeated passes")
    func nestedConnectionSnapshots() throws {
        let context = try context()
        let leaves = (0..<4).map { _ in PlanningTestNode(context: context) }
        let middle = PlanningTestNode(context: context)
        let sink = PlanningTestNode(context: context)
        for leaf in leaves.prefix(3) { connectForPlanning(leaf.output, to: middle.first) }
        connectForPlanning(middle.output, to: sink.first)
        connectForPlanning(leaves[3].output, to: sink.first)
        let planner = GraphExecutionPlanner(nodes: leaves + [middle, sink])
        let expected = leaves.prefix(3).map(\.id) + [middle.id, leaves[3].id, sink.id]
        for _ in 0..<3 {
            let result = planner.plan(roots: [], forcedNodes: [sink]).map(\.id)
            #expect(result == expected)
        }
    }

    @Test("Connection traversal does not retain detached outlets")
    func connectionTraversalLifetime() throws {
        let context = try context()
        let sink = PlanningTestNode(context: context)
        var detached: NodePort<Float>? = NodePort<Float>(name: "Detached", kind: .Outlet)
        weak var retired = detached
        let other = NodePort<Float>(name: "Other", kind: .Outlet)
        connectForPlanning(try #require(detached), to: sink.first)
        connectForPlanning(other, to: sink.first)
        let planner = GraphExecutionPlanner(nodes: [sink])
        _ = planner.plan(roots: [], forcedNodes: [sink])
        detached = nil
        #expect(retired == nil)
    }

    @Test("Reentrant pull hooks cannot overwrite an outer planning pass")
    func reentrantPlanning() throws {
        let context = try context()
        let source = PlanningTestNode(context: context)
        let sink = PlanningTestNode(context: context)
        let graph = Graph(context: context)
        graph.addNode(source)
        graph.addNode(sink)
        graph.connect(source.output, to: sink.first)
        let planner = GraphExecutionPlanner(nodes: graph.nodes)
        var nestedResult: [UUID] = []
        defer { sink.onPull = nil }
        sink.onPull = {
            nestedResult = planner.plan(roots: [], forcedNodes: [source]).map(\.id)
        }
        #expect(planner.plan(roots: [], forcedNodes: [sink]).map(\.id) == [source.id, sink.id])
        #expect(nestedResult == [source.id])
    }
}
