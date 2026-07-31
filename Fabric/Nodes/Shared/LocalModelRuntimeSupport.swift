import Foundation
internal import HuggingFace
internal import MLX
internal import MLXLLM
internal import MLXVLM
internal import MLXLMCommon
internal import MLXHuggingFace
internal import Tokenizers

struct LocalModelCatalogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let organization: String
    let repositoryName: String
    let isDownloaded: Bool
    let sizeInBytes: Int64?
    let summary: String

    var displayName: String {
        self.repositoryName
    }
}

struct LocalModelCatalogGroup: Identifiable, Hashable, Sendable {
    let organization: String
    let models: [LocalModelCatalogEntry]

    var id: String {
        self.organization
    }
}

enum LocalModelFamily: String, Hashable, Sendable {
    case llm
    case vlm
}

enum LocalModelRuntimeState: Equatable, Sendable {
    case unloaded
    case downloading(progress: Double)
    case loading
    case ready
    case generating
    case failed(message: String)

    var title: String {
        switch self {
        case .unloaded:
            "Not Loaded"
        case .downloading(let progress):
            "Downloading \(min(max(progress, 0), 1).formatted(.percent.precision(.fractionLength(1))))"
        case .loading:
            "Loading into Memory"
        case .ready:
            "Ready"
        case .generating:
            "Generating"
        case .failed:
            "Failed"
        }
    }

    var detail: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }

    var isReady: Bool {
        switch self {
        case .ready, .generating:
            true
        default:
            false
        }
    }
}

struct LocalModelRemoteMetadata: Hashable, Sendable {
    let sizeInBytes: Int64?
    let summary: String
}

struct LocalModelGenerationRequestTracker: Sendable {
    private(set) var currentRequestID = 0

    mutating func beginRequest() -> Int {
        self.currentRequestID += 1
        return self.currentRequestID
    }

    mutating func cancelCurrentRequest() {
        self.currentRequestID += 1
    }

    func isCurrent(_ requestID: Int) -> Bool {
        self.currentRequestID == requestID
    }
}

enum LocalModelRuntimeSupport {
    static func catalogEntries(
        for configurations: [ModelConfiguration],
        family: LocalModelFamily = .llm,
        metadataByModelID: [String: LocalModelRemoteMetadata] = [:]
    ) -> [LocalModelCatalogEntry] {
        configurations
            .map { configuration in
                let components = configuration.name.split(separator: "/", maxSplits: 1).map(String.init)
                let organization = components.first ?? "Other"
                let repositoryName = components.count > 1 ? components[1] : configuration.name
                let metadata = metadataByModelID[configuration.name]
                let isDownloaded = self.isModelDownloaded(modelID: configuration.name)
                return LocalModelCatalogEntry(
                    id: configuration.name,
                    organization: organization,
                    repositoryName: repositoryName,
                    isDownloaded: isDownloaded,
                    sizeInBytes: metadata?.sizeInBytes ?? (isDownloaded ? self.downloadedModelSize(modelID: configuration.name) : nil),
                    summary: metadata?.summary ?? self.modelSummary(modelID: configuration.name, family: family)
                )
            }
            .sorted { lhs, rhs in
                if lhs.organization == rhs.organization {
                    return lhs.repositoryName.localizedStandardCompare(rhs.repositoryName) == .orderedAscending
                }

                if lhs.organization == "mlx-community" {
                    return true
                }

                if rhs.organization == "mlx-community" {
                    return false
                }

                return lhs.organization.localizedStandardCompare(rhs.organization) == .orderedAscending
            }
    }

    static func groupedCatalogEntries(
        from entries: [LocalModelCatalogEntry],
        searchText: String
    ) -> [LocalModelCatalogGroup] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredEntries = if trimmedSearchText.isEmpty {
            entries
        } else {
            entries.filter { entry in
                entry.id.localizedStandardContains(trimmedSearchText)
                    || entry.organization.localizedStandardContains(trimmedSearchText)
                    || entry.repositoryName.localizedStandardContains(trimmedSearchText)
            }
        }

        let groupedEntries = Dictionary(grouping: filteredEntries, by: \.organization)
        let sortedOrganizations = groupedEntries.keys.sorted { lhs, rhs in
            if lhs == "mlx-community" {
                return true
            }

            if rhs == "mlx-community" {
                return false
            }

            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        return sortedOrganizations.compactMap { organization in
            guard let models = groupedEntries[organization], models.isEmpty == false else {
                return nil
            }

            return LocalModelCatalogGroup(organization: organization, models: models)
        }
    }

