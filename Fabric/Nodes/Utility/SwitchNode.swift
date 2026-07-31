//
//  SwitchNode.swift
//  Fabric
//

import Metal

public final class SwitchNode: RoutingNode
{
    override public class var name: String { "Switch" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Selects one input to route through. Inverse of Gate. Only the selected input branch is evaluated." }

    private static let outputPortName = "output"

    private static func inputPortName(_ index: Int) -> String
    {
        "input\(index)"
    }

    public var output: Port { port(named: Self.outputPortName) }

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
                                                      description: "Value for route \(index)")
        }

        removeRoutingPortsAboveRouteCount(named: Self.inputPortName)

        addOrReplaceDynamicPortPreservingIdentity(name: Self.outputPortName,
                                                  displayName: "Output",
                                                  portType: portType,
                                                  kind: .Outlet,
                                                  description: "Selected input value")

        let orderedPortNames = ["inputIndex"] + (0..<routeCount).map(Self.inputPortName) + [Self.outputPortName]
        applyPortOrder(orderedPortNames)
    }

    public override func respondToPull(requestedOutputPort: Port?) -> Node.PullResponse
    {
        let routeIndex = selectedRouteIndex()

        guard let selectedInput: Port = findPort(named: Self.inputPortName(routeIndex))
        else { return .evaluate(pulling: [inputIndex]) }

        return .evaluate(pulling: [inputIndex, selectedInput])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let selectedInput: Port = findPort(named: Self.inputPortName(selectedRouteIndex()))
        else { return }

        output.sendBoxed(selectedInput.snapshotValue(), force: true)
    }

    public override func updateConnectionTopology()
    {
        inputIndex.setConnectionsActive(true)

        for index in 0..<routeCount
        {
            let inputPort: Port? = findPort(named: Self.inputPortName(index))
            inputPort?.setConnectionsActive(index == selectedRouteIndex())
        }
    }
}
