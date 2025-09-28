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
    public let nodeClass: any NodeProtocol.Type
    public let nodeType:Node.NodeType
    public var fileURL:URL? = nil
    public var nodeName:String
    
    // Specify a overriden node type for say, nodeType image with specific image types (effects)
    public init(nodeClass: any NodeProtocol.Type, nodeType:Node.NodeType? = nil, fileURL:URL? = nil, nodeName:String? = nil)
    {
        self.nodeClass = nodeClass
        self.nodeType = nodeType ?? nodeClass.nodeType
        self.fileURL = fileURL
        self.nodeName = nodeName ?? nodeClass.name
    }
    
    public func initializeNode(context:Context) throws -> any NodeProtocol
    {
        if let nodeClassFile = self.nodeClass as? (any NodeFileLoadingProtocol.Type),
           let fileURL = self.fileURL
        {
            return try nodeClassFile.init(context:context, fileURL: fileURL)
        }
        
        return  self.nodeClass.init(context:context)
    }
}


