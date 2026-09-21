//
//  DocumentBundleExporter.swift
//  Fabric
//

import Foundation
import Satin

public enum DocumentBundleExportError: Error, LocalizedError
{
    case destinationAlreadyExists(URL)
    case unresolvedReference(String)
    case missingAsset(URL)
    case basenameCollision(name: String, first: URL, second: URL)
    case exportedPortMissing(UUID)

    public var errorDescription: String?
    {
        switch self
        {
        case .destinationAlreadyExists(let url):
            return "A file already exists at \(url.path)."
        case .unresolvedReference(let reference):
            return "The file reference '\(reference)' could not be resolved. Save the document before exporting relative paths."
        case .missingAsset(let url):
            return "The referenced asset does not exist: \(url.path)"
        case .basenameCollision(let name, let first, let second):
            return "Two different assets are named '\(name)': \(first.path) and \(second.path). Rename one before exporting."
        case .exportedPortMissing(let id):
            return "The exported graph no longer contains file-reference port \(id.uuidString)."
        }
    }
}

/// Produces a portable directory package containing a graph snapshot and the
/// static assets referenced by unconnected file-picker parameters.
///
/// The source graph is never mutated. Its cloned file references are rewritten
/// to `Assets/<original filename>`. Different source assets with the same
/// basename are rejected rather than renamed or overwritten. Connected file
/// references are graph-driven and remain untouched in the exported graph.
public enum DocumentBundleExporter
{
    public static let graphFilename = "Graph.fabric"
    public static let assetsDirectoryName = "Assets"

    private struct AssetReference
    {
        let portID: UUID
        let sourceURL: URL
        let bundledPath: String
    }

    public static func export(graph: Graph, to destinationURL: URL) throws
    {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) == false else
        {
            throw DocumentBundleExportError.destinationAlreadyExists(destinationURL)
        }

        let references = try self.assetReferences(in: graph, fileManager: fileManager)
        let exportedGraph = try self.clone(graph)
        try self.rewrite(references, in: exportedGraph)

        let parentURL = destinationURL.deletingLastPathComponent()
        let temporaryBundleURL = parentURL.appending(
            path: ".\(UUID().uuidString).fabricbundle-export",
            directoryHint: .isDirectory
        )
        let temporaryAssetsURL = temporaryBundleURL.appending(
            path: self.assetsDirectoryName,
            directoryHint: .isDirectory
        )

        defer
        {
            if fileManager.fileExists(atPath: temporaryBundleURL.path(percentEncoded: false))
            {
                try? fileManager.removeItem(at: temporaryBundleURL)
            }
        }

        try fileManager.createDirectory(at: temporaryAssetsURL,
                                        withIntermediateDirectories: true)

