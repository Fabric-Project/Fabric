import Foundation
internal import MLX
internal import MLXLLM
internal import MLXVLM
internal import MLXLMCommon

struct LocalModelCatalogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let organization: String
    let repositoryName: String
    let isDownloaded: Bool

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

enum LocalModelRuntimeSupport {
    static func catalogEntries(for configurations: [ModelConfiguration]) -> [LocalModelCatalogEntry] {
        configurations
            .map { configuration in
                let components = configuration.name.split(separator: "/", maxSplits: 1).map(String.init)
                let organization = components.first ?? "Other"
                let repositoryName = components.count > 1 ? components[1] : configuration.name
                return LocalModelCatalogEntry(
                    id: configuration.name,
                    organization: organization,
                    repositoryName: repositoryName,
                    isDownloaded: self.isModelDownloaded(modelID: configuration.name)
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
        let modelDirectory = ModelConfiguration(id: modelID).modelDirectory()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        return contents.isEmpty == false
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
        let modelDirectory = ModelConfiguration(id: modelID).modelDirectory()
        let configurationFileURL = modelDirectory.appending(path: "config.json")
        guard
            let data = try? Data(contentsOf: configurationFileURL),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return self.findLargestContextLimit(in: jsonObject)
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

actor LocalModelContainerCache {
    static let shared = LocalModelContainerCache()

    private struct CacheKey: Hashable {
        let family: LocalModelFamily
        let modelID: String
    }

    private var containerTasks: [CacheKey: Task<ModelContainer, Error>] = [:]

    func loadContainer(
        family: LocalModelFamily,
        configuration: ModelConfiguration,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> ModelContainer {
        let cacheKey = CacheKey(family: family, modelID: configuration.name)

        if let existingTask = self.containerTasks[cacheKey] {
            return try await existingTask.value
        }

        let task = Task<ModelContainer, Error> {
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            switch family {
            case .llm:
                return try await LLMModelFactory.shared.loadContainer(
                    configuration: configuration,
                    progressHandler: progressHandler
                )

            case .vlm:
                return try await VLMModelFactory.shared.loadContainer(
                    configuration: configuration,
                    progressHandler: progressHandler
                )
            }
        }

        self.containerTasks[cacheKey] = task

        do {
            return try await task.value
        } catch {
            self.containerTasks.removeValue(forKey: cacheKey)
            throw error
        }
    }
}
