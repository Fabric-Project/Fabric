//
//  GraphAutoLayout.swift
//  Fabric
//
//  One-shot auto-layout for node graphs.
//
//  Places consumer nodes in the rightmost column, then spreads their
//  inputs leftward in columns by graph depth. Disconnected nodes are
//  placed above consumers in the rightmost column.
//
//  This is a standalone file to anticipate future extraction of layout
//  concerns from Graph.

import Foundation

// MARK: - Public API

extension Graph {

    /// Lay out all nodes in left-to-right columns based on graph topology.
    /// Consumer nodes (sinks) are placed at the right; their inputs fan
    /// out to the left. Wraps all moves in a single undo group.
    public func autoLayout() {
        let layout = GraphAutoLayout.compute(nodes: self.nodes)

        undoManager?.beginUndoGrouping()

        for (node, newOffset) in layout {
            let oldOffset = node.offset
            undoManager?.registerUndo(withTarget: node) { n in
                let redoOffset = n.offset
                self.undoManager?.registerUndo(withTarget: n) { $0.offset = redoOffset }
                n.offset = oldOffset
            }
            node.offset = newOffset
        }

        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Auto Layout")
    }
}

// MARK: - Layout Algorithm

enum GraphAutoLayout {

    // Layout constants
    static let columnSpacing: CGFloat = 75
    static let rowSpacing: CGFloat = 20
    static let nodeWidth: CGFloat = 150

    /// Compute target offsets for all nodes.
    /// Returns an array of (node, newOffset) pairs.
    static func compute(nodes: [Node]) -> [(Node, CGSize)] {
        guard !nodes.isEmpty else { return [] }

        // Step 1: Assign each node to a column (0 = rightmost)
        let columns = assignColumns(nodes: nodes)

        // Step 2: Order nodes within each column
        let orderedColumns = orderWithinColumns(columns: columns, allNodes: nodes)

        // Step 3: Compute positions
        return computePositions(orderedColumns: orderedColumns)
    }

    // MARK: - Column Assignment

    /// Assign each node to a column by walking upstream from consumer/leaf nodes.
    /// Column 0 is rightmost. Nodes that feed deeper paths get pushed to higher
    /// column numbers (further left). Disconnected nodes go to column 0.
    private static func assignColumns(nodes: [Node]) -> [Int: [Node]] {
        var columnForNode: [UUID: Int] = [:]

        // Seed: consumer nodes and nodes with no downstream connections at column 0
        let consumerNodes = nodes.filter { $0.nodeExecutionMode == .Consumer }
        let nodesWithNoOutputConnections = nodes.filter { $0.outputNodes.isEmpty }
        let rightmostNodes = Set(consumerNodes.map(\.id)).union(nodesWithNoOutputConnections.map(\.id))

        for node in nodes where rightmostNodes.contains(node.id) {
            columnForNode[node.id] = 0
        }

        // BFS: walk upstream, assigning each input to at least column+1.
        // If a node is already assigned a deeper column, keep the deeper one.
        // Re-enqueue when a node's column increases so its inputs propagate.
        // Cap at node count to handle feedback cycles gracefully.
        let maxColumn = nodes.count
        var queue: [Node] = nodes.filter { rightmostNodes.contains($0.id) }

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let currentColumn = columnForNode[current.id] ?? 0

            for input in current.inputNodes {
                let newColumn = currentColumn + 1
                guard newColumn <= maxColumn else { continue }  // Cycle guard
                if newColumn > (columnForNode[input.id] ?? 0) {
                    columnForNode[input.id] = newColumn
                    queue.append(input)
                }
            }
        }

        // Any node not yet assigned (isolated, no connections at all) goes to column 0
        for node in nodes where columnForNode[node.id] == nil {
            columnForNode[node.id] = 0
        }

        // Group nodes by column
        var columns: [Int: [Node]] = [:]
        for node in nodes {
            let col = columnForNode[node.id] ?? 0
            columns[col, default: []].append(node)
        }

