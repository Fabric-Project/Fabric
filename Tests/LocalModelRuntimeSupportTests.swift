import Foundation
import Testing
@testable import Fabric
internal import MLXLMCommon

@Suite("Local Model Runtime Support")
struct LocalModelRuntimeSupportTests {
    @Test("Catalog groups curated models by org with mlx-community first")
    func catalogGroupsCuratedModelsByOrganization() {
        let configurations = [
            ModelConfiguration(id: "apple/FastModel"),
            ModelConfiguration(id: "mlx-community/Qwen3-4B-4bit"),
            ModelConfiguration(id: "huggingface/UtilityModel"),
            ModelConfiguration(id: "mlx-community/SmolLM-135M-Instruct-4bit"),
        ]

        let entries = LocalModelRuntimeSupport.catalogEntries(for: configurations)
        let groups = LocalModelRuntimeSupport.groupedCatalogEntries(from: entries, searchText: "")

        #expect(groups.first?.organization == "mlx-community")
        #expect(groups.first?.models.map(\.repositoryName) == [
            "Qwen3-4B-4bit",
            "SmolLM-135M-Instruct-4bit",
        ])
    }

    @Test("Catalog search filters by repo and organization")
    func catalogSearchFiltersEntries() {
        let configurations = [
            ModelConfiguration(id: "mlx-community/Qwen3-4B-4bit"),
            ModelConfiguration(id: "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit"),
            ModelConfiguration(id: "apple/FastModel"),
        ]

        let entries = LocalModelRuntimeSupport.catalogEntries(for: configurations)

        let repoSearchGroups = LocalModelRuntimeSupport.groupedCatalogEntries(from: entries, searchText: "Qwen3-VL")
        #expect(repoSearchGroups.count == 1)
        #expect(repoSearchGroups.first?.models.map(\.id) == ["lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit"])

        let organizationSearchGroups = LocalModelRuntimeSupport.groupedCatalogEntries(from: entries, searchText: "apple")
        #expect(organizationSearchGroups.count == 1)
        #expect(organizationSearchGroups.first?.organization == "apple")
    }

    @Test("Catalog applies remote size and capability metadata")
    func catalogAppliesRemoteMetadata() {
        let modelID = "example/VisionModel-4bit"
        let metadata = LocalModelRemoteMetadata(
            sizeInBytes: 1_500_000_000,
            summary: "Vision and text • 4-bit quantized"
        )

        let entries = LocalModelRuntimeSupport.catalogEntries(
            for: [ModelConfiguration(id: modelID)],
            family: .vlm,
            metadataByModelID: [modelID: metadata]
        )

        #expect(entries.first?.sizeInBytes == 1_500_000_000)
        #expect(entries.first?.summary == "Vision and text • 4-bit quantized")
    }

    @Test("A cached config without weights is not a complete model")
    func cachedConfigWithoutWeightsIsIncomplete() throws {
        let modelDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: modelDirectory) }

        try Data("{}".utf8).write(to: modelDirectory.appending(path: "config.json"))
        #expect(LocalModelRuntimeSupport.isCompleteModelDirectory(modelDirectory) == false)

        try Data([0]).write(to: modelDirectory.appending(path: "model.safetensors"))
        #expect(LocalModelRuntimeSupport.isCompleteModelDirectory(modelDirectory))
    }

    @Test("Latest generation request invalidates earlier requests")
    func latestGenerationRequestWins() {
        var tracker = LocalModelGenerationRequestTracker()
        let firstRequestID = tracker.beginRequest()
        let secondRequestID = tracker.beginRequest()

        #expect(tracker.isCurrent(firstRequestID) == false)
        #expect(tracker.isCurrent(secondRequestID))

        tracker.cancelCurrentRequest()
        #expect(tracker.isCurrent(secondRequestID) == false)
    }

    @Test("Runtime state exposes useful loading and failure labels")
    func runtimeStateLabels() {
        #expect(LocalModelRuntimeState.downloading(progress: 0.426).title == "Downloading 42.6%")
        #expect(LocalModelRuntimeState.ready.title == "Ready")
        #expect(LocalModelRuntimeState.generating.isReady)
        #expect(LocalModelRuntimeState.failed(message: "Unavailable").detail == "Unavailable")
    }
}
