//
//  DocumentFileReference.swift
//  Fabric
//

import Foundation

/// Resolves the string representation used by file-picker parameter ports.
///
/// File importers continue to store absolute `file://` URLs. A user-authored
/// filesystem path without that prefix is interpreted relative to the saved
/// document's directory. Keeping the persisted value as a String preserves
/// compatibility with existing graphs and with String connections.
public enum DocumentFileReference
{
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
