//
//  LLMNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/20/25.
//

import CoreImage
import Foundation
import Metal
import Satin
import SwiftUI
import simd
internal import MLXVLM
internal import MLXLMCommon

struct LocalVLMNodeSettingsView: View {
    @Bindable var node: LocalVLMNode

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
            runtimeState: self.node.modelRuntimeState,
            supportsImageInput: true,
            loadModel: self.node.loadModel,
            cancelModelOperation: self.node.cancelModelOperation,
            clearConversation: self.node.clearConversation
        )
    }
}

@Observable public class LocalVLMNode: Node {
    override public static var name: String { "Local VLM Node" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide a string prompt to a local VLLM for evaluation via MLX-Swift-LM" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        super.registerPorts(context: context) + [
            ("inputPrompt", ParameterPort(parameter: StringParameter("Prompt", "Describe this image?", [], .inputfield, "Text prompt to send to the model"))),
            ("inputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Image to analyze with the VLM")),
            ("inputGenerate", ParameterPort(parameter: BoolParameter("Generate", false, .button, "Trigger text generation"))),
            ("outputPort", NodePort<String>(name: "Output", kind: .Outlet, description: "Generated text response")),
            ("outputStats", NodePort<String>(name: "Stats", kind: .Outlet, description: "Generation statistics")),
            ("outputModel", NodePort<String>(name: "Model Info", kind: .Outlet, description: "Current model information")),
        ]
    }

    public var inputPrompt: NodePort<String> { port(named: "inputPrompt") }
    public var inputTexturePort: NodePort<FabricImage> { port(named: "inputTexturePort") }
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

    public var selectedModelID = VLMRegistry.smolvlm.name {
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
    private var modelAcquisitionState: LocalModelRuntimeState = .unloaded
    private var generationError: String?
    var availableModels: [LocalModelCatalogEntry] = []

    @ObservationIgnored private var suppressSettingSideEffects = false
    @ObservationIgnored private let vlmEvaluator = VLMEvaluator()
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
        self.suppressSettingSideEffects = true
        self.selectedModelID = try container.decodeIfPresent(String.self, forKey: .selectedModelID) ?? VLMRegistry.smolvlm.name
        self.temperature = try container.decodeIfPresent(Float.self, forKey: .temperature) ?? 0.6
        self.updateIntervalSeconds = try container.decodeIfPresent(Float.self, forKey: .updateIntervalSeconds) ?? 0.25
        self.systemPromptOverride = try container.decodeIfPresent(String.self, forKey: .systemPromptOverride) ?? ""
        self.chatModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatModeEnabled) ?? true
        self.desiredMaxContextTokens = try container.decodeIfPresent(Int.self, forKey: .desiredMaxContextTokens) ?? 4_096
        self.suppressSettingSideEffects = false

        self.configureEvaluatorBindings()
        self.applyEvaluatorConfiguration()
        self.refreshAvailableModels()
        self.observeSelectedModelState()
    }

    deinit {
        self.catalogMetadataTask?.cancel()
        self.modelStateObservationTask?.cancel()
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
        AnyView(LocalVLMNodeSettingsView(node: self))
    }

    override public var settingsSize: SettingsViewSize { .Custom(size: .init(width: 700, height: 600)) }

    override public func stopExecution(renderer: GraphRenderer) throws {
        self.vlmEvaluator.cancelModelOperation()
        try super.stopExecution(renderer: renderer)
    }

    override public func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws {
        if self.inputPrompt.valueDidChange, let prompt = self.inputPrompt.value {
            self.vlmEvaluator.prompt = prompt
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
                self.vlmEvaluator.prompt = prompt
            }

            let image = self.inputTexturePort.value.map { CIImage(mtlTexture: $0.texture) }.flatMap { $0 }
            self.vlmEvaluator.generate(image: image)

            if self.inputGenerate.connections.isEmpty {
                self.inputGenerate.value = false
                self.previousGenerateSignal = false
            }
        }

        self.outputPort.send(self.vlmEvaluator.output)
        self.outputStats.send(self.vlmEvaluator.stat)
        self.outputModel.send(self.vlmEvaluator.modelInfo)
    }

    func clearConversation() {
        self.vlmEvaluator.clearConversation()
    }

    func loadModel(_ modelID: String) {
        if self.selectedModelID != modelID {
            self.vlmEvaluator.cancelModelOperation()
            self.selectedModelID = modelID
        }
        self.vlmEvaluator.prepareModel()
    }

    func cancelModelOperation() {
        self.vlmEvaluator.cancelModelOperation()
    }

    private func configureEvaluatorBindings() {
        self.vlmEvaluator.onActivityTextChanged = { [weak self] activityText in
            Task { @MainActor in
                self?.activityText = activityText
            }
        }

        self.vlmEvaluator.onRunningChanged = { [weak self] running in
            Task { @MainActor in
                self?.isGenerating = running
            }
        }

        self.vlmEvaluator.onGenerationErrorChanged = { [weak self] generationError in
            Task { @MainActor in
                self?.generationError = generationError
            }
        }

        self.activityText = self.vlmEvaluator.activityText
        self.isGenerating = self.vlmEvaluator.running
        self.generationError = self.vlmEvaluator.generationError
    }

    private func didUpdateModelSettings() {
        guard self.suppressSettingSideEffects == false else { return }
        self.vlmEvaluator.resetSessionState()
        self.applyEvaluatorConfiguration()
        self.observeSelectedModelState()
    }

    private func didUpdateInferenceSettings() {
        guard self.suppressSettingSideEffects == false else { return }
        self.applyEvaluatorConfiguration()
        self.vlmEvaluator.clearConversation()
    }

    private func applyEvaluatorConfiguration() {
        let modelConfiguration = VLMRegistry.shared.configuration(id: self.selectedModelID)
        self.vlmEvaluator.modelConfiguration = modelConfiguration
        self.vlmEvaluator.systemPromptOverride = self.systemPromptOverride
        self.vlmEvaluator.chatModeEnabled = self.chatModeEnabled
        self.vlmEvaluator.generateParameters = GenerateParameters(
            maxTokens: 100,
            maxKVSize: self.effectiveMaxContextTokens,
            temperature: self.temperature
        )
        self.vlmEvaluator.updateInterval = .seconds(Double(self.updateIntervalSeconds))

        if self.inputPrompt.value == nil || self.inputPrompt.value?.isEmpty == true {
            self.inputPrompt.value = modelConfiguration.defaultPrompt
            self.vlmEvaluator.prompt = modelConfiguration.defaultPrompt
        }
    }

    private func refreshAvailableModels() {
        let configurations = Array(VLMRegistry.shared.models)
        self.availableModels = LocalModelRuntimeSupport.catalogEntries(
            for: configurations,
            family: .vlm
        )

        self.catalogMetadataTask?.cancel()
        self.catalogMetadataTask = Task { @MainActor [weak self, configurations] in
            let metadata = await LocalModelMetadataCache.shared.metadata(
                for: configurations.map(\.name),
                family: .vlm
            )
            guard Task.isCancelled == false else { return }

            let entries = LocalModelRuntimeSupport.catalogEntries(
                for: configurations,
                family: .vlm,
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
                family: .vlm,
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