    static func isModelDownloaded(modelID: String) -> Bool {
        guard let modelDirectory = self.cachedModelDirectory(modelID: modelID) else {
            return false
        }

        return self.isCompleteModelDirectory(modelDirectory)
    }

    static func isCompleteModelDirectory(_ modelDirectory: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: modelDirectory.appending(path: "config.json").path) else {
            return false
        }

        guard let files = FileManager.default.enumerator(
            at: modelDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return files.compactMap { $0 as? URL }.contains { $0.pathExtension == "safetensors" }
    }

    static func downloadedModelSize(modelID: String) -> Int64? {
        guard let modelDirectory = self.cachedModelDirectory(modelID: modelID) else {
            return nil
        }

        guard let files = FileManager.default.enumerator(
            at: modelDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var totalSize: Int64 = 0
        var foundFile = false

        for case let fileURL as URL in files {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true,
                let fileSize = values.fileSize
            else {
                continue
            }

            foundFile = true
            totalSize += Int64(fileSize)
        }

        return foundFile ? totalSize : nil
    }

    static func modelSummary(modelID: String, family: LocalModelFamily) -> String {
        let capability = family == .vlm ? "Vision and text" : "Text generation"
        let lowercasedModelID = modelID.lowercased()

        if lowercasedModelID.localizedStandardContains("4bit") || lowercasedModelID.localizedStandardContains("4-bit") {
            return "\(capability) • 4-bit quantized"
        }

        if lowercasedModelID.localizedStandardContains("8bit") || lowercasedModelID.localizedStandardContains("8-bit") {
            return "\(capability) • 8-bit quantized"
        }

        if lowercasedModelID.localizedStandardContains("bf16") {
            return "\(capability) • BF16"
        }

        return capability
    }

    static func effectiveContextTokenLimit(for modelID: String, desired: Int) -> Int {
        let sanitizedDesired = max(256, desired)
        let hardwareLimit = self.hardwareContextTokenLimit()
        let modelLimit = self.modelContextTokenLimit(for: modelID)
        return min(sanitizedDesired, hardwareLimit, modelLimit ?? Int.max)
    }

    static func hardwareContextTokenLimit() -> Int {
        let memoryInGigabytes = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)

        switch memoryInGigabytes {
        case ..<16:
            return 2_048
        case 16..<32:
            return 4_096
        case 32..<64:
            return 8_192
        case 64..<128:
            return 16_384
        default:
            return 32_768
        }
    }

    static func modelContextTokenLimit(for modelID: String) -> Int? {
        guard let modelDirectory = self.cachedModelDirectory(modelID: modelID) else {
            return nil
        }

        let configurationFileURL = modelDirectory.appending(path: "config.json")
        guard
            let data = try? Data(contentsOf: configurationFileURL),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return self.findLargestContextLimit(in: jsonObject)
    }

    static func cachedModelDirectory(modelID: String) -> URL? {
        guard let repositoryID = Repo.ID(rawValue: modelID) else {
            return nil
        }

        return HubCache.default.cachedFilePath(
            repo: repositoryID,
            kind: .model,
            revision: "main",
            filename: "config.json"
        )?.deletingLastPathComponent()
    }

    private static func findLargestContextLimit(in dictionary: [String: Any]) -> Int? {
        let candidateKeys = [
            "max_position_embeddings",
            "max_sequence_length",
            "context_length",
            "max_seq_len",
            "n_ctx",
        ]

        var bestCandidate: Int?

        for key in candidateKeys {
            if let value = dictionary[key] as? Int {
                bestCandidate = max(bestCandidate ?? 0, value)
            } else if let value = dictionary[key] as? NSNumber {
                bestCandidate = max(bestCandidate ?? 0, value.intValue)
            }
        }

        for value in dictionary.values {
            if let nestedDictionary = value as? [String: Any] {
                if let nestedCandidate = self.findLargestContextLimit(in: nestedDictionary) {
                    bestCandidate = max(bestCandidate ?? 0, nestedCandidate)
                }
            } else if let nestedArray = value as? [[String: Any]] {
                for nestedDictionary in nestedArray {
                    if let nestedCandidate = self.findLargestContextLimit(in: nestedDictionary) {
                        bestCandidate = max(bestCandidate ?? 0, nestedCandidate)
                    }
                }
            }
        }

        return bestCandidate
    }
}

