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
import CoreImage
internal import MLX
internal import MLXLLM
internal import MLXVLM
internal import MLXLMCommon

public class LocalVLMNode : Node
{
    override public static var name:String { "Local VLM Node" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide a string prompt to a local VLLM for evaluation via MLX-Swift-LM"}
    
    // Models download to ~/.cache/huggingface/hub/
    
    // TODO: add character set menu to choose component separation strategy
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        let defaultModelName =  VLMRegistry.smolvlm.name
        let models = VLMRegistry.shared.models.map(\.name)
        return ports +

        [
            ("inputModel", ParameterPort(parameter: StringParameter("Model", defaultModelName, models, .dropdown, "Vision language model to use"))),
            ("inputPrompt", ParameterPort(parameter: StringParameter("Prompt", "Describe this image?", [], .inputfield, "Text prompt to send to the model"))),
            ("inputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Image to analyze with the VLM")),
            ("inputGenerate", ParameterPort(parameter: BoolParameter("Generate", false, .button, "Trigger text generation"))),
            ("inputTemp", ParameterPort(parameter: FloatParameter("Temerature", 0.6, .inputfield, "Sampling temperature (higher = more creative)"))),
            ("inputUpdateInterval", ParameterPort(parameter: FloatParameter("Update Interval", 0.25, .inputfield, "Interval in seconds between output updates"))),
            ("outputPort", NodePort<String>(name: "Output", kind: .Outlet, description: "Generated text response")),
            ("outputStats", NodePort<String>(name: "Stats", kind: .Outlet, description: "Generation statistics")),
            ("outputModel", NodePort<String>(name: "Model Info", kind: .Outlet, description: "Current model information")),
        ]
    }
    
    // Port Proxy
    public var inputModel:NodePort<String> { port(named: "inputModel") }
    public var inputPrompt:NodePort<String> { port(named: "inputPrompt") }
    public var inputTexturePort:NodePort<FabricImage>  { port(named: "inputTexturePort") }
    public var inputGenerate:NodePort<Bool> { port(named: "inputGenerate") }
    public var inputTemp:NodePort<Float> { port(named: "inputTemp") }
    public var inputUpdateInterval:NodePort<Float> { port(named: "inputUpdateInterval") }
    public var outputPort:NodePort<String> { port(named: "outputPort") }
    public var outputStats:NodePort<String> { port(named: "outputStats") }
    public var outputModel:NodePort<String> { port(named: "outputModel") }

    private var vlmEvaluator = VLMEvaluator()
    
    public required init(context: Context)
    {
        super.init(context: context)
        
        Task {
            try await self.vlmEvaluator.load()
        }
    }
    
    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }
    
    override public func stopExecution(context: GraphExecutionContext) {
        
        self.vlmEvaluator.cancelGeneration()

        super.stopExecution(context: context)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputModel.valueDidChange,
           let name = self.inputModel.value,
           let modelConfig = LLMRegistry.shared.models.first(where: { $0.name == name })
        {
            self.vlmEvaluator.modelConfiguration = modelConfig
            self.vlmEvaluator.generateParameters = GenerateParameters(maxTokens: 100, temperature: self.inputTemp.value ?? 0.6 , )
            self.vlmEvaluator.updateInterval = Duration.seconds( Double(self.inputUpdateInterval.value ?? 0.25 ))
//            self.llmEvaluator.enableThinking = true
//            self.llmEvaluator.generateParameters = GenerateParameters()

            Task {
                try await self.vlmEvaluator.load()
            }
        }

        // Can these change during runtime? 
        if self.inputUpdateInterval.valueDidChange
        {
            self.vlmEvaluator.updateInterval = Duration.seconds( Double(self.inputUpdateInterval.value ?? 0.25 ))
        }
        
        if self.inputTemp.valueDidChange
        {
            self.vlmEvaluator.generateParameters = GenerateParameters( temperature: self.inputTemp.value ?? 0.6 )
        }
        
        if self.inputPrompt.valueDidChange
        {
            if let string = self.inputPrompt.value
            {
                print("Setting LLM Prompt to: \(string)")
                self.vlmEvaluator.prompt = string
            }
        }

        if self.inputGenerate.valueDidChange || self.inputPrompt.valueDidChange || self.inputTexturePort.valueDidChange
        {
            if self.inputGenerate.value == true && !self.vlmEvaluator.running
            {
                if let string = self.inputPrompt.value
                {
                    self.vlmEvaluator.prompt = string
                }
                
                var image:CIImage? = nil
                
                if let fabricImage = self.inputTexturePort.value
                {
                    image = CIImage(mtlTexture: fabricImage.texture)
                }
                
                print("Evaluating LLM with \(self.vlmEvaluator.prompt)")

                self.vlmEvaluator.generate(image:image )
            }
//            else
//            {
//                self.vlmEvaluator.cancelGeneration()
//            }
        }
        
        self.outputPort.send(self.vlmEvaluator.output)
        self.outputStats.send(self.vlmEvaluator.stat)
        self.outputModel.send(self.vlmEvaluator.modelInfo)
    }
}
