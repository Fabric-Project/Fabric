// Borrowed from https://github.com/ml-explore/mlx-swift-examples/blob/main/Applications/LLMEval/ContentView.swift

internal import AsyncAlgorithms
internal import MLX
internal import MLXLLM
internal import MLXLMCommon

class LLMEvaluator {

    var running = false

    var includeWeatherTool = false
    var enableThinking = false

    var prompt = ""
    var output = ""
    var modelInfo = ""
    var stat = ""

    /// This controls which model loads. `qwen2_5_1_5b` is one of the smaller ones, so this will fit on
    /// more devices.
    var modelConfiguration = LLMRegistry.qwen3_1_7b_4bit

    /// parameters controlling the output
    let generateParameters = GenerateParameters(maxTokens: 240, temperature: 0.6)
    let updateInterval = Duration.seconds(0.25)

    /// A task responsible for handling the generation process.
    var generationTask: Task<Void, Error>?

    enum LoadState {
        case idle
        case loaded(ModelContainer)
    }

    var loadState = LoadState.idle

    /// load and return the model -- can be called multiple times, subsequent calls will
    /// just return the loaded model
    func load() async throws -> ModelContainer {
        switch loadState {
        case .idle:
            // limit the buffer cache
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: modelConfiguration
            ) {
                [modelConfiguration] progress in
                Task { @MainActor in
                    self.modelInfo =
                        "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
                }
            }
            let numParams = await modelContainer.perform { context in
                context.model.numParameters()
            }

            self.prompt = modelConfiguration.defaultPrompt
            self.modelInfo =
                "Loaded \(modelConfiguration.id). Weights: \(numParams / (1024*1024))M"
            loadState = .loaded(modelContainer)
            return modelContainer

        case .loaded(let modelContainer):
            return modelContainer
        }
    }

    private func generate(prompt: String, toolResult: String? = nil) async {

        self.output = ""
        var chat: [Chat.Message] = [
            .system("You are a helpful assistant"),
            .user(prompt),
        ]

        if let toolResult {
            chat.append(.tool(toolResult))
        }

        let userInput = UserInput(
            chat: chat,
            tools: nil,
            additionalContext: ["enable_thinking": enableThinking]
        )

        do {
            let modelContainer = try await load()

            // each time you generate you will get something new
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

            try await modelContainer.perform { (context: ModelContext) -> Void in
                let lmInput = try await context.processor.prepare(input: userInput)
                let stream = try MLXLMCommon.generate(
                    input: lmInput, parameters: generateParameters, context: context)

                // generate and output in batches
                for await batch in stream._throttle(
                    for: updateInterval, reducing: Generation.collect)
                {
                    let output = batch.compactMap { $0.chunk }.joined(separator: "")
                    if !output.isEmpty {
                        Task { @MainActor [output] in
                            self.output += output
                        }
                    }

                    if let completion = batch.compactMap({ $0.info }).first {
                        Task { @MainActor in
                            self.stat = "\(completion.tokensPerSecond) tokens/s"
                        }
                    }

//                    if let toolCall = batch.compactMap({ $0.toolCall }).first {
//                        try await handleToolCall(toolCall, prompt: prompt)
//                    }
                }
            }

        } catch {
            output = "Failed: \(error)"
        }
    }

    func generate() {
        guard !running else { return }
        let currentPrompt = prompt
        prompt = ""
        generationTask = Task {
            running = true
            await generate(prompt: currentPrompt)
            running = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        running = false
    }

//    private func handleToolCall(_ toolCall: ToolCall, prompt: String) async throws {
//        let result =
//            switch toolCall.function.name {
//            case currentWeatherTool.name:
//                try await toolCall.execute(with: currentWeatherTool).toolResult
//            case addTool.name:
//                try await toolCall.execute(with: addTool).toolResult
//            case timeTool.name:
//                try await toolCall.execute(with: timeTool).toolResult
//            default:
//                "No tool match"
//            }
//
//        await generate(prompt: prompt, toolResult: result)
//    }
}
//
//struct WeatherInput: Codable {
//    let location: String
//    let unit: String?
//}
//
//struct WeatherOutput: Codable {
//    let temperature: Double
//    let conditions: String
//}
//
//struct AddInput: Codable {
//    let first: Int
//    let second: Int
//}
//
//struct AddOutput: Codable {
//    let result: Int
//}
//
//struct EmptyInput: Codable {}
//
//struct TimeOutput: Codable {
//    let time: String
//}
