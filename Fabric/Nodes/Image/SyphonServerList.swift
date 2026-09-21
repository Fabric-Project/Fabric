//
//  SyphonServerList.swift
//  Fabric
//

#if FABRIC_SYPHON_ENABLED

import Foundation
import Observation
import Syphon

/// One Syphon server, as the directory offers it.
public struct SyphonServerDescription: Identifiable, Hashable, Sendable
{
    /// Syphon's identity for the server, where it offers one. It names this
    /// server rather than the name it answers to: a relaunched application
    /// publishes under the same name as a different server.
    public let identity: String?

    /// The server's own name, which an application publishing one unnamed
    /// stream leaves empty.
    public let name: String

    public let appName: String

    public var id: String { self.identity ?? "\(self.appName)/\(self.name)" }

    /// The application on its own where the server is unnamed, both otherwise.
    public var displayName: String
    {
        self.name.isEmpty ? self.appName : "\(self.appName) – \(self.name)"
    }
}

/// The Syphon servers on offer, for anything that has to show them.
///
/// Watched once for the process rather than once per node. `SyphonServerDirectory`
/// is a singleton that observes the announce, retire and update notifications for
/// as long as the application runs and holds the list they carry, so mirroring it
/// has that lifetime by construction: there is nothing here whose going away
/// should stop the watching, which is what made the same observers wrong on a node.
///
/// For the main actor alone. A node reads the directory directly from `execute`,
/// where `serversMatchingName:appName:` is already safe to call and a snapshot
/// kept over here would be the wrong side of a hop.
@MainActor
@Observable
public final class SyphonServerList
{
    public static let shared = SyphonServerList()

    public private(set) var servers: [SyphonServerDescription] = []

    /// Syphon's announce / retire / update notifications, by raw name.
    ///
    /// Named literally rather than through Syphon's exported constants: those
    /// are `NSString * const` ending in "Notification", so Swift imports them
    /// as members of `NSNotification.Name` under refined spellings, and the
    /// literal values are the stabler reference. They are part of Syphon's
    /// cross-process contract — every publishing app posts exactly these.
    private static let directoryNotifications: [NSNotification.Name] = [
        NSNotification.Name("SyphonServerAnnounceNotification"),
        NSNotification.Name("SyphonServerRetireNotification"),
        NSNotification.Name("SyphonServerUpdateNotification"),
    ]

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init()
    {
        // The directory keeps the observers that post the notifications below,
        // so it has to exist before any of them can arrive.
        _ = SyphonServerDirectory.shared()

        self.observe()
        self.refresh()
    }

    private func observe()
    {
        let center = NotificationCenter.default
        self.observers = Self.directoryNotifications.map
        { name in
            center.addObserver(forName: name, object: nil, queue: .main)
            { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// Reads the directory out. Every way the list can change posts one of the
    /// notifications above, so there is nothing to poll for.
    public func refresh()
    {
        self.servers = SyphonServerDirectory.shared().servers
            .map
            { description in
                SyphonServerDescription(identity: (description[SyphonServerDescriptionUUIDKey] as? NSString) as String?,
                                        name: ((description[SyphonServerDescriptionNameKey] as? NSString) as String?) ?? "",
                                        appName: ((description[SyphonServerDescriptionAppNameKey] as? NSString) as String?) ?? "")
            }
            .sorted
            { lhs, rhs in
                (lhs.appName, lhs.name) < (rhs.appName, rhs.name)
            }
    }
}

#endif // FABRIC_SYPHON_ENABLED
