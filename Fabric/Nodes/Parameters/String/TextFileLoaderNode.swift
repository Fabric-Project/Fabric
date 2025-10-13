//
//  TextFileLoader.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class TextFileLoaderNode : Node
{
    override public static var name:String { "Text File Loader" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }

    let inputFilePathParam:StringParameter
    override public var inputParameters: [any Parameter] { [self.inputFilePathParam] + super.inputParameters}

    let outputPort:NodePort<String>
    override public var ports: [any NodePortProtocol] {  [outputPort] + super.ports}

    private var url: URL? = nil
    private var string: String? = nil
    
    required public init(context:Context)
    {
        self.inputFilePathParam = StringParameter("Text File", "", .filepicker)
        self.outputPort = NodePort<String>(name: "String", kind: .Outlet)
        
        super.init(context: context)
        
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputFilePathParameter
        case outputPort
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputFilePathParam, forKey: .inputFilePathParameter)
        try container.encode(self.outputPort, forKey: .outputPort)

        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
       
        self.inputFilePathParam = try container.decode(StringParameter.self, forKey: .inputFilePathParameter)
        self.outputPort = try container.decode(NodePort<String>.self, forKey: .outputPort)
        
        try super.init(from:decoder)
        
        self.loadStringFromURL()
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
   
    {
        if self.inputFilePathParam.valueDidChange
        {
            self.loadStringFromURL()
            
            if let string = self.string
            {
                self.outputPort.send( string )
            }
            
            else
            {
                self.outputPort.send( nil )
            }
        }
    }
    
    private func loadStringFromURL()
    {
        if  self.inputFilePathParam.value.isEmpty == false && self.url != URL(string: self.inputFilePathParam.value)
        {
            self.url = URL(string: self.inputFilePathParam.value)
            
            if FileManager.default.fileExists(atPath: self.url!.standardizedFileURL.path(percentEncoded: false) )
            {
                self.string = try? String(contentsOfFile: self.url!.path, encoding: .utf8)
            }
        }
        
    }
}
