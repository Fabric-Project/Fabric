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

    var modelConfiguration = LLMRegistry.qwen3_1_7b_4bit
    var generateParameters = GenerateParameters(maxKVSize: 4_096, temperature: 0.6)
    var updateInterval = Duration.seconds(0.25)
    var systemPromptOverride = ""
    var chatModeEnabled = true

    private var generationTask: Task<Void, Never>?
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

    func clearConversation() {
        self.chatSession = nil
        self.chatSessionSignature = nil
    }

    func resetSessionState() {
        self.cancelGeneration()
        self.clearConversation()
        self.loadedModelID = nil
        self.modelContainer = nil
        self.activityText = ""
    }

    func load() async throws -> ModelContainer {
        if let modelContainer, self.loadedModelID == self.modelConfiguration.name {
            return modelContainer
        }

        self.activityText = "Loading \(self.modelConfiguration.name)…"

        let modelContainer = try await LocalModelContainerCache.shared.loadContainer(
            family: .llm,
            configuration: self.modelConfiguration
        ) { [modelConfiguration] progress in
            self.activityText = "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
        }

        let parameterCount = await modelContainer.perform { context in
            context.model.numParameters()
        }

        self.loadedModelID = self.modelConfiguration.name
        self.modelContainer = modelContainer
        self.modelInfo = "Loaded \(self.modelConfiguration.name). Weights: \(parameterCount / (1024 * 1024))M"
        self.activityText = ""
        self.clearConversation()

        if self.prompt.isEmpty {
            self.prompt = self.modelConfiguration.defaultPrompt
        }

        return modelContainer
    }

    func generate() {
        guard self.running == false else { return }

        let currentPrompt = self.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentPrompt.isEmpty == false else { return }

        self.generationTask = Task {
            self.running = true
            await self.generateResponse(for: currentPrompt)
            self.running = false
        }
    }

    func cancelGeneration() {
        self.generationTask?.cancel()
        self.generationTask = nil
        self.running = false
    }

    private func generateResponse(for prompt: String) async {
        self.output = ""
        self.stat = ""

        do {
            let modelContainer = try await self.load()
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1_000))

            let session = self.chatModeEnabled
                ? self.chatSession(using: modelContainer)
                : self.makeStatelessSession(using: modelContainer)

            let stream = session.streamDetails(to: prompt, images: [], videos: [])
            for try await batch in stream._throttle(for: self.updateInterval, reducing: Generation.collect) {
                try Task.checkCancellation()

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
            self.output = "Failed: \(error)"
            self.activityText = ""
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
