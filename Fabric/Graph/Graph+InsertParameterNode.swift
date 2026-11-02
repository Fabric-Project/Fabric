//
//  Graph+InsertParameterNode.swift
//  Fabric
//

import Foundation

extension Graph
{
    /// Insert a parameter node adjacent to the given port, connect it,
    /// and move the port's publishing to the parameter node's port; see
    /// transferPublishing(from:to:).
    ///
    /// For an **inlet**: the parameter node is placed to the left.
    /// Existing upstream connections move to the parameter node's input;
    /// the parameter node's outlet connects to the original inlet.
    ///
    /// For an **outlet**: the parameter node is placed to the right.
    /// Existing downstream connections move to the parameter node's outlet;
    /// the original outlet connects to the parameter node's input.
    public func insertParameterNode(for port: Port)
    {
        guard let sourceNode = port.node,
              sourceNode.graph === self,
              nodePort(forID: port.id) === port,
              let nodeClass = port.portType.parameterNodeClass
        else { return }

        let paramNode = nodeClass.init(context: self.context)

        let paramOutlet = paramNode.outputPorts().first
        let paramInlet  = paramNode.inputPorts().first

        guard let paramOutlet, let paramInlet else { return }

        self.undoManager?.beginUndoGrouping()
        defer {
            self.undoManager?.endUndoGrouping()
            self.undoManager?.setActionName("Insert Parameter Node")
        }

        switch port.kind
        {
        case .Inlet:

            // Align the parameter node's outlet with the source inlet
            GraphAutoLayout.positionToLeft(of: sourceNode, node: paramNode,
                                           alignPorts: (source: port, placed: paramOutlet))

            let existingConnections = port.connectedPorts

            self.addNode(paramNode)
            self.transferPublishing(from: port, to: paramInlet)
            paramInlet.restoreValue(from: port.snapshotValue())

            // Connecting the parameter outlet replaces the original inlet
            // connection after its upstream source has been preserved.
            for connectedPort in existingConnections {
                self.connect(connectedPort, to: paramInlet)
            }
            self.connect(paramOutlet, to: port)

        case .Outlet:

            // Align the parameter node's inlet with the source outlet
            GraphAutoLayout.positionToRight(of: sourceNode, node: paramNode,
                                            alignPorts: (source: port, placed: paramInlet))

            let existingConnections = port.connectedPorts

            self.addNode(paramNode)
            self.transferPublishing(from: port, to: paramOutlet)
            paramInlet.restoreValue(from: port.snapshotValue())

            // Preserve the original outlet first, then replace each downstream
            // inlet with the parameter node's outlet.
            self.connect(port, to: paramInlet)
            for connectedPort in existingConnections {
                self.connect(paramOutlet, to: connectedPort)
            }

        }
    }

    /// Moves `port`'s publishing to `replacement`, a port of the same kind and
    /// type. `replacement` may be published already; it keeps its own published
    /// name and wires, and takes `port`'s published name only if it has none.
    /// The sub graph node around this graph moves the wires on `port`'s proxy
    /// to `replacement`'s proxy where they displace nothing (see
    /// transferWires(from:to:)), then moves the proxy's publishing the same
    /// way, so the hand-over repeats at each level. Each level registers undo
    /// on its own graph's undo manager, so the chain is one undo action only
    /// where the levels share one.
    internal func transferPublishing(from port: Port, to replacement: Port)
    {
        guard port.published else { return }
        let replacementHasName = replacement.publishedName != nil
        self.setPublished(true, on: replacement)
        if !replacementHasName, let name = port.publishedName
        {
            self.setPublishedName(name, on: replacement)
        }
        self.ownerNode?.innerPort(port, handsOverTo: replacement)
        self.setPublished(false, on: port)
    }
}
