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
    let node: LocalLLMNode

    var body: some View {
        LocalModelNodeSettingsPanel(
            curatedModels: self.node.availableModels,
            selectedModelID: self.node.settingBinding(\LocalLLMSettings.selectedModelID),
            temperature: self.node.settingBinding(\LocalLLMSettings.temperature),
            updateIntervalSeconds: self.node.settingBinding(\LocalLLMSettings.updateIntervalSeconds),
            systemPromptOverride: self.node.settingBinding(\LocalLLMSettings.systemPromptOverride),
            chatModeEnabled: self.node.settingBinding(\LocalLLMSettings.chatModeEnabled),
            desiredMaxContextTokens: self.node.settingBinding(\LocalLLMSettings.desiredMaxContextTokens),
            effectiveMaxContextTokens: self.node.effectiveMaxContextTokens,
            runtimeState: self.node.modelRuntimeState,
            supportsImageInput: false,
            loadModel: self.node.loadModel,
            cancelModelOperation: self.node.cancelModelOperation,
            clearConversation: self.node.clearConversation
        )
    }
}

@Observable public class LocalLLMNode: Node, LocalModelSettingsMirroring {
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

    public var inputPrompt: NodePort<String> { _inputPrompt }
    private var _inputPrompt: NodePort<String>!
    public var inputGenerate: NodePort<Bool> { _inputGenerate }
    private var _inputGenerate: NodePort<Bool>!
    public var outputPort: NodePort<String> { _outputPort }
    private var _outputPort: NodePort<String>!
    public var outputStats: NodePort<String> { _outputStats }
    private var _outputStats: NodePort<String>!
    public var outputModel: NodePort<String> { _outputModel }
    private var _outputModel: NodePort<String>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputPrompt = findPort(named: "inputPrompt")
        self._inputGenerate = findPort(named: "inputGenerate")
        self._outputPort = findPort(named: "outputPort")
        self._outputStats = findPort(named: "outputStats")
        self._outputModel = findPort(named: "outputModel")
    }

    private enum CodingKeys: String, CodingKey {
        case selectedModelID
        case temperature
        case updateIntervalSeconds
        case systemPromptOverride
        case chatModeEnabled
        case desiredMaxContextTokens
    }

    public internal(set) var selectedModelID = LLMRegistry.qwen3_1_7b_4bit.name

    public internal(set) var temperature: Float = 0.6

    public internal(set) var updateIntervalSeconds: Float = 0.25

    public internal(set) var systemPromptOverride = ""

    public internal(set) var chatModeEnabled = true

    public internal(set) var desiredMaxContextTokens = 4_096

    public var activityText = ""
    public var isGenerating = false
    private var modelAcquisitionState: LocalModelRuntimeState = .unloaded
    private var generationError: String?
    var availableModels: [LocalModelCatalogEntry] = []

    @ObservationIgnored private let llmEvaluator = LLMEvaluator()
    @ObservationIgnored private var catalogMetadataTask: Task<Void, Never>?
    @ObservationIgnored private var modelStateObservationTask: Task<Void, Never>?
    @ObservationIgnored private var previousGenerateSignal = false

    var modelRuntimeState: LocalModelRuntimeState {
        if let generationError {
            return .failed(message: generationError)
        }

        if self.isGenerating, self.modelAcquisitionState.isReady {
            return .generating
        }

        return self.modelAcquisitionState
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
        self.refreshAvailableModels()
        self.observeSelectedModelState()
    }

    public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedModelID = try container.decodeIfPresent(String.self, forKey: .selectedModelID) ?? LLMRegistry.qwen3_1_7b_4bit.name
        self.temperature = try container.decodeIfPresent(Float.self, forKey: .temperature) ?? 0.6
        self.updateIntervalSeconds = try container.decodeIfPresent(Float.self, forKey: .updateIntervalSeconds) ?? 0.25
        self.systemPromptOverride = try container.decodeIfPresent(String.self, forKey: .systemPromptOverride) ?? ""
        self.chatModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatModeEnabled) ?? true
        self.desiredMaxContextTokens = try container.decodeIfPresent(Int.self, forKey: .desiredMaxContextTokens) ?? 4_096

        self.configureEvaluatorBindings()
        self.applyEvaluatorConfiguration()
        self.refreshAvailableModels()
        self.observeSelectedModelState()
    }

    deinit {
        self.catalogMetadataTask?.cancel()
        self.modelStateObservationTask?.cancel()
    }

    public convenience init(context: Context, settings: LocalLLMSettings) {
        self.init(context: context)
        self.apply(settings)
    }

    override public var settings: (any NodeSettings)? { self.localModelSettings() as LocalLLMSettings }

    override public func apply(_ settings: any NodeSettings) {
        guard let settings = settings as? LocalLLMSettings else { return }
        let change = self.setLocalModelSettings(settings)

        if change.modelChanged { self.llmEvaluator.resetSessionState() }
        if change.modelChanged || change.inferenceChanged { self.applyEvaluatorConfiguration() }
        if change.inferenceChanged { self.llmEvaluator.clearConversation() }
        if change.modelChanged { self.observeSelectedModelState() }
        super.apply(settings)
    }

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView {
        AnyView(LocalLLMNodeSettingsView(node: self))
    }

    override public var settingsSize: SettingsViewSize { .Large }

    override public func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws {
        if self.inputPrompt.valueDidChange, let prompt = self.inputPrompt.value {
            self.llmEvaluator.prompt = prompt
        }

        let generateSignal = self.inputGenerate.value ?? false
        let shouldGenerate = self.inputGenerate.valueDidChange
            && generateSignal
            && self.previousGenerateSignal == false

        if self.inputGenerate.valueDidChange {
            self.previousGenerateSignal = generateSignal
        }

        if shouldGenerate {
            if let prompt = self.inputPrompt.value {
                self.llmEvaluator.prompt = prompt
            }

            self.llmEvaluator.generate()

            if self.inputGenerate.connections.isEmpty {
                self.inputGenerate.value = false
                self.previousGenerateSignal = false
            }
        }

        self.outputPort.send(self.llmEvaluator.output)
        self.outputStats.send(self.llmEvaluator.stat)
        self.outputModel.send(self.llmEvaluator.modelInfo)
    }

    override public func stopExecution(renderer: GraphRenderer) throws {
        self.llmEvaluator.cancelModelOperation()
        try super.stopExecution(renderer: renderer)
    }

    func clearConversation() {
        self.llmEvaluator.clearConversation()
    }

    func loadModel(_ modelID: String) {
        if self.selectedModelID != modelID {
            self.llmEvaluator.cancelModelOperation()
            var settings: LocalLLMSettings = self.localModelSettings()
            settings.selectedModelID = modelID
            self.setSettings(settings)
        }
        self.llmEvaluator.prepareModel()
    }

    func cancelModelOperation() {
        self.llmEvaluator.cancelModelOperation()
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

        self.llmEvaluator.onGenerationErrorChanged = { [weak self] generationError in
            Task { @MainActor in
                self?.generationError = generationError
            }
        }

        self.activityText = self.llmEvaluator.activityText
        self.isGenerating = self.llmEvaluator.running
        self.generationError = self.llmEvaluator.generationError
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

    private func refreshAvailableModels() {
        let configurations = Array(LLMRegistry.shared.models)
        self.availableModels = LocalModelRuntimeSupport.catalogEntries(
            for: configurations,
            family: .llm
        )

        self.catalogMetadataTask?.cancel()
        self.catalogMetadataTask = Task { @MainActor [weak self, configurations] in
            let metadata = await LocalModelMetadataCache.shared.metadata(
                for: configurations.map(\.name),
                family: .llm
            )
            guard Task.isCancelled == false else { return }

            let entries = LocalModelRuntimeSupport.catalogEntries(
                for: configurations,
                family: .llm,
                metadataByModelID: metadata
            )
            self?.availableModels = entries
        }
    }

    private func observeSelectedModelState() {
        let selectedModelID = self.selectedModelID
        self.modelStateObservationTask?.cancel()
        self.modelAcquisitionState = .unloaded
        self.modelStateObservationTask = Task { @MainActor [weak self] in
            let stateUpdates = await LocalModelContainerCache.shared.stateUpdates(
                family: .llm,
                modelID: selectedModelID
            )

            for await acquisitionState in stateUpdates {
                guard
                    Task.isCancelled == false,
                    let self,
                    self.selectedModelID == selectedModelID
                else {
                    return
                }

                self.modelAcquisitionState = acquisitionState
                if acquisitionState == .ready {
                    self.refreshAvailableModels()
                }
            }
        }
    }
}
