//
//  MatrixSwitchNode.swift
//  Fabric
//

import Metal
import Satin

/// N inputs, N outputs, cross-routed by an index map.
///
/// The map is a `Dictionary of Int` keyed by input index: `map["i"] = j` routes
/// Input i → Output j. A key's *absence* leaves that input unrouted — absence is
/// the routing equivalent of `nil`, which is why the map is a dictionary rather
/// than an `[Int]` with a sentinel (the port system has no optional element type).
/// Build/edit the map upstream with the Dictionary nodes: `Compose Dictionary`,
/// `Dictionary Set Value For Key` (add a route), `Dictionary Remove Key` (turn a
/// route off).
///
/// Because a node executes once per pass but each output may draw from a different
/// input, every routed source input is evaluated whenever any output is consumed;
/// unrouted inputs are never evaluated. An output with no source emits nothing —
/// it holds its previous value, so its consumers read a frozen value.
///
/// Unlike [[GateNode]], this node never declines a pull: an unrouted output's
/// consumer still runs (reading the frozen value) rather than being skipped as
/// Gate skips consumers of unselected branches. Neither node can starve its
/// control input — a declining node names its control inputs as keepAlive in
/// its PullResponse, so the renderer keeps a connected map/Index updating.
public final class MatrixSwitchNode: RoutingNodeBase
{
    override public class var name: String { "Matrix Switch" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Cross-routes N inputs to N outputs via an index map (Dictionary of Int) keyed by input index: map[\"i\"] = j sends Input i to Output j. Omit a key to leave that input unrouted. If two inputs target one output the lower index wins. An unrouted output emits nothing and holds its previous value, so its consumers see it frozen." }

    private static let indexMapPortName = "inputMap"

    private static func inputPortName(_ index: Int) -> String { "input\(index)" }

    private static func outputPortName(_ index: Int) -> String { "output\(index)" }

    public var inputMap: NodePort<[String: Int]> { port(named: Self.indexMapPortName) }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            (Self.indexMapPortName, NodePort<[String: Int]>(name: "Index Map",
                                                            kind: .Inlet,
                                                            description: "Input index → output index. Omit a key to leave that input unrouted.")),
        ]
    }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = PortType(rawValue: strategy) ?? .Virtual

        for index in 0..<routeCount
        {
            addOrReplaceDynamicPortPreservingIdentity(name: Self.inputPortName(index),
                                                      displayName: "Input \(index)",
                                                      portType: portType,
                                                      kind: .Inlet,
                                                      description: "Value for input \(index)")
        }

        for index in 0..<routeCount
        {
            addOrReplaceDynamicPortPreservingIdentity(name: Self.outputPortName(index),
                                                      displayName: "Output \(index)",
                                                      portType: portType,
                                                      kind: .Outlet,
                                                      description: "Value routed to output \(index)")
        }

        removeRoutingPortsAboveRouteCount(named: Self.inputPortName)
        removeRoutingPortsAboveRouteCount(named: Self.outputPortName)

        let orderedPortNames = [Self.indexMapPortName]
            + (0..<routeCount).map(Self.inputPortName)
            + (0..<routeCount).map(Self.outputPortName)
        applyPortOrder(orderedPortNames)

        inputMap.onValueChanged = { [weak self] in
            self?.updateConnectionTopology()
        }

        updateConnectionTopology()
    }

    public override func respondToPull(requestedOutputPort: Port?) -> Node.PullResponse
    {
        // A node executes once per pass, but each output may draw from a different
        // input and planning asks each node only once (the node is deduplicated
        // after its first visit). So any pull must schedule *every* routed source
        // input, not merely the one feeding the requested output.
        return .evaluate(pulling: [inputMap] + routedSourceInputPorts())
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let sources = sourceInputsByOutput()

        for outputIndex in 0..<routeCount
        {
            guard let sourceIndex = sources[outputIndex],
                  let sourceInput: Port = findPort(named: Self.inputPortName(sourceIndex)),
                  let outputPort: Port = findPort(named: Self.outputPortName(outputIndex))
            else { continue }

            outputPort.sendBoxed(sourceInput.snapshotValue(), force: true)
        }

    }

    public override func updateConnectionTopology()
    {
        let routedInputIDs = Set(routedSourceInputPorts().map(\.id))

        inputMap.setConnectionsActive(true)

        for index in 0..<routeCount
        {
            let inputPort: Port? = findPort(named: Self.inputPortName(index))
            inputPort?.setConnectionsActive(inputPort.map { routedInputIDs.contains($0.id) } ?? false)
        }
    }

    // MARK: - Routing

    private func currentMap() -> [String: Int]
    {
        inputMap.value ?? [:]
    }

    /// Output index → the lowest input index routed to it, built in one pass
    /// over the map (an output absent from the result is unrouted). Entries with
    /// a non-integer key or an out-of-range input/output are ignored, so an
    /// out-of-range value reads the same as an absent key.
    private func sourceInputsByOutput() -> [Int: Int]
    {
        var sources: [Int: Int] = [:]

        for (key, outputIndex) in currentMap()
        {
            guard let inputIndex = Int(key),
                  (0..<routeCount).contains(inputIndex),
                  (0..<routeCount).contains(outputIndex)
            else { continue }

            if let existing = sources[outputIndex], existing <= inputIndex { continue }
            sources[outputIndex] = inputIndex
        }

        return sources
    }

    /// Every input that actually feeds an output — collision losers and unrouted
    /// inputs excluded — ordered by the output they feed, deduplicated.
    private func routedSourceInputPorts() -> [Port]
    {
        let sources = sourceInputsByOutput()
        var seen = Set<Int>()
        var result: [Port] = []

        for outputIndex in 0..<routeCount
        {
            guard let sourceIndex = sources[outputIndex],
                  seen.insert(sourceIndex).inserted,
                  let port: Port = findPort(named: Self.inputPortName(sourceIndex))
            else { continue }

            result.append(port)
        }

        return result
    }
}
