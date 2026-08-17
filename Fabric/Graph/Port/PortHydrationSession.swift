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
    private let legacyKeysForRegistryKey: (String) -> [String]

    init(snapshots: [PortRegistry.Snapshot], legacyKeys: @escaping (String) -> [String])
    {
        self.pendingByRegistryKey = snapshots.reduce(into: [:]) { $0[$1.name] = $1.payload.base }
        self.legacyKeysForRegistryKey = legacyKeys
    }

    /// Registry keys whose state has not landed on any registered port.
    var unconsumedKeys: [String] { pendingByRegistryKey.keys.sorted() }

    /// Applies the pending snapshot for `registryKey` — or one of its declared
    /// legacy aliases — onto `port`, provided the directions agree. Must run
    /// before the port registers: the registry indexes by the id hydration
    /// adopts.
    func hydrate(_ port: Port, registryKey: String)
    {
        for key in [registryKey] + legacyKeysForRegistryKey(registryKey)
        {
            guard let decoded = pendingByRegistryKey[key],
                  decoded.kind == port.kind
            else { continue }

            pendingByRegistryKey.removeValue(forKey: key)
            port.hydrate(from: decoded)
            return
        }
    }
}
