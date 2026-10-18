//
//  DocumentFileReference.swift
//  Fabric
//

import Foundation

/// Resolves the string representation used by file-picker parameter ports.
///
/// Saved graphs use paths relative to the document directory for files inside
/// it, which travel with the document. Files outside it, and every file in an
/// unsaved graph, keep absolute file URLs. Persisting a String preserves
/// compatibility with existing graphs and String connections.
public enum DocumentFileReference
{
    public static func reference(for fileURL: URL, relativeTo directoryURL: URL?) -> String
    {
        let absoluteReference = fileURL.standardizedFileURL.absoluteString
        guard let directoryURL else { return absoluteReference }

        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let directoryComponents = directoryURL.standardizedFileURL.pathComponents
        guard fileComponents.starts(with: directoryComponents) else { return absoluteReference }

        let components = fileComponents.dropFirst(directoryComponents.count)
        return components.isEmpty ? "." : components.joined(separator: "/")
    }

    public static func resolve(_ reference: String,
                               relativeTo documentDirectoryURL: URL?,
                               directoryHint: URL.DirectoryHint = .inferFromPath) -> URL?
    {
        guard reference.isEmpty == false else { return nil }

        if reference.hasPrefix("file://")
        {
            guard let fileURL = URL(string: reference), fileURL.isFileURL else { return nil }
            return fileURL.standardizedFileURL
        }

        if reference.hasPrefix("/")
        {
            return URL(filePath: reference, directoryHint: directoryHint).standardizedFileURL
        }

        guard let documentDirectoryURL else { return nil }

        return URL(filePath: reference,
                   directoryHint: directoryHint,
                   relativeTo: documentDirectoryURL.standardizedFileURL)
            .standardizedFileURL
    }
}
