//
//  LLMNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/20/25.
//

import Foundation
import Satin
import simd
import Metal

public class LocalLLMNode : Node
{
    override public static var name:String { "Local LLM Node" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide a string prompt to a local LLM for evaluation via MLX-LLM"}

    // TODO: add character set menu to choose component separation strategy
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort", ParameterPort(parameter: StringParameter("Prompt", "What Color is the Sky?", [], .inputfield))),
            ("outputPort", NodePort<String>(name: "Output", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<String> { port(named: "inputPort") }
    public var outputPort:NodePort<String> { port(named: "outputPort") }

    private var llmEvaluator = LLMEvaluator()
    
    public required init(context: Context)
    {
        super.init(context: context)
        
        Task {
            try await self.llmEvaluator.load()
        }
    }
    
    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange
        {
            if let string = self.inputPort.value
            {
                self.llmEvaluator.prompt = string
                self.llmEvaluator.generate()
                
            }
        }
        
        self.outputPort.send(self.llmEvaluator.output)
    }
}
