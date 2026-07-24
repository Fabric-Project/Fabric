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
/// control input — when a requested output declines, the renderer still pulls
/// the node itself so a connected map/Index keeps updating.
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

        removeRoutingPorts { portName in
            for prefix in ["Input ", "Output "]
            {
                if portName.hasPrefix(prefix),
                   let index = Int(portName.dropFirst(prefix.count))
                {
                    return index >= routeCount
                }
            }
            return false
        }

        let orderedPortNames = [Self.indexMapPortName]
            + (0..<routeCount).map(Self.inputPortName)
            + (0..<routeCount).map(Self.outputPortName)
        applyPortOrder(orderedPortNames)
    }

    public override func activeInputPorts(requestedOutputPort: Port?) -> [Port]
    {
        // A node executes once per pass, but each output may draw from a different
        // input and planning queries activeInputPorts only once (the node is
        // deduplicated after its first visit). So any pull must schedule *every*
        // routed source input, not merely the one feeding the requested output.
        [inputMap] + routedSourceInputPorts()
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        for outputIndex in 0..<routeCount
        {
            guard let sourceIndex = sourceInputIndex(forOutput: outputIndex),
                  let sourceInput: Port = findPort(named: Self.inputPortName(sourceIndex)),
                  let outputPort: Port = findPort(named: Self.outputPortName(outputIndex))
            else { continue }

            outputPort.sendBoxed(sourceInput.snapshotValue(), force: true)
        }
    }

    // MARK: - Routing

    private func currentMap() -> [String: Int]
    {
        inputMap.value ?? [:]
    }

    /// The lowest input index routed to `outputIndex`, or nil when no input targets
    /// it (the output is unrouted). Map entries whose target is out of range are
    /// ignored, so an out-of-range value reads the same as an absent key.
    private func sourceInputIndex(forOutput outputIndex: Int) -> Int?
    {
        let map = currentMap()
        for inputIndex in 0..<routeCount
        {
            if map[String(inputIndex)] == outputIndex
            {
                return inputIndex
            }
        }
        return nil
    }

    /// Every input that actually feeds an output — collision losers and unrouted
    /// inputs excluded — in ascending order, deduplicated.
    private func routedSourceInputPorts() -> [Port]
    {
        var seen = Set<Int>()
        var result: [Port] = []
        for outputIndex in 0..<routeCount
        {
            guard let sourceIndex = sourceInputIndex(forOutput: outputIndex),
                  seen.insert(sourceIndex).inserted,
                  let port: Port = findPort(named: Self.inputPortName(sourceIndex))
            else { continue }

            result.append(port)
        }
        return result
    }
}
