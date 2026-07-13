//
//  GraphCanvasContext.swift
//  Fabric
//
//  Created by Claude on 3/26/26.
//

import SwiftUI

struct GraphConnectionPair: Identifiable
{
    struct ID: Hashable
    {
        let outletID: UUID
        let inletID: UUID
    }

    let outlet: Port
    let inlet: Port

    var id: ID
    {
        ID(outletID: outlet.id, inletID: inlet.id)
    }
}

/// Owns all editor session state for a node canvas: subgraph navigation,
/// scroll position, drag preview, port hit-testing, selection tracking,
/// and auto-layout timing for rapid node adds.
///
/// Views should depend on this single object rather than reaching into
/// `Graph` for UI concerns. `Graph` remains a pure document model.
@Observable
public class GraphCanvasContext
{
    // MARK: - Navigation

    public let rootGraph: Graph
    public private(set) var entries: [SubgraphNode] = []

    /// The graph currently being displayed and edited.
    public var currentGraph: Graph
    {
        entries.last?.subGraph ?? rootGraph
    }
    
    // MARK: - Canvas Interaction State

    /// Canvas scroll position; used to calculate initial offset for newly added nodes.
    @ObservationIgnored public var currentScrollOffset: CGPoint = .zero

    /// Raw scroll view content offset; used by editor gestures without invalidating SwiftUI views.
    @ObservationIgnored public var currentScrollContentOffset: CGPoint = .zero

    /// Current scroll view container size; used by editor gestures without invalidating SwiftUI views.
    @ObservationIgnored public var currentScrollContainerSize: CGSize = .zero

    /// Fixed graph canvas size; used to translate model-space node positions into canvas coordinates.
    @ObservationIgnored public var canvasSize: CGSize = .zero

    /// Port currently being dragged (for preview line rendering).
    var dragPreviewSourcePortID: UUID? = nil

    /// Current endpoint of the drag preview line.
    var dragPreviewTargetPosition: CGPoint? = nil

    @ObservationIgnored private let titleHeight: CGFloat = 30
    @ObservationIgnored private let portVStackSpacing: CGFloat = 10
    @ObservationIgnored private let portRowHeight: CGFloat = 15
    @ObservationIgnored private let outletTopSpacerHeight: CGFloat = 25
    @ObservationIgnored private var cachedConnectionGraphID: UUID?
    @ObservationIgnored private var cachedConnectionRevision: Int = 0
    @ObservationIgnored private var cachedConnectionNodeCount: Int = 0
    @ObservationIgnored private var cachedConnectionPairs: [GraphConnectionPair] = []

    func connectionPairs(for graph: Graph) -> [GraphConnectionPair]
    {
        if cachedConnectionGraphID == graph.id,
           cachedConnectionRevision == graph.connectionRevision,
           cachedConnectionNodeCount == graph.nodes.count
        {
            return cachedConnectionPairs
        }

        let outlets = graph.nodes.flatMap(\.ports).filter { $0.kind == .Outlet }
        cachedConnectionPairs = outlets.flatMap { outlet in
            outlet.connections
                .filter { $0.kind == .Inlet }
                .map { GraphConnectionPair(outlet: outlet, inlet: $0) }
        }
        cachedConnectionGraphID = graph.id
        cachedConnectionRevision = graph.connectionRevision
        cachedConnectionNodeCount = graph.nodes.count

        return cachedConnectionPairs
    }

    public func graphPosition(for port: Port) -> CGPoint?
    {
        guard let node = port.node else { return nil }

        return self.graphPosition(for: port, nodeOffset: node.offset, nodeSize: node.nodeSize)
    }

    public func graphPosition(for port: Port, nodeOffset: CGSize, nodeSize: CGSize) -> CGPoint?
    {
        guard let node = port.node else { return nil }

        let xOffset: CGFloat
        let yFromTop: CGFloat
        let sameKindPorts = node.ports.filter { $0.kind == port.kind }
        let portIndex = sameKindPorts.firstIndex(where: { $0.id == port.id }) ?? 0

        switch port.kind
        {
        case .Inlet:
            xOffset = -nodeSize.width / 2
            yFromTop = titleHeight + portVStackSpacing + CGFloat(portIndex) * (portRowHeight + portVStackSpacing) + portRowHeight / 2

        case .Outlet:
            xOffset = nodeSize.width / 2
            yFromTop = outletTopSpacerHeight + portVStackSpacing + CGFloat(portIndex) * (portRowHeight + portVStackSpacing) + portRowHeight / 2
        }

        return CGPoint(x: nodeOffset.width + xOffset,
                       y: nodeOffset.height + yFromTop - nodeSize.height / 2)
    }

