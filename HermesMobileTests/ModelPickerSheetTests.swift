import XCTest
@testable import HermesMobile

/// Pins the two rules the shared picker gained when Settings > Default Model
/// started using it: which row spins during a server save, and what the custom
/// entry commits under each configuration.
final class ModelPickerSheetTests: XCTestCase {
    private func option(_ id: String, provider: String?) -> ModelCatalogOption {
        ModelCatalogOption(id: id, displayName: id, providerID: provider)
    }

    // MARK: In-flight row

    func testInFlightRowMatchesTheSavingModelAndProvider() {
        let key = ModelFavoriteKey(modelID: "gpt-5", providerID: "openai")

        XCTAssertTrue(
            ModelPickerSheet.isInFlight(option("gpt-5", provider: "openai"), inFlightKey: key)
        )
    }

    func testInFlightRowIgnoresTheSameModelIDUnderAnotherProvider() {
        let key = ModelFavoriteKey(modelID: "gpt-5", providerID: "openai")

        XCTAssertFalse(
            ModelPickerSheet.isInFlight(option("gpt-5", provider: "azure"), inFlightKey: key)
        )
        XCTAssertFalse(
            ModelPickerSheet.isInFlight(option("gpt-5", provider: nil), inFlightKey: key)
        )
    }

    func testNoRowIsInFlightWithoutAKey() {
        XCTAssertFalse(
            ModelPickerSheet.isInFlight(option("gpt-5", provider: "openai"), inFlightKey: nil)
        )
    }

    // MARK: Search

    private var codexGroup: ModelCatalogGroup {
        ModelCatalogGroup(
            id: "openai-codex",
            name: "OpenAI Codex",
            providerID: "openai-codex",
            models: [option("gpt-5", provider: "openai-codex"), option("o3", provider: "openai-codex")]
        )
    }

    func testSearchingAGroupsDisplayNameKeepsAllOfItsModels() {
        // The header reads "OpenAI Codex" while the id is "openai-codex", so
        // matching ids alone would answer "no models" to the visible name.
        let filtered = ModelPickerSheet.filteredGroups([codexGroup], query: "OpenAI Codex")

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.allModels.count, 2)
    }

    func testSearchingAModelNameKeepsOnlyThatModel() {
        let filtered = ModelPickerSheet.filteredGroups([codexGroup], query: "o3")

        XCTAssertEqual(filtered.first?.allModels.map(\.id), ["o3"])
    }

    func testSearchingSomethingAbsentDropsTheGroup() {
        XCTAssertTrue(ModelPickerSheet.filteredGroups([codexGroup], query: "claude").isEmpty)
    }

    func testAnEmptyQueryKeepsEveryGroupUntouched() {
        XCTAssertEqual(ModelPickerSheet.filteredGroups([codexGroup], query: "   ").count, 1)
    }

    // MARK: Custom entry

    func testServerDefaultCommitsABareModelIDWithNoProvider() {
        let built = ModelPickerSheet.customOption(
            modelID: "  my-model  ",
            providerID: "  ",
            configuration: .serverDefault
        )

        XCTAssertEqual(built?.id, "my-model")
        XCTAssertNil(built?.providerID)
    }

    func testComposerRequiresAProviderForACustomModel() {
        XCTAssertNil(
            ModelPickerSheet.customOption(
                modelID: "my-model",
                providerID: "",
                configuration: .composer
            )
        )
    }

    func testCustomProviderIsLowercasedWhenSupplied() {
        let built = ModelPickerSheet.customOption(
            modelID: "my-model",
            providerID: "OpenAI",
            configuration: .serverDefault
        )

        XCTAssertEqual(built?.providerID, "openai")
    }

    func testEmptyModelIDNeverCommits() {
        for configuration in [ModelPickerConfiguration.composer, .serverDefault] {
            XCTAssertNil(
                ModelPickerSheet.customOption(
                    modelID: "   ",
                    providerID: "openai",
                    configuration: configuration
                )
            )
        }
    }

    // MARK: Duplicate category rows (#604/#2569)

    private func group(_ id: String, _ name: String, provider: String?) -> ModelCatalogGroup {
        ModelCatalogGroup(
            id: id,
            name: name,
            providerID: provider,
            models: [ModelCatalogOption(id: "\(id)-model", displayName: "\(id)-model", providerID: provider)]
        )
    }

    /// Reproduced defect: the server payload repeats a category row (same
    /// provider_id and display name, different synthetic id). The picker must
    /// render it exactly once.
    func testRepeatedCategoryRowsCollapseToOne() {
        let groups = [
            group("openrouter:OpenRouter · Latest:5", "OpenRouter · Latest", provider: "openrouter"),
            group("openrouter:OpenRouter · Latest:9", "OpenRouter · Latest", provider: "openrouter")
        ]

        let deduped = ModelPickerSheet.deduplicatedGroups(groups)

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.name, "OpenRouter · Latest")
    }

    /// The regression this must never reintroduce: Free / Latest / Contributor
    /// and the base group share one provider_id but are DIFFERENT categories.
    /// Dedup keyed on provider_id alone would keep only one of them.
    func testDistinctCategoriesOfOneProviderAllSurvive() {
        let groups = [
            group("openrouter:OpenRouter:0", "OpenRouter", provider: "openrouter"),
            group("openrouter:OpenRouter · Free:1", "OpenRouter · Free", provider: "openrouter"),
            group("openrouter:OpenRouter · Latest:2", "OpenRouter · Latest", provider: "openrouter"),
            group("openrouter:OpenRouter · Contributor:3", "OpenRouter · Contributor", provider: "openrouter")
        ]

        let deduped = ModelPickerSheet.deduplicatedGroups(groups)

        XCTAssertEqual(deduped.count, 4)
        XCTAssertEqual(
            Set(deduped.map(\.name)),
            ["OpenRouter", "OpenRouter · Free", "OpenRouter · Latest", "OpenRouter · Contributor"]
        )
    }

    /// Same display name under two providers is two real categories, not a duplicate.
    func testSameNameUnderDifferentProvidersSurvives() {
        let groups = [
            group("nous:Nous Portal · Latest:0", "Nous Portal · Latest", provider: "nous"),
            group("openrouter:OpenRouter · Latest:1", "OpenRouter · Latest", provider: "openrouter")
        ]

        XCTAssertEqual(ModelPickerSheet.deduplicatedGroups(groups).count, 2)
    }

    /// Duplicate detection ignores casing and surrounding whitespace.
    func testDuplicateIdentityIgnoresCasingAndWhitespace() {
        let groups = [
            group("a", "OpenRouter · Free", provider: "openrouter"),
            group("b", "  openrouter · free ", provider: "OpenRouter")
        ]

        XCTAssertEqual(ModelPickerSheet.deduplicatedGroups(groups).count, 1)
    }

    /// A provider without a provider_id still deduplicates on its own name.
    func testDuplicateIdentityWorksWithoutProviderID() {
        let groups = [
            group("a", "Saved Custom", provider: nil),
            group("b", "Saved Custom", provider: nil)
        ]

        XCTAssertEqual(ModelPickerSheet.deduplicatedGroups(groups).count, 1)
    }
}
