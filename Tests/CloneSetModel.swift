import Foundation
@testable import Fabric

/// The patch model, as CloneSetContractTests needs it: every member is an
/// instance of one stored graph, so a node's counterpart has its id.
enum CloneSetModel
{
    static let name = "Patch model"

    static let divergences: Set<CloneSetDivergence> = []

    static func counterpart<T: Node>(of node: T, from source: SubgraphNode, in member: SubgraphNode) -> T?
    {
        member.subGraph.nodesRecursive().first { $0.id == node.id } as? T
    }

    static func syncSiblings(of member: SubgraphNode)
    {
        member.graph?.patchCloneSiblings(of: member)
    }

    static func syncMember(_ target: SubgraphNode, from source: SubgraphNode) throws
    {
        try source.graph?.patchCloneMember(target, from: source)
    }

    /// Whether `member`'s sub graph encodes to its set's stored graph.
    static func isInStep(_ member: SubgraphNode) -> Bool
    {
        member.isInStepWithCloneSet
    }
}