        return columns
    }

    // MARK: - Vertical Ordering

    /// Order nodes within each column to minimise wire crossings.
    ///
    /// Processes columns right-to-left. For the rightmost column (col 0),
    /// disconnected nodes are placed above consumers, sorted by downstream
    /// port index. For subsequent columns, nodes are sorted by:
    ///   1. Row index of their downstream node in the previous column
    ///   2. Port index on that downstream node
    ///   3. Current Y offset (preserve user ordering as tiebreaker)
    private static func orderWithinColumns(columns: [Int: [Node]], allNodes: [Node]) -> [(column: Int, nodes: [Node])] {
        let maxColumn = columns.keys.max() ?? 0

        // Row index of each node within its column, set as we process right-to-left.
        var rowIndexForNode: [UUID: Int] = [:]

        var result: [(column: Int, nodes: [Node])] = []

        for col in 0...maxColumn {
            guard var nodesInColumn = columns[col] else { continue }

            if col == 0 {
                // Rightmost column: disconnected nodes above consumers,
                // each group sorted by downstream port index.
                let portKeys = downstreamPortIndexKeys(for: nodesInColumn)

                func compare(_ a: Node, _ b: Node) -> Bool {
                    switch (portKeys[a.id], portKeys[b.id]) {
                    case let (ak?, bk?):  return ak < bk
                    case (_?, nil):       return true
                    case (nil, _?):       return false
                    case (nil, nil):      return a.offset.height < b.offset.height
                    }
                }

                let consumers = nodesInColumn.filter { $0.nodeExecutionMode == .Consumer }
                let disconnected = nodesInColumn.filter { $0.nodeExecutionMode != .Consumer }
                nodesInColumn = disconnected.sorted(by: compare) + consumers.sorted(by: compare)
            } else {
                // Sort by downstream node's row in the already-ordered columns,
                // then by port index on that downstream node.
                nodesInColumn.sort { a, b in
                    let ak = downstreamSortKey(for: a, rowIndexForNode: rowIndexForNode)
                    let bk = downstreamSortKey(for: b, rowIndexForNode: rowIndexForNode)
                    if ak.row != bk.row { return ak.row < bk.row }
                    if ak.portIndex != bk.portIndex { return ak.portIndex < bk.portIndex }
                    return a.offset.height < b.offset.height
                }
            }

            for (index, node) in nodesInColumn.enumerated() {
                rowIndexForNode[node.id] = index
            }
            result.append((column: col, nodes: nodesInColumn))
        }

        return result
    }

    /// For each node, find the minimum port index where it connects on any
    /// downstream node. Used for column 0 sorting.
    private static func downstreamPortIndexKeys(for nodes: [Node]) -> [UUID: Int] {
        var keys: [UUID: Int] = [:]
        for node in nodes {
            var minPortIndex: Int? = nil
            for port in node.ports where port.kind == .Outlet {
                for connection in port.connections where connection.kind == .Inlet {
                    if let downstreamNode = connection.node,
                       let index = downstreamNode.ports.firstIndex(where: { $0.id == connection.id }) {
                        minPortIndex = min(minPortIndex ?? Int.max, index)
                    }
                }
            }
            if let idx = minPortIndex {
                keys[node.id] = idx
            }
        }
        return keys
    }

    /// Sort key: (downstream node's row in previous column, port index on that node).
    /// Unconstrained nodes sort last.
    private static func downstreamSortKey(for node: Node, rowIndexForNode: [UUID: Int]) -> (row: Int, portIndex: Int) {
        var bestRow = Int.max
        var bestPortIndex = Int.max

        for port in node.ports where port.kind == .Outlet {
            for connection in port.connections where connection.kind == .Inlet {
                if let downstreamNode = connection.node,
                   let downstreamRow = rowIndexForNode[downstreamNode.id] {
                    let portIndex = downstreamNode.ports.firstIndex(where: { $0.id == connection.id }) ?? Int.max
                    if (downstreamRow, portIndex) < (bestRow, bestPortIndex) {
                        bestRow = downstreamRow
                        bestPortIndex = portIndex
                    }
                }
            }
        }

        return (bestRow, bestPortIndex)
    }

    // MARK: - Position Computation

    /// Compute final offsets. Column 0 is at the right, higher columns go left.
    ///
    /// Each node tries to top-align with its topmost downstream connected node.
    /// If that would overlap with the node above, it stacks below instead.
    /// Column 0 (no downstream) centres around Y = 0.
    private static func computePositions(orderedColumns: [(column: Int, nodes: [Node])]) -> [(Node, CGSize)] {
        guard !orderedColumns.isEmpty else { return [] }

        var result: [(Node, CGSize)] = []
        var centreYForNode: [UUID: CGFloat] = [:]

        // Process columns right-to-left so downstream positions are known
        let sorted = orderedColumns.sorted { $0.column < $1.column }

        for (column, nodes) in sorted {
            let x = -CGFloat(column) * (columnSpacing + nodeWidth)

            if column == 0 {
                // Rightmost column: centre around 0
                let totalHeight = nodes.enumerated().reduce(CGFloat(0)) { acc, pair in
                    acc + pair.element.nodeSize.height + (pair.offset > 0 ? rowSpacing : 0)
                }
                var y = -totalHeight / 2
                for node in nodes {
                    let centreY = y + node.nodeSize.height / 2
                    result.append((node, CGSize(width: x, height: centreY)))
                    centreYForNode[node.id] = centreY
                    y += node.nodeSize.height + rowSpacing
                }
            } else {
                // Each node tries to top-align with its downstream target.
                // `bottomOfPrevious` ensures no overlap with the node above.
                var bottomOfPrevious: CGFloat = -.infinity

                for node in nodes {
                    let nodeHeight = node.nodeSize.height

                    // Desired top edge: align with downstream node's top edge
                    let desiredTop: CGFloat
                    if let downstreamTop = downstreamTopEdgeY(for: node, centreYForNode: centreYForNode) {
                        desiredTop = downstreamTop
                    } else {
                        // No downstream connection — stack below previous
                        desiredTop = bottomOfPrevious + rowSpacing
                    }

                    // Ensure we don't overlap with the node above
                    let actualTop = max(desiredTop, bottomOfPrevious + rowSpacing)
                    let centreY = actualTop + nodeHeight / 2

                    result.append((node, CGSize(width: x, height: centreY)))
                    centreYForNode[node.id] = centreY
                    bottomOfPrevious = actualTop + nodeHeight
                }
            }
        }

        return result
    }

    /// Find the top-edge Y of the downstream node that the given node connects to.
    private static func downstreamTopEdgeY(for node: Node, centreYForNode: [UUID: CGFloat]) -> CGFloat? {
        for outputNode in node.outputNodes {
            if let centreY = centreYForNode[outputNode.id] {
                return centreY - outputNode.nodeSize.height / 2
            }
        }
        return nil
    }

    // MARK: - Adjacency Placement

    /// Position `node` immediately left of `referenceNode`.
    static func positionToLeft(of referenceNode: Node, node: Node, gap: CGFloat = columnSpacing) {
        node.offset = CGSize(
            width: referenceNode.offset.width - node.nodeSize.width - gap,
            height: referenceNode.offset.height
        )
    }

    /// Position `node` immediately right of `referenceNode`.
    static func positionToRight(of referenceNode: Node, node: Node, gap: CGFloat = columnSpacing) {
        node.offset = CGSize(
            width: referenceNode.offset.width + referenceNode.nodeSize.width + gap,
            height: referenceNode.offset.height
        )
    }

    // MARK: - Parameter Node Mapping

    /// Returns the parameter node class for a given port type,
    /// or nil if no matching parameter node exists.
    static func parameterNodeClass(for portType: PortType) -> Node.Type?
    {
        switch portType
        {
        case .Float, .Int:  return NumberNode.self
        case .Bool:         return TrueNode.self
        case .String:       return StringNode.self
        case .Vector2:      return MakeVector2Node.self
        case .Vector3:      return MakeVector3Node.self
        case .Vector4:      return MakeVector4Node.self
        case .Color:        return MakeVector4Node.self
        case .Quaternion:   return MakeQuaternionNode.self
        case .Transform:    return IdentityTransformNode.self
        default:            return nil
        }
    }
}

