//
//  PortHydrationSession.swift
//  Fabric
//

import Foundation

/// The document's port values for one node's decode, applied onto the
/// code-declared ports as each is made (see Node.init(from:)).
///
/// The session lives only for the decode pass. Graph finalizes it once node
/// inits and their reconciles are done: whatever remains unconsumed matched
/// nothing the code declares and is reported dropped, and closing the session
/// means a port declared later can never take stale document state.
internal final class PortHydrationSession
{
    private var pending: [PortKey: PortValue]
    private var consumed: [ObjectIdentifier: PortState] = [:]

    init(states: [PortState])
    {
        self.pending = Dictionary(states.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// Keys whose value has not landed on any port.
    var unconsumedKeys: [String] { pending.keys.map(\.description).sorted() }

    /// Hands back the saved value for `port`'s key as a state to put on it.
    /// The match is exact: a value saved under any other key, a retired port or
    /// a renamed one, stays pending and is reported dropped at finalize.
    func hydrate(_ port: Port, key: PortKey) -> PortState?
    {
        guard let value = pending.removeValue(forKey: key) else { return nil }
        let state = PortState(key: key, value: value)
        consumed[ObjectIdentifier(port)] = state
        return state
    }

    /// Returns a port's consumed value to the pending set, for a node that
    /// retires a port and declares it again within one decode.
    func relinquish(_ port: Port)
    {
        guard let state = consumed.removeValue(forKey: ObjectIdentifier(port)) else { return }
        pending[state.key] = state.value
    }
}

/// A saved value that may not decode, a case this build does not know, say;
/// it is dropped rather than failing the node.
internal struct LossyPortValue: Decodable
{
    let value: PortValue?
    init(from decoder: any Decoder) throws { self.value = try? PortValue(from: decoder) }
}
