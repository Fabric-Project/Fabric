//
//  DocumentFileReference.swift
//  Fabric
//

import Foundation

/// Resolves the string representation used by file-picker parameter ports.
///
/// Saved graphs use paths relative to the document directory, including `../`.
/// Unsaved graphs retain absolute file URLs. Persisting a String preserves
/// compatibility with existing graphs and String connections.
public enum DocumentFileReference
{
    public static func reference(for fileURL: URL, relativeTo directoryURL: URL?) -> String
    {
        guard let directoryURL else { return fileURL.standardizedFileURL.absoluteString }

        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let directoryComponents = directoryURL.standardizedFileURL.pathComponents
        let commonCount = zip(fileComponents, directoryComponents)
            .prefix { $0.0 == $0.1 }.count
        let components = Array(repeating: "..", count: directoryComponents.count - commonCount)
            + fileComponents.dropFirst(commonCount)
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
