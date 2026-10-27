import Foundation

/// Mutable planning scratch belongs to the renderer's topology cache, never to
/// a node. Pull responses are evaluated each pass; only identity slots are cached.
internal final class GraphExecutionPlanner {
    private enum State {
        case unvisited
        case processing
        case processed
        case keepAliveWalked
        case declined
    }

    private struct Entry {
        var pass: UInt64 = 0
        var state: State = .unvisited
    }

    private var nodes: ContiguousArray<Node> = []
    private var entries: ContiguousArray<Entry> = []
    private let topologyNodeCount: Int
    private var pass: UInt64 = 0
    private var isPlanning = false

    init(nodes initialNodes: [Node]) {
        nodes.reserveCapacity(initialNodes.count)
        entries.reserveCapacity(initialNodes.count)
        // Identity resolution is paid once when topology changes. Runtime pull
        // traversal uses integer slots instead of looking up this dictionary.
        var slotsByID: [UUID: Int] = [:]
        slotsByID.reserveCapacity(initialNodes.count)
        for node in initialNodes {
            if let slot = slotsByID[node.id] {
                node.executionPlanningSlot = slot
            } else {
                let slot = nodes.count
                slotsByID[node.id] = slot
                node.executionPlanningSlot = slot
                nodes.append(node)
                entries.append(Entry())
            }
        }
        topologyNodeCount = nodes.count
    }

    func plan(roots: [(node: Node, requestedOutputPort: Port?)],
              alreadyScheduledNodes: [Node] = [],
              forcedNodes: [Node] = []) -> [Node]
    {
        // Custom pull hooks may reenter execution. An active pass must keep its
        // own states; this exceptional path does not share mutable scratch.
        if isPlanning {
            return GraphExecutionPlanner(nodes: Array(nodes)).plan(
                roots: roots, alreadyScheduledNodes: alreadyScheduledNodes, forcedNodes: forcedNodes)
        }
        isPlanning = true
        defer {
            // Foreign forced/upstream nodes belong to this call, not the cached
            // graph topology. Release them while keeping scratch capacity.
            let temporaryCount = nodes.count - topologyNodeCount
            nodes.removeLast(temporaryCount)
            entries.removeLast(temporaryCount)
            isPlanning = false
        }

        if pass == .max {
            for index in entries.indices { entries[index] = Entry() }
            pass = 0
        }
        pass += 1

        for node in alreadyScheduledNodes { setState(.processed, at: slot(for: node)) }

        var ordered: [Node] = []
        for root in roots {
            pull(root.node, requestedOutputPort: root.requestedOutputPort, ordered: &ordered)
        }
        for node in forcedNodes {
            pull(node, requestedOutputPort: nil, ordered: &ordered)
        }
        // Preserve the explicit-force contract even when a pull declined.
        for node in forcedNodes where state(at: slot(for: node)) != .processed {
            ordered.append(node)
        }
        return ordered
    }

    private func slot(for node: Node) -> Int {
        let hint = node.executionPlanningSlot
        if nodes.indices.contains(hint), nodes[hint] === node { return hint }

        // A hint can belong to another renderer/layout. Never trust it without
        // validation. Also support callers forcing nodes outside graph.nodes,
        // including upstream nodes reached through published/proxy connections.
        if let slot = nodes.firstIndex(where: { $0.id == node.id }) {
            node.executionPlanningSlot = slot
            return slot
        }
        let slot = nodes.count
        nodes.append(node)
        entries.append(Entry())
        node.executionPlanningSlot = slot
        return slot
    }

    private func state(at slot: Int) -> State {
        entries[slot].pass == pass ? entries[slot].state : .unvisited
    }

    private func setState(_ state: State, at slot: Int) {
        entries[slot] = Entry(pass: pass, state: state)
    }

    @discardableResult
    private func pull(_ node: Node, requestedOutputPort: Port?, ordered: inout [Node]) -> Bool {
        let response = node.respondToPull(requestedOutputPort: requestedOutputPort)
        let slot = slot(for: node)
        switch response {
        case .declined(let keepAlivePorts):
            if state(at: slot) == .unvisited {
                setState(.keepAliveWalked, at: slot)
                for port in keepAlivePorts { pullConnections(port, ordered: &ordered) }
            }
            return false

        case .evaluate(let pullingPorts):
            switch state(at: slot) {
            case .processed, .processing: return true
            case .declined: return false
            case .keepAliveWalked, .unvisited: break
            }
            setState(.processing, at: slot)
            var attempted = 0
            var active = 0
            for port in pullingPorts {
                let counts = pullConnections(port, ordered: &ordered)
                attempted += counts.attempted
                active += counts.active
            }
            if attempted > 0 && active == 0 {
                setState(.declined, at: slot)
                return false
            }
            ordered.append(node)
            setState(.processed, at: slot)
            return true
        }
    }

    @discardableResult
    private func pullConnections(_ input: Port, ordered: inout [Node]) -> (attempted: Int, active: Int) {
        var attempted = 0
        var active = 0
        // Array iteration keeps the connection list stable if a pull hook edits
        // it. Connection activity and weak endpoints are checked as visited.
        for connection in input.connections {
            guard connection.active, connection.inletPortID == input.id,
                  let output = connection.outletPort, let node = output.node
            else { continue }
            attempted += 1
            if pull(node, requestedOutputPort: output, ordered: &ordered) { active += 1 }
        }
        return (attempted, active)
    }
}
