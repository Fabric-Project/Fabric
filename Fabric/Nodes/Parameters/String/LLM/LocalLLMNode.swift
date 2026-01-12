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
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
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
            ("inputTemp", ParameterPort(parameter: FloatParameter("Temerature", 0.6, .inputfield))),
            ("inputUpdateInterval", ParameterPort(parameter: FloatParameter("Update Interval", 0.25, .inputfield))),
            ("outputPort", NodePort<String>(name: "Output", kind: .Outlet)),
            ("outputStats", NodePort<String>(name: "Stats", kind: .Outlet)),
            ("outputModel", NodePort<String>(name: "Model Info", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputModel:NodePort<String> { port(named: "inputModel") }
    public var inputPrompt:NodePort<String> { port(named: "inputPrompt") }
    public var inputGenerate:NodePort<Bool> { port(named: "inputGenerate") }
    public var inputTemp:NodePort<Float> { port(named: "inputTemp") }
    public var inputUpdateInterval:NodePort<Float> { port(named: "inputUpdateInterval") }
    public var outputPort:NodePort<String> { port(named: "outputPort") }
    public var outputStats:NodePort<String> { port(named: "outputStats") }
    public var outputModel:NodePort<String> { port(named: "outputModel") }

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
            self.llmEvaluator.generateParameters = GenerateParameters( temperature: self.inputTemp.value ?? 0.6 )
            self.llmEvaluator.updateInterval = Duration.seconds( Double(self.inputUpdateInterval.value ?? 0.25 ))
//            self.llmEvaluator.enableThinking = true
//            self.llmEvaluator.generateParameters = GenerateParameters()

            Task {
                try await self.llmEvaluator.load()
            }
        }

        // Can these change during runtime? 
        if self.inputUpdateInterval.valueDidChange
        {
            self.llmEvaluator.updateInterval = Duration.seconds( Double(self.inputUpdateInterval.value ?? 0.25 ))
        }
        
        if self.inputTemp.valueDidChange
        {
            self.llmEvaluator.generateParameters = GenerateParameters( temperature: self.inputTemp.value ?? 0.6 )
        }
        
        if self.inputPrompt.valueDidChange
        {
            if let string = self.inputPrompt.value
            {
                print("Setting LLM Prompt to: \(string)")
                self.llmEvaluator.prompt = string
            }
        }

        if self.inputGenerate.valueDidChange || self.inputPrompt.valueDidChange
        {
            if self.inputGenerate.value == true
            {
                self.llmEvaluator.cancelGeneration()
                
                if let string = self.inputPrompt.value
                {
                    self.llmEvaluator.prompt = string
                }

                print("Evaluating LLM with \(self.llmEvaluator.prompt)")

                self.llmEvaluator.generate()
            }
            else
            {
                self.llmEvaluator.cancelGeneration()
            }
        }
        
        self.outputPort.send(self.llmEvaluator.output)
        self.outputStats.send(self.llmEvaluator.stat)
        self.outputModel.send(self.llmEvaluator.modelInfo)
    }
}