        var copiedBundledPaths: Set<String> = []
        for reference in references where copiedBundledPaths.insert(reference.bundledPath).inserted
        {
            let assetURL = temporaryBundleURL.appending(path: reference.bundledPath)
            try fileManager.copyItem(at: reference.sourceURL, to: assetURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let graphData = try encoder.encode(exportedGraph)
        try graphData.write(to: temporaryBundleURL.appending(path: self.graphFilename),
                            options: .atomic)

        try fileManager.moveItem(at: temporaryBundleURL, to: destinationURL)
    }

    /// Builds the package representation used by FileDocument Save and Save As.
    /// Existing package children are retained so connected/dynamic references
    /// cannot accidentally prune assets that the graph may select at runtime.
    public static func fileWrapper(graph: Graph,
                                   preserving existingBundle: FileWrapper?) throws -> FileWrapper
    {
        let fileManager = FileManager.default
        let references = try self.assetReferences(in: graph, fileManager: fileManager)
        let exportedGraph = try self.clone(graph)
        try self.rewrite(references, in: exportedGraph)

        var packageChildren: [String: FileWrapper]
        if let existingBundle, existingBundle.isDirectory
        {
            packageChildren = existingBundle.fileWrappers ?? [:]
        }
        else
        {
            // Save As may convert an existing standalone document into a
            // bundle. SwiftUI still supplies that regular file as
            // existingFile, whose fileWrappers accessor raises NSException.
            packageChildren = [:]
        }

        var assetChildren: [String: FileWrapper]
        if let existingAssets = packageChildren[self.assetsDirectoryName],
           existingAssets.isDirectory
        {
            assetChildren = existingAssets.fileWrappers ?? [:]
        }
        else
        {
            assetChildren = [:]
        }

        for reference in references
        {
            let assetWrapper = try FileWrapper(url: reference.sourceURL,
                                               options: [.immediate])
            assetChildren[reference.sourceURL.lastPathComponent] = assetWrapper
        }

        let assetsWrapper = FileWrapper(directoryWithFileWrappers: assetChildren)
        assetsWrapper.preferredFilename = self.assetsDirectoryName
        packageChildren[self.assetsDirectoryName] = assetsWrapper

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let graphData = try encoder.encode(exportedGraph)
        let graphWrapper = FileWrapper(regularFileWithContents: graphData)
        graphWrapper.preferredFilename = self.graphFilename
        packageChildren[self.graphFilename] = graphWrapper

        return FileWrapper(directoryWithFileWrappers: packageChildren)
    }

    private static func assetReferences(in graph: Graph,
                                        fileManager: FileManager) throws -> [AssetReference]
    {
        var references: [AssetReference] = []
        var sourceByBasename: [String: URL] = [:]

        try self.visitFileReferencePorts(in: graph) { port in
            guard port.connectedOutlets.isEmpty else { return }

            guard let value = port.value, value.isEmpty == false else { return }

            guard let sourceURL = graph.resolveFileReference(value) else
            {
                throw DocumentBundleExportError.unresolvedReference(value)
            }

            guard fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)) else
            {
                throw DocumentBundleExportError.missingAsset(sourceURL)
            }

            let basename = sourceURL.lastPathComponent
            let collisionKey = basename.lowercased()
            if let existingSourceURL = sourceByBasename[collisionKey],
               existingSourceURL.standardizedFileURL != sourceURL.standardizedFileURL
            {
                throw DocumentBundleExportError.basenameCollision(name: basename,
                                                                  first: existingSourceURL,
                                                                  second: sourceURL)
            }

            sourceByBasename[collisionKey] = sourceURL
            references.append(AssetReference(
                portID: port.id,
                sourceURL: sourceURL,
                bundledPath: "\(self.assetsDirectoryName)/\(basename)"
            ))
        }

        return references
    }

    private static func clone(_ graph: Graph) throws -> Graph
    {
        let data = try JSONEncoder().encode(graph)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: graph.context,
                                         fileReferenceBaseURL: graph.fileReferenceBaseURL)
        return try decoder.decode(Graph.self, from: data)
    }

    private static func rewrite(_ references: [AssetReference], in graph: Graph) throws
    {
        var portByID: [UUID: ParameterPort<String>] = [:]
        try self.visitFileReferencePorts(in: graph) { port in
            portByID[port.id] = port
        }

        for reference in references
        {
            guard let port = portByID[reference.portID] else
            {
                throw DocumentBundleExportError.exportedPortMissing(reference.portID)
            }

            port.value = reference.bundledPath
        }
    }

    private static func visitFileReferencePorts(in graph: Graph,
                                                body: (ParameterPort<String>) throws -> Void) throws
    {
        for node in graph.nodes
        {
            for port in node.ports
            {
                guard let fileReferencePort = port as? ParameterPort<String>,
                      fileReferencePort.parameter?.controlType == .filepicker
                else { continue }

                try body(fileReferencePort)
            }

            if let subgraphNode = node as? SubgraphNode
            {
                try self.visitFileReferencePorts(in: subgraphNode.subGraph, body: body)
            }
        }
    }
}