// MARK: - Insert Parameter Node

extension Graph {

    /// Insert a parameter node adjacent to the given port, connect it,
    /// and transfer any published state.
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
              let nodeClass = GraphAutoLayout.parameterNodeClass(for: port.portType)
        else { return }

        let paramNode = nodeClass.init(context: self.context)

        let paramOutlet = paramNode.ports.first(where: { $0.kind == .Outlet })
        let paramInlet  = paramNode.ports.first(where: { $0.kind == .Inlet })

        switch port.kind
        {
        case .Inlet:
            guard let paramOutlet else { return }

            GraphAutoLayout.positionToLeft(of: sourceNode, node: paramNode)

            let existingConnections = Array(port.connections)

            // Transfer published state to the parameter node's input (or outlet if no input)
            if self.isPublished(port)
            {
                let savedName = self.publishedPorts[port.id] ?? ""
                self.publishedPorts.removeValue(forKey: port.id)

                let publishTarget = paramInlet ?? paramOutlet
                self.publishedPorts[publishTarget.id] = savedName
            }

            // Move existing upstream connections to the parameter node's input
            for connection in existingConnections { connection.disconnect(from: port) }
            if let paramInlet
            {
                for connection in existingConnections { connection.connect(to: paramInlet) }
            }

            self.addNode(paramNode)
            paramOutlet.connect(to: port)

        case .Outlet:
            guard let paramInlet else { return }

            GraphAutoLayout.positionToRight(of: sourceNode, node: paramNode)

            let existingConnections = Array(port.connections)

            // Transfer published state to the parameter node's outlet (or input if no outlet)
            if self.isPublished(port)
            {
                let savedName = self.publishedPorts[port.id] ?? ""
                self.publishedPorts.removeValue(forKey: port.id)

                let publishTarget = paramOutlet ?? paramInlet
                self.publishedPorts[publishTarget.id] = savedName
            }

            // Move existing downstream connections to the parameter node's outlet
            for connection in existingConnections { port.disconnect(from: connection) }
            if let paramOutlet
            {
                for connection in existingConnections { paramOutlet.connect(to: connection) }
            }

            self.addNode(paramNode)
            port.connect(to: paramInlet)
        }

        self.rebuildPublishedParameterGroup()
    }
}
