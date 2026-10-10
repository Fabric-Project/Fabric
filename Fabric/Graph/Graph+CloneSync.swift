//
//  Graph+CloneSync.swift
//  Fabric
//
//  Created by Claude on 10/9/26.
//

import Foundation
import Satin

/// Keeping a clone set in step: the member edited last is encoded as the
/// set's stored graph, and each sibling's sub graph is replaced with a fresh
/// instance decoded from it. Nothing is diffed: a sibling after a sync is a
/// sibling as a document load would make it, with the parent-facing things
/// that are its own put back, its proxies under their ids with the parent's
/// wires onto them, and its published inlet values. Everything the sibling
/// held at runtime, a movie's position, an integrator's sum, a feedback
/// buffer, starts over. See SubgraphNode.replaceSubGraph.
extension Graph
{
    /// How the coordinator brings a member's siblings in line with it.
    internal func syncCloneSiblings(of member: SubgraphNode)
    {
        self.reinstantiateCloneSiblings(of: member)
    }

    /// Stores `member`'s sub graph as its set's graph and, where that changed
    /// the stored graph, re-instantiates every sibling from it. Registers no
    /// undo steps: the edit that caused this is undone on the member, and the
    /// siblings follow again. A sibling that cannot be decoded keeps what it
    /// has and is reported.
    public func reinstantiateCloneSiblings(of member: SubgraphNode)
    {
        guard member.cloneSetID != nil else { return }
        let coordinator = self.cloneSetCoordinator
        guard !coordinator.isSyncing else { return }
        coordinator.isSyncing = true
        defer { coordinator.isSyncing = false }

        do
        {
            guard try self.refreshCloneSetGraph(from: member) else { return }
        }
        catch
        {
            print("Clone set sync: \(member) could not be stored: \(error.localizedDescription)")
            return
        }

        for sibling in self.cloneSiblings(of: member)
        {
            do
            {
                let proxiesBefore = sibling.proxyInnerPortIDs
                try sibling.reinstantiateSubGraph()
                // An unpublish takes the proxy from the sibling, but not the
                // parent's wires onto it; the sibling keeps them for the proxy's
                // return.
                let dropped = sibling.graph?.pruneDanglingConnections() ?? []
                sibling.keepWires(dropped, offProxies: proxiesBefore)
            }
            catch { print("Clone set sync: \(sibling) not re-instantiated from \(member): \(error.localizedDescription)") }
        }
    }

    /// Makes `target` an instance of `source`'s sub graph now, whether or not
    /// the stored graph changed. Throws where the two are not members of one
    /// set.
    public func reinstantiateCloneMember(_ target: SubgraphNode, from source: SubgraphNode) throws
    {
        guard let setID = source.cloneSetID, target.cloneSetID == setID, target !== source else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(target) and \(source) are not members of one clone set.")
        }

        let coordinator = self.cloneSetCoordinator
        let wasSyncing = coordinator.isSyncing
        coordinator.isSyncing = true
        defer { coordinator.isSyncing = wasSyncing }

        try self.refreshCloneSetGraph(from: source)
        try target.reinstantiateSubGraph()
    }
}

/// Where an undo step registered inside a clone set member acts, by ids, so
/// the step finds its target again after a sync re-instantiates the member's
/// sub graph under the same ids: the path of subgraph node ids from the
/// document's root to the graph the edit was made in, and the target's id
/// there. The step is registered against this, which it holds, since its
/// target may be retired and released before it is undone.
final class CloneUndoLocation
{
    private enum Target
    {
        case graph
        case node(UUID)
        case viewModel(nodeID: UUID)
        case parameter(portID: UUID)
        /// A target with no id to find it by, held as it was.
        case object(AnyObject)
    }

    private weak var root: Graph?
    private let path: [UUID]
    private let target: Target

    /// Nil outside clone set members, where nothing is re-instantiated.
    init?(of graph: Graph, target: AnyObject)
    {
        guard !graph.enclosingCloneMembers.isEmpty else { return nil }
        switch target
        {
        case is Graph:                          self.target = .graph
        case let node as Node:                  self.target = .node(node.id)
        case let viewModel as NodeViewModel:    self.target = .viewModel(nodeID: viewModel.node.id)
        // A parameter port's parameter takes the port's id.
        case let parameter as any Parameter:    self.target = .parameter(portID: parameter.id)
        default:                                self.target = .object(target)
        }
        self.root = graph.rootGraph
        self.path = graph.ancestors.compactMap(\.ownerNode).map(\.id).reversed()
    }

    /// The graph the edit was made in, as the document holds it now.
    var liveGraph: Graph?
    {
        var graph = self.root
        for id in path
        {
            graph = (graph?.node(forID: id) as? SubgraphNode)?.subGraph
        }
        return graph
    }

    /// The target as the document holds it now; nil where it is not there.
    func liveTarget() -> AnyObject?
    {
        guard let graph = self.liveGraph else { return nil }

        switch target
        {
        case .graph:
            return graph
        case .node(let id):
            return graph.node(forID: id)
        case .viewModel(let nodeID):
            return graph.node(forID: nodeID).flatMap { graph.viewModelIfPresent(for: $0) }
        case .parameter(let portID):
            return graph.nodePort(forID: portID)?.parameter
        case .object(let object):
            return object
        }
    }
}
