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
internal import MLX
internal import MLXLLM
internal import MLXLMCommon

public class LocalLLMNode : Node
{
    override public static var name:String { "Local LLM Node" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide a string prompt to a local LLM for evaluation via MLX-LLM"}
    
    // Models download to ~/.cache/huggingface/hub/
    
    
    // TODO: add character set menu to choose component separation strategy
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        let defaultModelName =  LLMRegistry.qwen3_1_7b_4bit.name
        let models = LLMRegistry.shared.models.map(\.name)
        return ports +

        [
            ("inputModel", ParameterPort(parameter: StringParameter("Model", defaultModelName, models, .dropdown))),
            ("inputPrompt", ParameterPort(parameter: StringParameter("Prompt", "What Color is the Sky?", [], .inputfield))),
            ("inputGenerate", ParameterPort(parameter: BoolParameter("Generate", false, .button))),
            ("outputPort", NodePort<String>(name: "Output", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputModel:NodePort<String> { port(named: "inputModel") }
    public var inputPrompt:NodePort<String> { port(named: "inputPrompt") }
    public var inputGenerate:NodePort<Bool> { port(named: "inputGenerate") }
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
        if self.inputModel.valueDidChange,
           let name = self.inputModel.value,
           let modelConfig = LLMRegistry.shared.models.first(where: { $0.name == name })
        {
            self.llmEvaluator.modelConfiguration = modelConfig
            
            Task {
                try await self.llmEvaluator.load()
            }
            
        }
        
        if self.inputPrompt.valueDidChange
        {
            if let string = self.inputPrompt.value
            {
                self.llmEvaluator.prompt = string
            }
        }

        if self.inputGenerate.valueDidChange
            && self.inputGenerate.value == true
        {
            self.llmEvaluator.cancelGeneration()
            
            self.llmEvaluator.generate()
        }
        
        self.outputPort.send(self.llmEvaluator.output)
    }
}
