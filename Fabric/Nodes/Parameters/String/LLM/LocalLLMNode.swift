//
//  LLMNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/20/25.
//

import Foundation
import Metal
import Satin
import SwiftUI
import simd
internal import MLXLLM
internal import MLXLMCommon

struct LocalLLMNodeSettingsView: View {
    @Bindable var node: LocalLLMNode

    var body: some View {
        LocalModelNodeSettingsPanel(
            curatedModels: self.node.availableModels,
            selectedModelID: self.$node.selectedModelID,
            temperature: self.$node.temperature,
            updateIntervalSeconds: self.$node.updateIntervalSeconds,
            systemPromptOverride: self.$node.systemPromptOverride,
            chatModeEnabled: self.$node.chatModeEnabled,
            desiredMaxContextTokens: self.$node.desiredMaxContextTokens,
            effectiveMaxContextTokens: self.node.effectiveMaxContextTokens,
            activityText: self.node.activityText,
            supportsImageInput: false,
            clearConversation: self.node.clearConversation
        )
    }
}

@Observable public class LocalLLMNode: Node {
    override public static var name: String { "Local LLM Node" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide a string prompt to a local LLM for evaluation via MLX-Swift-LM" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        super.registerPorts(context: context) + [
            ("inputPrompt", ParameterPort(parameter: StringParameter("Prompt", "What color is the sky?", [], .inputfield))),
            ("inputGenerate", ParameterPort(parameter: BoolParameter("Generate", false, .button))),
            ("outputPort", NodePort<String>(name: "Output", kind: .Outlet)),
            ("outputStats", NodePort<String>(name: "Stats", kind: .Outlet)),
            ("outputModel", NodePort<String>(name: "Model Info", kind: .Outlet)),
        ]
    }

    public var inputPrompt: NodePort<String> { port(named: "inputPrompt") }
    public var inputGenerate: NodePort<Bool> { port(named: "inputGenerate") }
    public var outputPort: NodePort<String> { port(named: "outputPort") }
    public var outputStats: NodePort<String> { port(named: "outputStats") }
    public var outputModel: NodePort<String> { port(named: "outputModel") }

    private enum CodingKeys: String, CodingKey {
        case selectedModelID
        case temperature
        case updateIntervalSeconds
        case systemPromptOverride
        case chatModeEnabled
        case desiredMaxContextTokens
    }

    public var selectedModelID = LLMRegistry.qwen3_1_7b_4bit.name {
        didSet {
            self.didUpdateModelSettings()
        }
    }

    public var temperature: Float = 0.6 {
        didSet {
            self.didUpdateInferenceSettings()
        }
    }

    public var updateIntervalSeconds: Float = 0.25 {
        didSet {
            self.didUpdateInferenceSettings()
        }
    }

    public var systemPromptOverride = "" {
        didSet {
            self.didUpdateInferenceSettings()
        }
    }

    public var chatModeEnabled = true {
        didSet {
            self.didUpdateInferenceSettings()
        }
    }

    public var desiredMaxContextTokens = 4_096 {
        didSet {
            self.didUpdateInferenceSettings()
        }
    }

    public var activityText = ""
    public var isGenerating = false

    @ObservationIgnored private var suppressSettingSideEffects = false
    @ObservationIgnored private let llmEvaluator = LLMEvaluator()

    var availableModels: [LocalModelCatalogEntry] {
        LocalModelRuntimeSupport.catalogEntries(for: Array(LLMRegistry.shared.models))
    }

    public var effectiveMaxContextTokens: Int {
        LocalModelRuntimeSupport.effectiveContextTokenLimit(
            for: self.selectedModelID,
            desired: self.desiredMaxContextTokens
        )
    }

    public required init(context: Context) {
        super.init(context: context)
        self.configureEvaluatorBindings()
        self.applyEvaluatorConfiguration()
    }

    public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.suppressSettingSideEffects = true
        self.selectedModelID = try container.decodeIfPresent(String.self, forKey: .selectedModelID) ?? LLMRegistry.qwen3_1_7b_4bit.name
        self.temperature = try container.decodeIfPresent(Float.self, forKey: .temperature) ?? 0.6
        self.updateIntervalSeconds = try container.decodeIfPresent(Float.self, forKey: .updateIntervalSeconds) ?? 0.25
        self.systemPromptOverride = try container.decodeIfPresent(String.self, forKey: .systemPromptOverride) ?? ""
        self.chatModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatModeEnabled) ?? true
        self.desiredMaxContextTokens = try container.decodeIfPresent(Int.self, forKey: .desiredMaxContextTokens) ?? 4_096
        self.suppressSettingSideEffects = false

        self.configureEvaluatorBindings()
        self.applyEvaluatorConfiguration()
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.selectedModelID, forKey: .selectedModelID)
        try container.encode(self.temperature, forKey: .temperature)
        try container.encode(self.updateIntervalSeconds, forKey: .updateIntervalSeconds)
        try container.encode(self.systemPromptOverride, forKey: .systemPromptOverride)
        try container.encode(self.chatModeEnabled, forKey: .chatModeEnabled)
        try container.encode(self.desiredMaxContextTokens, forKey: .desiredMaxContextTokens)
    }

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView {
        AnyView(LocalLLMNodeSettingsView(node: self))
    }

    override public var settingsSize: SettingsViewSize { .Large }

    override public func execute(
        context: GraphExecutionContext,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) {
        if self.inputPrompt.valueDidChange, let prompt = self.inputPrompt.value {
            self.llmEvaluator.prompt = prompt
        }

        if self.inputGenerate.valueDidChange || self.inputPrompt.valueDidChange {
            if self.inputGenerate.value == true {
                if let prompt = self.inputPrompt.value {
                    self.llmEvaluator.prompt = prompt
                }

                self.llmEvaluator.generate()
            } else {
                self.llmEvaluator.cancelGeneration()
            }
        }

        self.outputPort.send(self.llmEvaluator.output)
        self.outputStats.send(self.llmEvaluator.stat)
        self.outputModel.send(self.llmEvaluator.modelInfo)
    }

    override public func stopExecution(context: GraphExecutionContext) {
        self.llmEvaluator.cancelGeneration()
        super.stopExecution(context: context)
    }

    func clearConversation() {
        self.llmEvaluator.clearConversation()
    }

    private func configureEvaluatorBindings() {
        self.llmEvaluator.onActivityTextChanged = { [weak self] activityText in
            Task { @MainActor in
                self?.activityText = activityText
            }
        }

        self.llmEvaluator.onRunningChanged = { [weak self] running in
            Task { @MainActor in
                self?.isGenerating = running
            }
        }

        self.activityText = self.llmEvaluator.activityText
        self.isGenerating = self.llmEvaluator.running
    }

    private func didUpdateModelSettings() {
        guard self.suppressSettingSideEffects == false else { return }
        self.llmEvaluator.resetSessionState()
        self.applyEvaluatorConfiguration()
    }

    private func didUpdateInferenceSettings() {
        guard self.suppressSettingSideEffects == false else { return }
        self.applyEvaluatorConfiguration()
        self.llmEvaluator.clearConversation()
    }

    private func applyEvaluatorConfiguration() {
        let modelConfiguration = LLMRegistry.shared.configuration(id: self.selectedModelID)
        self.llmEvaluator.modelConfiguration = modelConfiguration
        self.llmEvaluator.systemPromptOverride = self.systemPromptOverride
        self.llmEvaluator.chatModeEnabled = self.chatModeEnabled
        self.llmEvaluator.generateParameters = GenerateParameters(
            maxKVSize: self.effectiveMaxContextTokens,
            temperature: self.temperature
        )
        self.llmEvaluator.updateInterval = .seconds(Double(self.updateIntervalSeconds))

        if self.inputPrompt.value == nil || self.inputPrompt.value?.isEmpty == true {
            self.inputPrompt.value = modelConfiguration.defaultPrompt
            self.llmEvaluator.prompt = modelConfiguration.defaultPrompt
        }
    }
}