    public func canvasPosition(for port: Port) -> CGPoint?
    {
        guard let graphPosition = self.graphPosition(for: port) else { return nil }

        return self.canvasPosition(forGraphPosition: graphPosition)
    }

    public func canvasPosition(for port: Port, nodeOffset: CGSize, nodeSize: CGSize) -> CGPoint?
    {
        guard let graphPosition = self.graphPosition(for: port, nodeOffset: nodeOffset, nodeSize: nodeSize) else { return nil }

        return self.canvasPosition(forGraphPosition: graphPosition)
    }

    private func canvasPosition(forGraphPosition graphPosition: CGPoint) -> CGPoint
    {
        return CGPoint(x: graphPosition.x + canvasSize.width / 2,
                       y: graphPosition.y + canvasSize.height / 2)
    }

    public func nearestPortID(to graphPosition: CGPoint, maximumDistance: CGFloat = 25) -> UUID?
    {
        var closestPort: (id: UUID, distance: CGFloat)? = nil

        for node in currentGraph.nodes
        {
            for port in node.ports
            {
                guard let portPosition = self.canvasPosition(for: port) else { continue }

                let distance = hypot(graphPosition.x - portPosition.x, graphPosition.y - portPosition.y)
                guard distance < maximumDistance else { continue }

                if let currentClosest = closestPort
                {
                    if distance < currentClosest.distance
                    {
                        closestPort = (id: port.id, distance: distance)
                    }
                }
                else
                {
                    closestPort = (id: port.id, distance: distance)
                }
            }
        }

        return closestPort?.id
    }

    // MARK: - Auto-Layout Timing

    @ObservationIgnored private let nodeOffset = CGSize(width: 20, height: 20)
    @ObservationIgnored private var currentNodeOffset = CGSize.zero
    @ObservationIgnored private var lastAddedTime: TimeInterval = .zero
    @ObservationIgnored private var nodeAddedResetTime: TimeInterval = 10.0

    // MARK: - Init

    public init(rootGraph: Graph)
    {
        self.rootGraph = rootGraph
    }
    
    public func enter(_ node: SubgraphNode)
    {
        entries.append(node)
        syncUndoManager()
    }

    public func pop()
    {
        guard !entries.isEmpty else { return }
        entries.removeLast()
        syncUndoManager()
    }

    public func popTo(_ node: SubgraphNode)
    {
        guard let index = entries.firstIndex(where: { $0.id == node.id }) else { return }
        entries = Array(entries.prefix(through: index))
        syncUndoManager()
    }

    public func popToRoot()
    {
        entries.removeAll()
        syncUndoManager()
    }

    // MARK: - Interactive Node Addition

    /// Add a node from a registry wrapper via user interaction.
    /// Positions the node at the current scroll center and staggers
    /// rapid successive adds so they don't pile on top of each other.
    public func layoutNode(_ node: Node) throws
    {
        let graph = currentGraph
        node.offset = self.calcInteractiveOffset(for: node)
    }

    /// Calculates the offset for a user-initiated add: centered on the
    /// current scroll position, plus a stagger when nodes are added in
    /// quick succession.
    private func calcInteractiveOffset(for node: Node) -> CGSize
    {
        let base = CGSize(width: currentScrollOffset.x - node.nodeSize.width / 2.0,
                          height: currentScrollOffset.y - node.nodeSize.height / 4.0)
        return base + calcRapidAddStagger()
    }

    /// Returns an accumulated offset when nodes are added within
    /// `nodeAddedResetTime` of each other, so rapid adds fan out
    /// rather than stacking.
    private func calcRapidAddStagger() -> CGSize
    {
        let deltaTime = Date.now.timeIntervalSinceReferenceDate - lastAddedTime
        lastAddedTime = Date.now.timeIntervalSinceReferenceDate

        if deltaTime < nodeAddedResetTime
        {
            currentNodeOffset += nodeOffset
        }
        else
        {
            currentNodeOffset = .zero
        }

        return currentNodeOffset
    }

    // MARK: - Private

    /// Propagate the undo manager to the active subgraph so undo works at any nesting level.
    private func syncUndoManager()
    {
        if let active = entries.last?.subGraph, let undoManager = rootGraph.undoManager
        {
            active.undoManager = undoManager
        }
    }
}
