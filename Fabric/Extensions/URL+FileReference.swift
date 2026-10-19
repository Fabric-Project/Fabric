//
//  URL+FileReference.swift
//  Fabric
//

import Foundation

/// File references: the string representation used by file-picker parameter ports.
///
/// Saved graphs use paths relative to the document directory for files inside
/// it, which travel with the document. Files outside it, and every file in an
/// unsaved graph, keep absolute file URLs. A relative path is the user's to
/// write, so it persists as written. Persisting a String preserves
/// compatibility with existing graphs and String connections.
public extension URL
{
    /// Resolves a file URL, an absolute filesystem path, or a path relative to
    /// the document directory. Without a document directory, only absolute
    /// references resolve.
    init?(fileReference: String,
          relativeTo documentDirectoryURL: URL?,
          directoryHint: URL.DirectoryHint = .inferFromPath)
    {
        guard fileReference.isEmpty == false else { return nil }

        // A file URL: its path follows the authority, so is absolute by definition.
        if fileReference.hasPrefix("file://")
        {
            guard let fileURL = URL(string: fileReference), fileURL.isFileURL else { return nil }
            self = fileURL.standardizedFileURL
        }
        // An absolute filesystem path: Fabric runs only on POSIX systems, where a leading slash is the root.
        else if fileReference.hasPrefix("/")
        {
            self = URL(filePath: fileReference, directoryHint: directoryHint).standardizedFileURL
        }
        else
        {
            guard let documentDirectoryURL else { return nil }

            self = URL(filePath: fileReference,
                       directoryHint: directoryHint,
                       relativeTo: documentDirectoryURL.standardizedFileURL)
                .standardizedFileURL
        }
    }

    /// A path relative to the directory for a file within it, otherwise an absolute file URL.
    func fileReference(relativeTo directoryURL: URL?) -> String
    {
        let absoluteReference = self.standardizedFileURL.absoluteString
        guard let directoryURL else { return absoluteReference }

        let fileComponents = self.standardizedFileURL.pathComponents
        let directoryComponents = directoryURL.standardizedFileURL.pathComponents
        guard fileComponents.starts(with: directoryComponents) else { return absoluteReference }

        let components = fileComponents.dropFirst(directoryComponents.count)
        return components.isEmpty ? "." : components.joined(separator: "/")
    }
}
