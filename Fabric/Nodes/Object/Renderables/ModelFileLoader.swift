//
//  ModelFileLoader.swift
//  Fabric
//
//  Created by Toby Harris on 10/13/26.
//

import Foundation
import Satin
import MetalKit
import ModelIO

/// Loads the model file a node's File Path port names, for Model Mesh and
/// Instanced Model Mesh, and holds why a file gave no model as the node's
/// status. The node owns the model it is handed.
final class ModelFileLoader
{
    enum Outcome
    {
        /// The file the node's model already came from.
        case unchanged
        /// The file's model: flattened when still; when animated, with its
        /// hierarchy and the animation that moves it.
        case loaded(Object, animation: AssetAnimation?)
        /// No file is named, or the file gave no model. The error is the
        /// node's to throw; nil when there is none to throw.
        case noModel(throwing: FabricError?)
    }

    /// Why the named file gave no model; nil once one loads or none is named.
    /// An error's message is the one the node throws.
    private(set) var status: NodeStatus?

    /// Whether the model's meshes are InstancedMeshes, for Instanced Model Mesh.
    private let instanced: Bool

    private var textureLoader: MTKTextureLoader?

    /// The file the node's model came from. Nil after a failure, so naming
    /// the same file again retries the load.
    private var loadedURL: URL?

    init(instanced: Bool = false)
    {
        self.instanced = instanced
    }

    func load(path: String?, for node: Node) -> Outcome
    {
        let statusBefore = self.status
        let outcome = self.outcome(path: path, for: node)
        if self.status != statusBefore
        {
            node.subtitleSubject.send()
        }
        return outcome
    }

    private func outcome(path: String?, for node: Node) -> Outcome
    {
        guard let path, path.isEmpty == false else
        {
            self.loadedURL = nil
            self.status = nil
            return .noModel(throwing: nil)
        }

        guard let url = node.graph?.resolveFileReference(path)
            ?? DocumentFileReference.resolve(path, relativeTo: nil) else
        {
            return self.fail(.fileNotFound, message: "Model file path is invalid: \(path)")
        }

        guard self.loadedURL != url else { return .unchanged }

        guard FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false)) else
        {
            return self.fail(.fileNotFound, message: "Model file not found: \(url.path)")
        }

        guard MDLAsset.canImportFileExtension(url.pathExtension) else
        {
            return self.fail(.failed, message: "Model files of type .\(url.pathExtension) cannot be imported: \(url.path)")
        }

        let textureLoader = self.textureLoader ?? MTKTextureLoader(device: node.context.device)
        self.textureLoader = textureLoader

        // An animated model keeps its hierarchy, since animated objects and skeleton
        // anchors move the meshes within it; a still one is flattened. Either is
        // empty when ModelIO could read nothing from the file.
        let loadedAsset = loadAnimatedAsset(url: url, context: node.context, textureLoader: textureLoader, instanced: self.instanced)
        let root = loadedAsset.animation == nil ? Object.flatten(loadedAsset.root) : loadedAsset.root

        guard root.getChildren(true).contains(where: { $0 is Mesh }) else
        {
            self.loadedURL = nil
            self.status = .warning("No mesh found in model file: \(url.path)")
            return .noModel(throwing: nil)
        }

        self.loadedURL = url
        self.status = nil
        return .loaded(root, animation: loadedAsset.animation)
    }

    private func fail(_ kind: FabricErrorKind.Execution, message: String) -> Outcome
    {
        self.loadedURL = nil
        self.status = .error(message)
        return .noModel(throwing: FabricError(.execution(kind), severity: .recoverable, message: message))
    }
}
