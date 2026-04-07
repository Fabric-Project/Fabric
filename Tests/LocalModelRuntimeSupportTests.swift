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
}
