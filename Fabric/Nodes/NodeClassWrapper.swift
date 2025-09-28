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
    public var fileURL:URL? = nil
    public var nodeName:String
    public init(nodeClass: any NodeProtocol.Type, fileURL:URL? = nil, nodeName:String? = nil)
    {
        self.nodeClass = nodeClass
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


