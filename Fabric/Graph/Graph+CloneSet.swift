//
//  Graph+CloneSet.swift
//  Fabric
//
//  Created by Claude on 9/10/26.
//

import Foundation
internal import AnyCodable

/// A member's view of its set: the source of its title icon, its subtitle
/// and their tooltip. See SubgraphNode.cloneSetInfo.
public struct CloneSetInfo: Equatable
{
    public let setID: UUID
    public let name: String
    public let memberCount: Int

    public init(setID: UUID, name: String, memberCount: Int)
    {
        self.setID = setID
        self.name = name
        self.memberCount = memberCount
    }

    /// The glyph every clone set member wears.
    public static let symbolName = "square.on.square"

    public var tooltip: String
    {
        "Clone set: \(name), \(memberCount) \(memberCount == 1 ? "member" : "members"). Edits here reach every member."
    }

    /// The member's title icon: the clone glyph, with the set and its size on hover.
    public var titleIcon: NodeTitleIcon
    {
        NodeTitleIcon(systemName: Self.symbolName, tooltip: tooltip)
    }
}

/// Clone sets: groups of SubgraphNodes kept identical in design to a shared
/// template while each executes on its own. Members are peers to edit: the
/// member you edit refreshes the template and its siblings are reconciled
/// from it. See CloneSet for the template and SubgraphNode.cloneRecord for
/// how a member's ids relate to it.
extension Graph
{
    // MARK: - Creation

    /// Adds a sibling of `node` to this graph: a duplicate that shares the
    /// node's clone set and records the same template ids against fresh ids
    /// of its own. Starts a set, with the node's design as its template, if
    /// the node is not in one yet. One undo step.
    @discardableResult
    public func duplicateAsClone(_ node: SubgraphNode,
                                 offset: CGSize = CGSize(width: 20, height: 20)) -> SubgraphNode?
    {
        guard node.graph === self else { return nil }

        undoManager?.beginUndoGrouping()
        defer
        {
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Duplicate as Clone")
        }

        let previousRecord = node.cloneRecord
        if node.cloneSetID == nil
        {
            guard let memberNodeType = try? self.qualifiedNodeID(for: type(of: node)).description else { return nil }
            let set = CloneSet(name: self.nextFreeCloneSetName(), memberNodeType: memberNodeType, templateJSON: Data())
            self.addCloneSetUndoably(set)
            self.setCloneMembership(setID: set.id, record: [:], on: node)
        }

        // The template and the source's record must be complete before the
        // copy is taken, since the copy's record is the source's, rewritten.
        self.refreshCloneTemplate(from: node)
        self.registerRecordUndo(on: node, previousRecord: previousRecord)

        let copies = self.duplicateNodes([node], offset: offset, preservingCloneLinks: true)
        guard let copy = copies.first as? SubgraphNode else { return nil }

        self.cloneSetMembershipChanged(setID: copy.cloneSetID)
        return copy
    }

    // MARK: - Template

    /// Rewrites the set's template from `member`'s current design. Returns
    /// false where the member is in no set.
    @discardableResult
    internal func refreshCloneTemplate(from member: SubgraphNode) -> Bool
    {
        guard let setID = member.cloneSetID, let set = self.cloneSet(for: setID),
              let canonical = self.cloneTemplateJSON(from: member)
        else { return false }

        if canonical != set.templateJSON { set.templateJSON = canonical }
        return true
    }

    /// `member`'s current design in the template's ids: canonical JSON of its
    /// sub graph with every local id rewritten to the id the member records
    /// for it. Any id the record did not have is given a template id and
    /// recorded first, so the template and the record together describe the
    /// member exactly. Does not touch the set.
    public func cloneTemplateJSON(from member: SubgraphNode) -> Data?
    {
        guard let data = try? JSONEncoder().encode(member.subGraph),
              let object = CloneSet.jsonObject(from: data)
        else { return nil }

        var record = member.cloneRecord
        var templateIDsByLocal = Dictionary(record.map { ($0.value, $0.key) },
                                            uniquingKeysWith: { first, _ in first })
        for localID in Self.findAllUUIDs(in: object) where templateIDsByLocal[localID] == nil
        {
            let templateID = UUID().uuidString
            record[templateID] = localID
            templateIDsByLocal[localID] = templateID
        }
        if record != member.cloneRecord { member.cloneRecord = record }

        let templateObject = Self.remapUUIDs(in: object,
                                             remap: templateIDsByLocal,
                                             preservingKeys: [Self.cloneSetIDKey]) as? [String: Any] ?? [:]
        return CloneSet.canonicalJSON(templateObject)
    }

    // MARK: - Discovery

    /// Every member of the set anywhere in the document, in document order.
    public func cloneSetMembers(of setID: UUID) -> [SubgraphNode]
    {
        self.rootGraph.subgraphNodesRecursive().filter { $0.cloneSetID == setID }
    }

    /// The other members of `node`'s set; empty outside a set.
    public func cloneSiblings(of node: SubgraphNode) -> [SubgraphNode]
    {
        guard let setID = node.cloneSetID else { return [] }
        return self.cloneSetMembers(of: setID).filter { $0 !== node }
    }

    /// Subgraph nodes in this graph and, depth first, in their sub graphs.
    internal func subgraphNodesRecursive() -> [SubgraphNode]
    {
        self.nodes.flatMap { node -> [SubgraphNode] in
            guard let subgraphNode = node as? SubgraphNode else { return [] }
            return [subgraphNode] + subgraphNode.subGraph.subgraphNodesRecursive()
        }
    }

    // MARK: - Names

