//
//  ClassWrapper.swift
//  v
//
//  Created by Anton Marini on 4/28/24.
//

import Foundation
import Satin

public struct NodeClassWrapper: Identifiable
{
    public let id = UUID()
    public let nodeClass:Node.Type
    public let nodeType:Node.NodeType
    public var fileURL:URL? = nil
    public var nodeName:String

    /// Bundle identifier of the plugin that provides this node, if any.
    /// nil for built-in nodes.
    public var pluginBundleID: String? = nil

    /// Returns true if this node comes from a plugin rather than being built-in.
    public var isPluginNode: Bool { pluginBundleID != nil }

    // Specify a overridden node type for say, nodeType image with specific image types (effects)
    public init(nodeClass: Node.Type, nodeType:Node.NodeType? = nil, fileURL:URL? = nil, nodeName:String? = nil, pluginBundleID: String? = nil)
    {
        self.nodeClass = nodeClass
        self.nodeType = nodeType ?? nodeClass.nodeType
        self.fileURL = fileURL
        self.nodeName = nodeName ?? nodeClass.name
        self.pluginBundleID = pluginBundleID
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


