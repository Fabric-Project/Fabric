//
//  SubGraphNavigationPath.swift
//  Fabric
//
//  Created by Codex on 3/20/26.
//

import SwiftUI

@Observable
public class SubGraphNavigationPath
{
    public struct Entry: Identifiable
    {
        public let id = UUID()
        public let node: SubgraphNode

        public var graph: Graph { node.subGraph }
        public var name: String { node.name }
    }

    private let rootGraph: Graph
    public private(set) var entries: [Entry] = []

    public init(rootGraph: Graph)
    {
        self.rootGraph = rootGraph
    }

    /// The graph currently being displayed and edited.
    public var activeGraph: Graph
    {
        entries.last?.graph ?? rootGraph
    }

    public func enter(_ node: SubgraphNode)
    {
        entries.append(Entry(node: node))
        syncToGraph()
    }

    public func pop()
    {
        guard !entries.isEmpty else { return }
        entries.removeLast()
        syncToGraph()
    }

    public func popTo(_ entry: Entry)
    {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries = Array(entries.prefix(through: index))
        syncToGraph()
    }

    public func popToRoot()
    {
        entries.removeAll()
        syncToGraph()
    }

    /// Keep Graph.activeSubGraph in sync for code that still reads it.
    private func syncToGraph()
    {
        let active = entries.last?.graph
        rootGraph.activeSubGraph = active

        if let active, let undoManager = rootGraph.undoManager
        {
            active.undoManager = undoManager
        }
    }
}
