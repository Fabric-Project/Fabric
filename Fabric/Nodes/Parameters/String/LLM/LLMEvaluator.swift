import Foundation
internal import AsyncAlgorithms
internal import MLX
internal import MLXLLM
internal import MLXLMCommon

final class LLMEvaluator {
    var onOutputChanged: ((String) -> Void)?
    var onModelInfoChanged: ((String) -> Void)?
    var onStatChanged: ((String) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?
    var onActivityTextChanged: ((String) -> Void)?
    var onGenerationErrorChanged: ((String?) -> Void)?

    var running = false {
        didSet {
            self.onRunningChanged?(self.running)
        }
    }

    var prompt = ""
    var output = "" {
        didSet {
            self.onOutputChanged?(self.output)
        }
    }
    var modelInfo = "" {
        didSet {
            self.onModelInfoChanged?(self.modelInfo)
        }
    }
    var stat = "" {
        didSet {
            self.onStatChanged?(self.stat)
        }
    }
    var activityText = "" {
        didSet {
            self.onActivityTextChanged?(self.activityText)
        }
    }
    var generationError: String? {
        didSet {
            self.onGenerationErrorChanged?(self.generationError)
        }
    }

    var modelConfiguration = LLMRegistry.qwen3_1_7b_4bit
    var generateParameters = GenerateParameters(maxKVSize: 4_096, temperature: 0.6)
    var updateInterval = Duration.seconds(0.25)
    var systemPromptOverride = ""
    var chatModeEnabled = true

    private var generationTask: Task<Void, Never>?
    private var generationRequestTracker = LocalModelGenerationRequestTracker()
    private let modelLoadConsumerID = UUID()
    private var loadedModelID: String?
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    private var chatSessionSignature: ChatSessionSignature?

    private struct ChatSessionSignature: Equatable {
        let modelID: String
        let instructions: String
        let temperature: Float
        let maxKVSize: Int?
    }

    deinit {
        let consumerID = self.modelLoadConsumerID
        let modelID = self.modelConfiguration.name
        Task {
            await LocalModelContainerCache.shared.releaseContainer(
                family: .llm,
                modelID: modelID,
                consumerID: consumerID
            )
        }
    }

    func clearConversation() {
        self.chatSession = nil
        self.chatSessionSignature = nil
    }

    func resetSessionState() {
        self.cancelModelOperation()
    }

    func load(configuration: ModelConfiguration, requestID: Int) async throws -> ModelContainer {
        if let modelContainer, self.loadedModelID == configuration.name {
            return modelContainer
        }

        self.activityText = "Loading \(configuration.name)…"

        let modelContainer = try await LocalModelContainerCache.shared.loadContainer(
            family: .llm,
            configuration: configuration,
            consumerID: self.modelLoadConsumerID
        )

        guard self.generationRequestTracker.isCurrent(requestID), Task.isCancelled == false else {
            throw CancellationError()
        }

        let parameterCount = await modelContainer.perform { context in
            context.model.numParameters()
        }

        self.loadedModelID = configuration.name
        self.modelContainer = modelContainer
        self.modelInfo = "Loaded \(configuration.name). Weights: \(parameterCount / (1024 * 1024))M"
        self.activityText = ""
        self.clearConversation()

        if self.prompt.isEmpty {
            self.prompt = self.modelConfiguration.defaultPrompt
        }

        return modelContainer
    }

    func generate() {
        let currentPrompt = self.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentPrompt.isEmpty == false else { return }

        let requestID = self.generationRequestTracker.beginRequest()
        let configuration = self.modelConfiguration
        let previousTask = self.running ? self.generationTask : nil
        self.generationError = nil

        if previousTask != nil {
            previousTask?.cancel()
            self.clearConversation()
        }

        self.running = true
        self.generationTask = Task { [weak self] in
            guard let self, self.generationRequestTracker.isCurrent(requestID), Task.isCancelled == false else { return }
            await self.generateResponse(for: currentPrompt, configuration: configuration, requestID: requestID)

            guard self.generationRequestTracker.isCurrent(requestID) else { return }
            self.generationTask = nil
            self.running = false
        }
    }

    func prepareModel() {
        let requestID = self.generationRequestTracker.beginRequest()
        let configuration = self.modelConfiguration
        self.generationTask?.cancel()
        self.clearConversation()
        self.generationError = nil

        self.generationTask = Task { [weak self] in
            guard let self else { return }

            do {
                _ = try await self.load(configuration: configuration, requestID: requestID)
                guard self.generationRequestTracker.isCurrent(requestID) else { return }
                self.generationTask = nil
            } catch is CancellationError {
                guard self.generationRequestTracker.isCurrent(requestID) else { return }
                self.generationTask = nil
            } catch {
                guard self.generationRequestTracker.isCurrent(requestID) else { return }
                self.generationTask = nil
                self.activityText = ""
                self.generationError = error.localizedDescription
            }
        }
    }

    func cancelModelOperation() {
        let modelID = self.loadedModelID ?? self.modelConfiguration.name
        let consumerID = self.modelLoadConsumerID
        self.cancelGeneration()
        self.clearConversation()
        self.loadedModelID = nil
        self.modelContainer = nil
        self.modelInfo = ""
        Task {
            await LocalModelContainerCache.shared.releaseContainer(
                family: .llm,
                modelID: modelID,
                consumerID: consumerID
            )
        }
    }

    func cancelGeneration() {
        let wasRunning = self.running
        self.generationRequestTracker.cancelCurrentRequest()
        self.generationTask?.cancel()
        self.generationTask = nil
        self.running = false
        if wasRunning {
            self.clearConversation()
        }
        self.activityText = ""
        self.generationError = nil
    }

    private func generateResponse(for prompt: String, configuration: ModelConfiguration, requestID: Int) async {
        self.output = ""
        self.stat = ""

        do {
            let modelContainer = try await self.load(configuration: configuration, requestID: requestID)
            guard self.generationRequestTracker.isCurrent(requestID) else { return }
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1_000))

            let session = self.chatModeEnabled
                ? self.chatSession(using: modelContainer)
                : self.makeStatelessSession(using: modelContainer)

            let stream = session.streamDetails(to: prompt, images: [], videos: [])
            for try await batch in stream._throttle(for: self.updateInterval, reducing: Generation.collect) {
                try Task.checkCancellation()
                guard self.generationRequestTracker.isCurrent(requestID) else { return }

                let outputDelta = batch.compactMap { $0.chunk }.joined(separator: "")
                if outputDelta.isEmpty == false {
                    self.output += outputDelta
                }

                if let completion = batch.compactMap({ $0.info }).first {
                    self.stat = "\(completion.tokensPerSecond) tokens/s"
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard self.generationRequestTracker.isCurrent(requestID) else { return }
            self.output = "Failed: \(error)"
            self.activityText = ""
            self.generationError = error.localizedDescription
        }
    }

    private func chatSession(using modelContainer: ModelContainer) -> ChatSession {
        let instructions = self.resolvedInstructions()
        let signature = ChatSessionSignature(
            modelID: self.modelConfiguration.name,
            instructions: instructions,
            temperature: self.generateParameters.temperature,
            maxKVSize: self.generateParameters.maxKVSize
        )

        if let chatSession, self.chatSessionSignature == signature {
            chatSession.instructions = instructions
            chatSession.generateParameters = self.generateParameters
            chatSession.additionalContext = nil
            return chatSession
        }

        let session = ChatSession(
            modelContainer,
            instructions: instructions,
            generateParameters: self.generateParameters
        )
        self.chatSession = session
        self.chatSessionSignature = signature
        return session
    }

    private func makeStatelessSession(using modelContainer: ModelContainer) -> ChatSession {
        ChatSession(
            modelContainer,
            instructions: self.resolvedInstructions(),
            generateParameters: self.generateParameters
        )
    }

    private func resolvedInstructions() -> String {
        let trimmedOverride = self.systemPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedOverride.isEmpty ? "You are a helpful assistant." : trimmedOverride
    }
}