actor LocalModelMetadataCache {
    static let shared = LocalModelMetadataCache()

    private struct CacheKey: Hashable, Sendable {
        let family: LocalModelFamily
        let modelID: String
    }

    private let hubClient = HubClient()
    private var metadataByKey: [CacheKey: LocalModelRemoteMetadata] = [:]
    private var metadataTasks: [CacheKey: Task<LocalModelRemoteMetadata?, Never>] = [:]

    func metadata(for modelID: String, family: LocalModelFamily) async -> LocalModelRemoteMetadata? {
        let cacheKey = CacheKey(family: family, modelID: modelID)

        if let metadata = self.metadataByKey[cacheKey] {
            return metadata
        }

        if let task = self.metadataTasks[cacheKey] {
            return await task.value
        }

        let hubClient = self.hubClient
        let task = Task<LocalModelRemoteMetadata?, Never> {
            guard let repositoryID = Repo.ID(rawValue: modelID) else { return nil }

            do {
                let model = try await hubClient.getModel(
                    repositoryID,
                    full: true,
                    filesMetadata: true,
                    cardData: true
                )
                let requiredFilesSize = model.siblings?
                    .filter { sibling in
                        let filename = sibling.relativeFilename
                        return filename.hasSuffix(".safetensors")
                            || filename.hasSuffix(".json")
                            || filename.hasSuffix(".jinja")
                    }
                    .compactMap(\.size)
                    .reduce(0, +)
                let resolvedSize = requiredFilesSize.flatMap { $0 > 0 ? Int64($0) : nil }
                    ?? model.usedStorage.map(Int64.init)

                return LocalModelRemoteMetadata(
                    sizeInBytes: resolvedSize,
                    summary: LocalModelRuntimeSupport.modelSummary(modelID: modelID, family: family)
                )
            } catch {
                return nil
            }
        }

        self.metadataTasks[cacheKey] = task
        let metadata = await task.value
        self.metadataTasks.removeValue(forKey: cacheKey)
        if let metadata {
            self.metadataByKey[cacheKey] = metadata
        }
        return metadata
    }

    func metadata(for modelIDs: [String], family: LocalModelFamily) async -> [String: LocalModelRemoteMetadata] {
        var result: [String: LocalModelRemoteMetadata] = [:]
        let maximumConcurrentRequests = 6

        for batchStart in stride(from: 0, to: modelIDs.count, by: maximumConcurrentRequests) {
            let batchEnd = min(batchStart + maximumConcurrentRequests, modelIDs.count)
            let batch = modelIDs[batchStart..<batchEnd]

            let batchResult = await withTaskGroup(of: (String, LocalModelRemoteMetadata?).self) { group in
                for modelID in batch {
                    group.addTask {
                        let metadata = await self.metadata(for: modelID, family: family)
                        return (modelID, metadata)
                    }
                }

                var metadataByModelID: [String: LocalModelRemoteMetadata] = [:]
                for await (modelID, metadata) in group {
                    metadataByModelID[modelID] = metadata
                }
                return metadataByModelID
            }

            result.merge(batchResult) { _, latest in latest }
        }

        return result
    }
}

