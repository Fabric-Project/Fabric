// Borrowed from https://github.com/ml-explore/mlx-swift-examples/blob/main/Applications/LLMEval/ContentView.swift

import CoreImage
internal import AsyncAlgorithms
internal import MLX
internal import MLXLLM
internal import MLXVLM
internal import MLXLMCommon

class VLMEvaluator {

    let videoSystemPrompt =
        "Focus only on describing the key dramatic action or notable event occurring in this video segment. Skip general context or scene-setting details unless they are crucial to understanding the main action."
    let imageSystemPrompt =
        "You are an image understanding model capable of describing the salient features of any image."

    
    var running = false

    var includeWeatherTool = false
    var enableThinking = false

    var prompt = ""
    var output = ""
    var modelInfo = ""
    var stat = ""

    /// This controls which model loads. `qwen2_5_1_5b` is one of the smaller ones, so this will fit on
    /// more devices.
    var modelConfiguration = VLMRegistry.smolvlm

    /// parameters controlling the output
    var generateParameters = GenerateParameters( temperature: 0.6)
    var updateInterval = Duration.seconds(0.25)

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

            let modelContainer = try await VLMModelFactory.shared.loadContainer(
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

    private func generate(prompt: String, image: CIImage?, toolResult: String? = nil) async {
        
        let images: [UserInput.Image] = if let image { [.ciImage(image)] } else { [] }

        let systemPrompt = !images.isEmpty ? imageSystemPrompt :"You are a helpful assistant."
        
        self.output = ""
        var chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(prompt, images:images),
        ]

        if let toolResult {
            chat.append(.tool(toolResult))
        }

        var userInput = UserInput(
            chat: chat,
            tools: nil,
            additionalContext: ["enable_thinking": enableThinking]
        )

        userInput.processing.resize = .init(width: 448, height: 448)

        do {
            let modelContainer = try await load()

            // each time you generate you will get something new
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

            try await modelContainer.perform { (context: ModelContext) -> Void in
//                print("LLM preparing user input")
                let lmInput = try await context.processor.prepare(input: userInput)
                                
//                print("LLM begin streaming output")
                let stream = try MLXLMCommon.generate(
                    input: lmInput, parameters: generateParameters, context: context)

                // generate and output in batches
                for await batch in stream._throttle(
                    for: updateInterval, reducing: Generation.collect)
                {
//                    print("LLM recieved output batch")
                    
                    let output = batch.compactMap { $0.chunk }.joined(separator: "")
                    if !output.isEmpty {
                        Task { @MainActor [output] in
//                            print("LLM output append: \(output)")
                            self.output += output
                        }
                    }

                    if let completion = batch.compactMap({ $0.info }).first {
                        Task { @MainActor in
//                            print("LLM stats: \(completion.tokensPerSecond) tokens/s")
                            self.stat = "\(completion.tokensPerSecond) tokens/s"
                        }
                    }
                }
            }

        } catch {
            output = "Failed: \(error)"
        }
    }

    func generate(image: CIImage?) {
        guard !running else { return }
        let currentPrompt = prompt
        prompt = ""
        generationTask = Task {
            running = true
            await generate(prompt: currentPrompt, image:image)
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
