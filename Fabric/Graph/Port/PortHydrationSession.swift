//
//  PortHydrationSession.swift
//  Fabric
//

import Foundation

/// The document's contribution to a node's ports during decode: snapshots
/// keyed by registry key, applied onto the code-declared ports as each one
/// registers (see Node.init(from:) — declare-then-hydrate).
///
/// The session lives only for the decode pass. Graph finalizes it once node
/// inits and their dynamic rebuilds are done: whatever remains unconsumed
/// matched nothing the code declares and is reported dropped, and clearing
/// the session guarantees a port added later — a user action, a reconnecting
/// device — can never resurrect stale document state.
internal final class PortHydrationSession
{
    private var pendingByRegistryKey: [String: Port]
    private var consumedByPortID: [UUID: (registryKey: String, snapshot: Port)] = [:]
    private let documentKeyOrder: [String]

    init(snapshots: [PortRegistry.Snapshot])
    {
        self.pendingByRegistryKey = snapshots.reduce(into: [:]) { $0[$1.name] = $1.payload.base }
        self.documentKeyOrder = snapshots.map(\.name)
    }

    /// Registry keys whose state has not landed on any registered port.
    var unconsumedKeys: [String] { pendingByRegistryKey.keys.sorted() }

    /// Applies the pending snapshot for `registryKey` onto `port`, provided the
    /// directions agree. The match is exact: state saved under any other key —
    /// a retired port, a renamed one — stays pending and is reported dropped at
    /// finalize. Must run before the port registers: the registry indexes by
    /// the id hydration adopts.
    func hydrate(_ port: Port, registryKey: String)
    {
        guard let decoded = pendingByRegistryKey[registryKey],
              decoded.kind == port.kind
        else { return }

        pendingByRegistryKey.removeValue(forKey: registryKey)
        port.hydrate(from: decoded)
        consumedByPortID[port.id] = (registryKey: registryKey, snapshot: decoded)
    }

    /// Empties the pending set and hands back what was in it, in the order the
    /// document listed it. For a node whose source cannot rebuild the port set
    /// at decode time — a script that no longer parses, a shader that no longer
    /// compiles — these decoded instances are all that stands between the
    /// document and the loss of every port and wire the node had.
    func drainPendingSnapshots() -> [(registryKey: String, port: Port)]
    {
        func take(_ keys: [String]) -> [(registryKey: String, port: Port)]
        {
            keys.compactMap { key in
                pendingByRegistryKey.removeValue(forKey: key).map { (registryKey: key, port: $0) }
            }
        }

        return take(documentKeyOrder) + take(pendingByRegistryKey.keys.sorted())
    }

    /// Returns `port`'s consumed snapshot to the pending set. A node that
    /// removes and recreates the same registry key inside one decode — the
    /// image and matrix port branches of BaseImageNode's material sync do this
    /// across Live Image's two passes — would otherwise mint a fresh identity
    /// for the replacement and take the document's wires with it.
    func relinquish(_ port: Port)
    {
        guard let consumed = consumedByPortID.removeValue(forKey: port.id) else { return }
        pendingByRegistryKey[consumed.registryKey] = consumed.snapshot
    }
}
