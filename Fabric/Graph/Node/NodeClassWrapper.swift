//
//  ClassWrapper.swift
//  v
//
//  Created by Anton Marini on 4/28/24.
//

import Foundation
import Satin
import UniformTypeIdentifiers
import CoreTransferable

public struct NodeClassWrapper: Identifiable
{
    public let id = UUID()
    public let nodeClass:Node.Type
    public let nodeType:Node.NodeType
    public var fileURL:URL? = nil
    public var nodeName:String

    // Specify a overridden node type for say, nodeType image with specific image types (effects)
    public init(nodeClass: Node.Type, nodeType:Node.NodeType? = nil, fileURL:URL? = nil, nodeName:String? = nil)
    {
        self.nodeClass = nodeClass
        self.nodeType = nodeType ?? nodeClass.nodeType
        self.fileURL = fileURL
        self.nodeName = nodeName ?? nodeClass.name
    }

    public func initializeNode(context:Context) throws -> Node
    {
        if let nodeClassFile = self.nodeClass as? (any NodeFileLoadingProtocol.Type),
           let fileURL = self.fileURL
        {
            return try nodeClassFile.init(context:context, fileURL: fileURL)
        }

        return  self.nodeClass.init(context:context)
    }
}

/// Drag-and-drop payload for node registry items.
public struct NodeRegistryDragData: Codable, Transferable
{
    public let wrapperID: UUID

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .nodeRegistryItem)
    }
}

extension UTType
{
    /// The host app's Info.plist must declare this identifier under UTExportedTypeDeclarations
    /// (conforming to public.data) or drag-and-drop will be silently rejected at runtime.
    public static var nodeRegistryItem: UTType { UTType(exportedAs: "info.vade.fabric.node-registry-item") }
}