    /// Renames the set. Whitespace is trimmed; an empty name goes back to a
    /// system name, the lowest not in use by another set. Undoable.
    public func renameCloneSet(_ setID: UUID, to name: String)
    {
        guard let set = self.cloneSet(for: setID) else { return }

        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty
        {
            trimmed = self.nextFreeCloneSetName(ignoring: setID)
        }
        let previous = set.name
        guard previous != trimmed else { return }

        set.name = trimmed
        self.cloneSetMembershipChanged(setID: setID)

        undoManager?.registerUndo(withTarget: self) { graph in
            graph.renameCloneSet(setID, to: previous)
        }
        undoManager?.setActionName("Rename Clone Set")
    }

    /// "Set A", "Set B", ... "Set Z", "Set AA", ...: the first not in use by
    /// any set in the document, `excluding` names claimed in the same edit
    /// and `ignoring` the set being renamed, whose own name is free to it.
    internal func nextFreeCloneSetName(excluding claimed: Set<String> = [], ignoring setID: UUID? = nil) -> String
    {
        let used = Set(self.rootGraph.cloneSets.filter { $0.id != setID }.map(\.name)).union(claimed)
        var index = 0
        while true
        {
            let candidate = "Set \(Self.cloneSetLetters(for: index))"
            if !used.contains(candidate) { return candidate }
            index += 1
        }
    }

    private static func cloneSetLetters(for index: Int) -> String
    {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var letters = ""
        var remaining = index
        repeat
        {
            letters.insert(alphabet[remaining % alphabet.count], at: letters.startIndex)
            remaining = remaining / alphabet.count - 1
        }
        while remaining >= 0
        return letters
    }

    // MARK: - Unlink

    /// Takes `node` out of its set: it keeps its contents and becomes an
    /// ordinary subgraph. Sets nested inside it get sets of their own, each
    /// on a copy of the nested template, so their records still resolve while
    /// they detach from their counterparts in the former siblings. Undoable.
    public func unlinkClone(_ node: SubgraphNode)
    {
        guard node.graph === self, let setID = node.cloneSetID else { return }

        let nestedMembers = node.subGraph.subgraphNodesRecursive().filter { $0.cloneSetID != nil }
        let nestedSetIDs = Set(nestedMembers.compactMap(\.cloneSetID))
        var claimedNames = Set<String>()
        var detachedSets: [UUID: CloneSet] = [:]
        for nestedSetID in nestedSetIDs.sorted(by: { $0.uuidString < $1.uuidString })
        {
            guard let nestedSet = self.cloneSet(for: nestedSetID) else { continue }
            let name = self.nextFreeCloneSetName(excluding: claimedNames)
            claimedNames.insert(name)
            detachedSets[nestedSetID] = CloneSet(name: name, memberNodeType: nestedSet.memberNodeType, templateJSON: nestedSet.templateJSON)
        }

        undoManager?.beginUndoGrouping()
        defer
        {
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Unlink from Clones")
        }

        for set in detachedSets.values { self.addCloneSetUndoably(set) }

        self.setCloneMembership(setID: nil, record: [:], on: node)
        for nestedMember in nestedMembers
        {
            guard let nestedSetID = nestedMember.cloneSetID, let detached = detachedSets[nestedSetID] else { continue }
            self.setCloneMembership(setID: detached.id, record: nestedMember.cloneRecord, on: nestedMember)
        }

        self.cloneSetMembershipChanged(setID: setID)
    }

    // MARK: - Bookkeeping

    internal func addCloneSetUndoably(_ set: CloneSet)
    {
        self.addCloneSet(set)
        undoManager?.registerUndo(withTarget: self) { graph in
            graph.removeCloneSetUndoably(set)
        }
    }

    internal func removeCloneSetUndoably(_ set: CloneSet)
    {
        self.removeCloneSet(set)
        undoManager?.registerUndo(withTarget: self) { graph in
            graph.addCloneSetUndoably(set)
        }
    }

    /// Undoable assignment of a node's set and record. The badge on every
    /// member of the sets touched is refreshed by `cloneSetMembershipChanged`.
    internal func setCloneMembership(setID: UUID?, record: [String: String], on node: SubgraphNode)
    {
        let previousID = node.cloneSetID
        let previousRecord = node.cloneRecord
        guard previousID != setID || previousRecord != record else { return }

        node.cloneSetID = setID
        node.cloneRecord = record
        node.subtitleSubject.send()

        undoManager?.registerUndo(withTarget: self) { graph in
            graph.setCloneMembership(setID: previousID, record: previousRecord, on: node)
            graph.cloneSetMembershipChanged(setID: previousID)
            graph.cloneSetMembershipChanged(setID: setID)
        }
    }

    /// A record grown by a template refresh inside an undoable edit goes back
    /// with that edit.
    private func registerRecordUndo(on node: SubgraphNode, previousRecord: [String: String])
    {
        let grown = node.cloneRecord
        guard grown != previousRecord else { return }
        undoManager?.registerUndo(withTarget: self) { graph in
            node.cloneRecord = previousRecord
            graph.registerRecordUndo(on: node, previousRecord: grown)
        }
    }

    /// The member count a set's badge shows changed; refresh every member.
    internal func cloneSetMembershipChanged(setID: UUID?)
    {
        guard let setID else { return }
        for member in self.cloneSetMembers(of: setID)
        {
            member.subtitleSubject.send()
        }
    }

    /// Strips clone links from a node and everything nested in it, for copies
    /// that must not be members.
    internal static func clearCloneLinks(in node: Node)
    {
        guard let subgraphNode = node as? SubgraphNode else { return }
        subgraphNode.cloneSetID = nil
        subgraphNode.cloneRecord = [:]
        for inner in subgraphNode.subGraph.nodes { clearCloneLinks(in: inner) }
    }
}
