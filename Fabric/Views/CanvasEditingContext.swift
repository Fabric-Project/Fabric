//
//  CanvasEditingContext.swift
//  Fabric
//
//  Created by Claude on 3/26/26.
//

import SwiftUI

/// Owns all editor session state for a node canvas: subgraph navigation,
/// scroll position, drag preview, port hit-testing, selection tracking,
/// and auto-layout timing for rapid node adds.
///
/// Views should depend on this single object rather than reaching into
/// `Graph` for UI concerns. `Graph` remains a pure document model.
@Observable
public class CanvasEditingContext
{
    // MARK: - Navigation

    public let rootGraph: Graph
    public private(set) var entries: [SubgraphNode] = []

    /// The graph currently being displayed and edited.
    public var activeGraph: Graph
    {
        entries.last?.subGraph ?? rootGraph
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

    // MARK: - Canvas Interaction State

    /// Canvas scroll position; used to calculate initial offset for newly added nodes.
    @ObservationIgnored public var currentScrollOffset: CGPoint = .zero

    /// Port currently being dragged (for preview line rendering).
    var dragPreviewSourcePortID: UUID? = nil

    /// Current endpoint of the drag preview line.
    var dragPreviewTargetPosition: CGPoint? = nil

    /// Cached screen positions of all ports, maintained by views during render for hit-testing.
    @ObservationIgnored var portPositions: [UUID: CGPoint] = [:]

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

    // MARK: - Interactive Node Addition

    /// Add a node from a registry wrapper via user interaction.
    /// Positions the node at the current scroll center and staggers
    /// rapid successive adds so they don't pile on top of each other.
    public func addNode(_ wrapper: NodeClassWrapper) throws
    {
        let graph = activeGraph
        let node = try wrapper.initializeNode(context: graph.context)
        node.offset = self.calcInteractiveOffset(for: node)
        graph.addNode(node)
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
