import Foundation
@testable import Fabric

/// The decode model, as CloneSetContractTests needs it: every member is an
/// instance of one stored graph, so a node's counterpart has its id.
enum CloneSetModel
{
    static let name = "Decode model"

    static let divergences: Set<CloneSetDivergence> = [.siblingNodesAreReplaced]

    static func counterpart<T: Node>(of node: T, from source: SubgraphNode, in member: SubgraphNode) -> T?
    {
        member.subGraph.nodesRecursive().first { $0.id == node.id } as? T
    }

    static func syncSiblings(of member: SubgraphNode)
    {
        member.graph?.reinstantiateCloneSiblings(of: member)
    }

    static func syncMember(_ target: SubgraphNode, from source: SubgraphNode) throws
    {
        try source.graph?.reinstantiateCloneMember(target, from: source)
    }
}
