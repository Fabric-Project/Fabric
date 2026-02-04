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
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Load a Plaintext file and output a String"}
        
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("Text File", "", .filepicker, "Path to the text file to load"))),
            ("outputPort", NodePort<String>(name: "Text", kind: .Outlet, description: "Contents of the loaded text file")),
        ]
    }
    
    // Port Proxy
    public var inputFilePathParam:ParameterPort<String> { port(named: "inputFilePathParam") }
    public var outputPort:NodePort<String> { port(named: "outputPort") }

    private var url:URL? = nil
    private var string: String? = nil
    
    
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
            
//            else
//            {
//                self.outputPort.send( nil )
//            }
        }
    }
    
    private func loadStringFromURL()
    {
        if let path = self.inputFilePathParam.value,
           path.isEmpty == false && self.url != URL(string: path)
        {
            self.url = URL(string: path)
            
            if FileManager.default.fileExists(atPath: self.url!.standardizedFileURL.path(percentEncoded: false) )
            {
                self.string = try? String(contentsOfFile: self.url!.path, encoding: .utf8)
            }
        }
        
    }
}
