//
//  Graph+SerializationDiagnostics.swift
//  Fabric
//

import Foundation

extension Graph
{
    // MARK: - Diagnostic Types

    /// Port state a document carried for registry keys the node's code no
    /// longer declares or rebuilds. That state (and any wires into those
    /// ports) is dropped on load — deliberately, the code owns the port set —
    /// and surfaced here so hosts can warn instead of losing data silently.
    public struct DroppedPortStateDiagnostic
    {
        public let nodeID: UUID
        public let nodeTitle: String
        public let droppedRegistryKeys: [String]
    }

    /// A saved wire the decode-time connection restore could not re-establish:
    /// an endpoint no longer exists (its port was retired, or its node failed
    /// to decode) or its port's type changed to something incompatible since
    /// the save. Wires are the destructive loss on load, so hosts should
    /// surface these.
    public struct DroppedConnectionDiagnostic
    {
        public enum Reason
        {
            case missingEndpoint
            case incompatibleTypes
        }

        public let portID: UUID
        public let otherPortID: UUID
        public let reason: Reason

        /// Endpoints named as "node.port" where they still resolve.
        public let summary: String
    }

    /// A node this document referenced that could not be loaded — its type is
    /// no longer registered (a plugin didn't load, or the node was retired)
    /// or its saved state failed to decode. The node is skipped, not the
    /// document: the rest of the graph decodes normally, and any connection
    /// that touched the missing node's ports is caught by
    /// DroppedConnectionDiagnostic once decoding reaches connections.
    public struct MissingNodeDiagnostic
    {
        public enum Reason
        {
            case typeNotRegistered
            case decodeFailed
        }

        public let serializedType: String
        public let reason: Reason
        public let summary: String
    }

    // MARK: - Building (called from Graph.init(from:), which owns appending
    // to the private(set) arrays above -- private(set) is file-scoped, so
    // this extension, living in its own file, can't touch those setters
    // itself even though it's the same type.

    /// Builds the diagnostic for a node that failed to load and logs it.
    func makeMissingNodeDiagnostic(serializedType: String, reason: MissingNodeDiagnostic.Reason, summary: String) -> MissingNodeDiagnostic
    {
        print("Graph decode: \(summary)")
        return MissingNodeDiagnostic(serializedType: serializedType, reason: reason, summary: summary)
    }

    /// Ends every node's port-hydration window and builds a diagnostic for
    /// each node that had saved state for keys its code no longer declares.
    func makeDroppedPortStateDiagnostics() -> [DroppedPortStateDiagnostic]
    {
        self.nodes.compactMap { node in
            let droppedKeys = node.finalizePortHydration()
            guard !droppedKeys.isEmpty else { return nil }
            print("Graph decode: '\(node.title)' dropped port state for retired keys \(droppedKeys)")
            return DroppedPortStateDiagnostic(nodeID: node.id,
                                              nodeTitle: node.title,
                                              droppedRegistryKeys: droppedKeys)
        }
    }

    /// Builds the diagnostic for a saved wire that couldn't be restored, or
    /// nil if this endpoint pair was already reported (the legacy connection
    /// map holds every wire under both endpoints, so either side can surface
    /// the same drop first).
    func makeDroppedConnectionDiagnostic(from portID: UUID,
                                         to otherPortID: UUID,
                                         reason: DroppedConnectionDiagnostic.Reason,
                                         portsByID: [UUID: Port],
                                         reportedPairs: inout Set<Set<UUID>>) -> DroppedConnectionDiagnostic?
    {
        guard reportedPairs.insert(Set([portID, otherPortID])).inserted else { return nil }

        // A raw port UUID means nothing to a person reading this; name
        // whichever side we can and describe the other relative to it, since
        // it's only ever the far side's owning node that failed to load.
        func describe(_ id: UUID) -> String?
        {
            guard let port = portsByID[id] else { return nil }
            return "\(port.node?.title ?? "?").\(port.displayName)"
        }

        let summary: String

        switch (describe(portID), describe(otherPortID))
        {
        case let (.some(known), .some(otherKnown)):
            summary = "\(known) ↔ \(otherKnown)"
        case let (.some(known), nil), let (nil, .some(known)):
            summary = "Could not find the connected port for \(known)"
        case (nil, nil):
            summary = "Could not restore a connection — neither port exists anymore"
        }

        let diagnostic = DroppedConnectionDiagnostic(portID: portID,
                                                     otherPortID: otherPortID,
                                                     reason: reason,
                                                     summary: summary)
        print("Graph decode: dropped connection (\(reason)): \(diagnostic.summary)")
        return diagnostic
    }
}