actor LocalModelContainerCache {
    static let shared = LocalModelContainerCache()

    private struct CacheKey: Hashable, Sendable {
        let family: LocalModelFamily
        let modelID: String
    }

    private struct ContainerLoad {
        let id: UUID
        let task: Task<ModelContainer, Error>
        var consumers: Set<UUID>
    }

    private var containerLoads: [CacheKey: ContainerLoad] = [:]
    private var activeLoadIDs: [CacheKey: UUID] = [:]
    private var acquisitionStates: [CacheKey: LocalModelRuntimeState] = [:]
    private var stateObservers: [CacheKey: [UUID: AsyncStream<LocalModelRuntimeState>.Continuation]] = [:]

    func isReady(family: LocalModelFamily, modelID: String) -> Bool {
        self.acquisitionStates[CacheKey(family: family, modelID: modelID)] == .ready
    }

    func stateUpdates(family: LocalModelFamily, modelID: String) -> AsyncStream<LocalModelRuntimeState> {
        let cacheKey = CacheKey(family: family, modelID: modelID)
        let observerID = UUID()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.stateObservers[cacheKey, default: [:]][observerID] = continuation
            continuation.yield(self.currentState(for: cacheKey))
            continuation.onTermination = { _ in
                Task {
                    await LocalModelContainerCache.shared.removeStateObserver(
                        observerID,
                        for: cacheKey
                    )
                }
            }
        }
    }

    func loadContainer(
        family: LocalModelFamily,
        configuration: ModelConfiguration,
        consumerID: UUID
    ) async throws -> ModelContainer {
        let cacheKey = CacheKey(family: family, modelID: configuration.name)

        if var existingLoad = self.containerLoads[cacheKey] {
            existingLoad.consumers.insert(consumerID)
            self.containerLoads[cacheKey] = existingLoad
            return try await existingLoad.task.value
        }

        let loadID = UUID()
        let initialState: LocalModelRuntimeState = LocalModelRuntimeSupport.isModelDownloaded(
            modelID: configuration.name
        ) ? .loading : .downloading(progress: 0)
        self.updateState(initialState, for: cacheKey)
        self.activeLoadIDs[cacheKey] = loadID

        let task = Task<ModelContainer, Error> {
            MLX.Memory.cacheLimit = 20 * 1024 * 1024

            switch family {
            case .llm:
                return try await LLMModelFactory.shared.loadContainer(
                    from: #hubDownloader(),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: configuration,
                    progressHandler: { progress in
                        let fractionCompleted = progress.fractionCompleted
                        Task {
                            await LocalModelContainerCache.shared.reportProgress(
                                fractionCompleted,
                                for: cacheKey,
                                loadID: loadID
                            )
                        }
                    }
                )

            case .vlm:
                return try await VLMModelFactory.shared.loadContainer(
                    from: #hubDownloader(),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: configuration,
                    progressHandler: { progress in
                        let fractionCompleted = progress.fractionCompleted
                        Task {
                            await LocalModelContainerCache.shared.reportProgress(
                                fractionCompleted,
                                for: cacheKey,
                                loadID: loadID
                            )
                        }
                    }
                )
            }
        }

        self.containerLoads[cacheKey] = ContainerLoad(
            id: loadID,
            task: task,
            consumers: [consumerID]
        )

        do {
            let container = try await task.value
            guard
                task.isCancelled == false,
                self.activeLoadIDs[cacheKey] == loadID
            else {
                throw CancellationError()
            }
            self.activeLoadIDs.removeValue(forKey: cacheKey)
            self.updateState(.ready, for: cacheKey)
            return container
        } catch {
            if self.activeLoadIDs[cacheKey] == loadID {
                self.activeLoadIDs.removeValue(forKey: cacheKey)
                self.containerLoads.removeValue(forKey: cacheKey)
                if error is CancellationError {
                    self.updateState(.unloaded, for: cacheKey)
                } else {
                    self.updateState(.failed(message: error.localizedDescription), for: cacheKey)
                }
            }
            throw error
        }
    }

    func cancelLoadingContainer(family: LocalModelFamily, modelID: String, consumerID: UUID) {
        let cacheKey = CacheKey(family: family, modelID: modelID)
        guard self.acquisitionStates[cacheKey] != .ready else { return }
        guard var containerLoad = self.containerLoads[cacheKey] else { return }
        containerLoad.consumers.remove(consumerID)

        if containerLoad.consumers.isEmpty {
            self.activeLoadIDs.removeValue(forKey: cacheKey)
            self.containerLoads.removeValue(forKey: cacheKey)?.task.cancel()
            self.updateState(.unloaded, for: cacheKey)
        } else {
            self.containerLoads[cacheKey] = containerLoad
        }
    }

    private func reportProgress(_ fractionCompleted: Double, for cacheKey: CacheKey, loadID: UUID) {
        guard self.activeLoadIDs[cacheKey] == loadID else { return }
        let clampedProgress = min(max(fractionCompleted, 0), 1)

        switch self.currentState(for: cacheKey) {
        case .loading, .ready:
            return
        case .downloading(let currentProgress) where clampedProgress < currentProgress:
            return
        default:
            break
        }

        self.updateState(
            clampedProgress >= 1 ? .loading : .downloading(progress: clampedProgress),
            for: cacheKey
        )
    }

    private func currentState(for cacheKey: CacheKey) -> LocalModelRuntimeState {
        self.acquisitionStates[cacheKey] ?? .unloaded
    }

    private func updateState(_ state: LocalModelRuntimeState, for cacheKey: CacheKey) {
        guard self.acquisitionStates[cacheKey] != state else { return }
        self.acquisitionStates[cacheKey] = state
        guard let observers = self.stateObservers[cacheKey] else { return }
        for observer in observers.values {
            observer.yield(state)
        }
    }

    private func removeStateObserver(_ observerID: UUID, for cacheKey: CacheKey) {
        self.stateObservers[cacheKey]?.removeValue(forKey: observerID)
        if self.stateObservers[cacheKey]?.isEmpty == true {
            self.stateObservers.removeValue(forKey: cacheKey)
        }
    }
}
