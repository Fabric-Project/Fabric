#if FABRIC_SYPHON_ENABLED

import Foundation
import Syphon

/// Describes a Syphon server discovered on the system.
public struct SyphonServerDescription: Identifiable, Equatable, Sendable {
    public let id: String
    public let serverName: String
    public let appName: String
}

/// Public utility for discovering available Syphon servers.
/// Wraps SyphonServerDirectory so consumers don't need to import Syphon directly.
public enum FabricSyphonDiscovery {

    /// Returns all currently available Syphon servers.
    public static func availableServers() -> [SyphonServerDescription] {
        guard let servers = SyphonServerDirectory.shared().servers as? [[String: Any]] else {
            return []
        }
        return servers.compactMap { dict in
            let name = dict[SyphonServerDescriptionNameKey] as? String ?? ""
            let app = dict[SyphonServerDescriptionAppNameKey] as? String ?? ""
            return SyphonServerDescription(
                id: "\(app) - \(name)",
                serverName: name,
                appName: app
            )
        }
    }

    // MARK: - Notification Names

    /// Posted when a new Syphon server becomes available.
    public static let serverAnnounceNotification = NSNotification.Name.SyphonServerAnnounce

    /// Posted when a Syphon server is no longer available.
    public static let serverRetireNotification = NSNotification.Name.SyphonServerRetire

    /// Posted when a Syphon server's description changes.
    public static let serverUpdateNotification = NSNotification.Name.SyphonServerUpdate
}

#endif
