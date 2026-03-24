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
    static let columnSpacing: CGFloat = 150
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
    /// Sort key: the minimum port index where this node connects on its
    /// downstream node. Nodes feeding earlier (higher) ports sort first.
    /// For the rightmost column, disconnected nodes are placed above consumers.
    private static func orderWithinColumns(columns: [Int: [Node]], allNodes: [Node]) -> [(column: Int, nodes: [Node])] {
        let maxColumn = columns.keys.max() ?? 0

        // For each node, find the lowest port index it connects to on any
        // downstream node. Lower index → higher on screen.
        var sortKey: [UUID: Int] = [:]

        for node in allNodes {
            var minPortIndex = Int.max
            // Check each outlet port for connections to downstream inlet ports
            for port in node.ports where port.kind == .Outlet {
                for connection in port.connections where connection.kind == .Inlet {
                    if let downstreamNode = connection.node {
                        let index = downstreamNode.ports.firstIndex(where: { $0.id == connection.id }) ?? Int.max
                        minPortIndex = min(minPortIndex, index)
                    }
                }
            }
            sortKey[node.id] = minPortIndex == Int.max ? 0 : minPortIndex
        }

        // Sort and build output
        var result: [(column: Int, nodes: [Node])] = []

        for col in 0...maxColumn {
            guard var nodesInColumn = columns[col] else { continue }

            if col == 0 {
                // Rightmost column: disconnected nodes above consumers
                let consumers = nodesInColumn.filter { $0.nodeExecutionMode == .Consumer }
                let disconnected = nodesInColumn.filter { $0.nodeExecutionMode != .Consumer }

                let sortedDisconnected = disconnected.sorted { (sortKey[$0.id] ?? 0) < (sortKey[$1.id] ?? 0) }
                let sortedConsumers = consumers.sorted { (sortKey[$0.id] ?? 0) < (sortKey[$1.id] ?? 0) }

                nodesInColumn = sortedDisconnected + sortedConsumers
            } else {
                nodesInColumn.sort { (sortKey[$0.id] ?? 0) < (sortKey[$1.id] ?? 0) }
            }

            result.append((column: col, nodes: nodesInColumn))
        }

        return result
    }

    // MARK: - Position Computation

    /// Compute final offsets. Column 0 is at the right, higher columns go left.
    /// Nodes within a column are stacked vertically with spacing.
    private static func computePositions(orderedColumns: [(column: Int, nodes: [Node])]) -> [(Node, CGSize)] {
        guard !orderedColumns.isEmpty else { return [] }

        let maxColumn = orderedColumns.map(\.column).max() ?? 0
        var result: [(Node, CGSize)] = []

        for (column, nodes) in orderedColumns {
            // X: column 0 (consumers) at the right, higher columns go left
            let x = -CGFloat(column) * (columnSpacing + nodeWidth)

            // Y: stack nodes vertically, centred around 0
            let totalHeight = nodes.enumerated().reduce(CGFloat(0)) { acc, pair in
                acc + pair.element.nodeSize.height + (pair.offset > 0 ? rowSpacing : 0)
            }
            var y = -totalHeight / 2

            for node in nodes {
                let nodeHeight = node.nodeSize.height
                let centreY = y + nodeHeight / 2
                result.append((node, CGSize(width: x, height: centreY)))
                y += nodeHeight + rowSpacing
            }
        }

        return result
    }
}
