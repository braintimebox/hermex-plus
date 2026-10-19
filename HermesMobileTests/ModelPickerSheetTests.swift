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

    /// A colliding row is MERGED, never dropped: a repeated payload carrying
    /// extra models must keep every model it brought.
    func testCollidingRowsMergeTheirModelsWithoutLoss() {
        let first = ModelCatalogGroup(
            id: "openrouter:OpenRouter · Free:0",
            name: "OpenRouter · Free",
            providerID: "openrouter",
            models: [option("a/free-model", provider: "openrouter")]
        )
        let second = ModelCatalogGroup(
            id: "openrouter:OpenRouter · Free:7",
            name: "OpenRouter · Free",
            providerID: "openrouter",
            models: [
                option("a/free-model", provider: "openrouter"),   // duplicate model
                option("b/free-model", provider: "openrouter")    // new model
            ]
        )

        let deduped = ModelPickerSheet.deduplicatedGroups([first, second])

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.models.map(\.id), ["a/free-model", "b/free-model"])
    }

    // MARK: Section order (FREE / LATEST / CONTRIBUTOR / others)

    private func sectionGroup(_ name: String, provider: String, models: Int = 1) -> ModelCatalogGroup {
        ModelCatalogGroup(
            id: "\(provider):\(name):0",
            name: name,
            providerID: provider,
            models: (0..<models).map {
                ModelCatalogOption(id: "\(provider)/m\($0)", displayName: "m\($0)", providerID: provider)
            }
        )
    }

    /// The category is the text after the last "·", which is how hermes-webui
    /// names a derived group ("OpenRouter · Free"). A provider whose own name
    /// already ends with the keyword belongs to that block as well.
    func testSectionResolvesDerivedCategoryFromGroupName() {
        XCTAssertEqual(ModelPickerCatalogSection.resolve(groupName: "OpenRouter · Free"), .free)
        XCTAssertEqual(ModelPickerCatalogSection.resolve(groupName: "Nous Portal · Latest"), .latest)
        XCTAssertEqual(ModelPickerCatalogSection.resolve(groupName: "OpenCode Go · Contributor"), .contributor)
        XCTAssertEqual(ModelPickerCatalogSection.resolve(groupName: "OpenCode Free"), .free)
        XCTAssertEqual(ModelPickerCatalogSection.resolve(groupName: "DeepSeek"), .other)
        XCTAssertEqual(ModelPickerCatalogSection.resolve(groupName: "OpenCode Go"), .other)
    }

    /// Fixed block order; providers inside a block sort alphabetically.
    func testSectionsFollowDesignOrderAndSortByProviderName() {
        let groups = [
            sectionGroup("DeepSeek", provider: "deepseek"),
            sectionGroup("OpenRouter · Free", provider: "openrouter"),
            sectionGroup("Nous Portal · Free", provider: "nous"),
            sectionGroup("OpenRouter · Latest", provider: "openrouter"),
            sectionGroup("OpenCode Free", provider: "opencode-free"),
            sectionGroup("Gemini · Contributor", provider: "gemini")
        ]

        let sections = ModelPickerSheet.sectionedGroups(groups)

        XCTAssertEqual(sections.map(\.section), [.free, .latest, .contributor, .other])
        XCTAssertEqual(sections[0].groups.map(\.name), ["OpenCode Free", "OpenRouter · Free", "Nous Portal · Free"])
        XCTAssertEqual(sections[1].groups.map(\.name), ["OpenRouter · Latest"])
        XCTAssertEqual(sections[2].groups.map(\.name), ["Gemini · Contributor"])
        // "OpenCode Free" is a provider catalog whose own name ends with the
        // keyword: it appears in FREE and, mirrored, under the full catalogs.
        XCTAssertEqual(sections[3].groups.map(\.name), ["DeepSeek", "OpenCode Free"])
    }

    /// Sectioning never loses a category: every input group is present, derived
    /// slices exactly once, and a provider whose own name carries the keyword
    /// also sits under the full catalogs (as the agreed design shows).
    func testSectioningKeepsEveryGroupAndMirrorsOwnNameCatalogs() {
        let groups = [
            sectionGroup("OpenRouter", provider: "openrouter"),
            sectionGroup("OpenRouter · Free", provider: "openrouter"),
            sectionGroup("OpenRouter · Latest", provider: "openrouter"),
            sectionGroup("OpenRouter · Contributor", provider: "openrouter"),
            sectionGroup("Nous Portal", provider: "nous"),
            sectionGroup("Nous Portal · Free", provider: "nous"),
            sectionGroup("Nous Portal · Latest", provider: "nous"),
            sectionGroup("OpenCode Free", provider: "opencode-free")
        ]

        let sections = ModelPickerSheet.sectionedGroups(groups)
        let flattened = sections.flatMap(\.groups)

        XCTAssertEqual(Set(flattened.map(\.name)), Set(groups.map(\.name)))
        XCTAssertEqual(sections.map(\.section), [.free, .latest, .contributor, .other])

        // A derived slice lives in its block only.
        XCTAssertEqual(flattened.filter { $0.name == "OpenRouter · Free" }.count, 1)
        // A provider's own catalog is reachable from FREE and from the full list.
        XCTAssertEqual(flattened.filter { $0.name == "OpenCode Free" }.count, 2)
        XCTAssertEqual(sections.first(where: { $0.section == .free })?.groups.map(\.name),
                       ["OpenCode Free", "OpenRouter · Free", "Nous Portal · Free"])
        XCTAssertTrue(sections.first(where: { $0.section == .other })?.groups.map(\.name).contains("OpenCode Free") ?? false)
    }

    /// An empty block is omitted rather than rendered as a header with nothing
    /// under it.
    func testEmptySectionsAreOmitted() {
        let sections = ModelPickerSheet.sectionedGroups([sectionGroup("DeepSeek", provider: "deepseek")])

        XCTAssertEqual(sections.map(\.section), [.other])
    }

    // MARK: Catalog counter (P0: Nous Portal 44 → 399)

    /// The header's total is `allModels.count`, so a model listed in both the
    /// visible slice and the overflow tail must be counted once. Duplicates
    /// across the two buckets are what would inflate a provider close to double.
    func testAllModelsDeduplicatesVisibleAndOverflow() {
        let a = ModelCatalogOption(id: "vendor/a", displayName: "A", providerID: "nous")
        let b = ModelCatalogOption(id: "vendor/b", displayName: "B", providerID: "nous")
        let c = ModelCatalogOption(id: "vendor/c", displayName: "C", providerID: "nous")
        let group = ModelCatalogGroup(
            id: "nous:Nous Portal:0",
            name: "Nous Portal",
            providerID: "nous",
            models: [a, b],
            extraModels: [b, c]
        )

        XCTAssertEqual(group.allModels.map(\.id), ["vendor/a", "vendor/b", "vendor/c"])
        XCTAssertEqual(group.allModels.count, 3)
    }

    /// The counter must never exceed the number of distinct ids the group holds,
    /// and it must reach every id in the overflow tail.
    func testAllModelsCountCoversEveryDistinctId() {
        let ids = (0..<40).map { "vendor/m\($0)" }
        let options = ids.map { ModelCatalogOption(id: $0, displayName: $0, providerID: "nous") }
        let group = ModelCatalogGroup(
            id: "nous:Nous Portal:0",
            name: "Nous Portal",
            providerID: "nous",
            models: Array(options.prefix(15)),
            extraModels: Array(options.dropFirst(15))
        )

        XCTAssertEqual(group.allModels.count, ids.count)
        XCTAssertEqual(Set(group.allModels.map(\.id)).count, group.allModels.count)
    }

    // MARK: FREE order and search

    /// The agreed mock fixes FREE as OpenCode Free → OpenRouter · Free →
    /// Nous Portal · Free, whatever order the catalog arrives in. A provider
    /// that is not in the list keeps its alphabetical place after them.
    func testFreeSectionFollowsAgreedOrder() {
        let groups = [
            sectionGroup("Nous Portal · Free", provider: "nous"),
            sectionGroup("OpenRouter · Free", provider: "openrouter"),
            sectionGroup("OpenCode Free", provider: "opencode-free"),
            sectionGroup("Acme · Free", provider: "acme")
        ]

        let free = ModelPickerSheet.sectionedGroups(groups).first { $0.section == .free }

        XCTAssertEqual(
            free?.groups.map(\.name),
            ["OpenCode Free", "OpenRouter · Free", "Nous Portal · Free", "Acme · Free"]
        )
    }

    /// Outside FREE the blocks stay alphabetical.
    func testOtherSectionsStayAlphabetical() {
        let groups = [
            sectionGroup("OpenRouter · Latest", provider: "openrouter"),
            sectionGroup("Nous Portal · Latest", provider: "nous"),
            sectionGroup("Gemini · Latest", provider: "gemini")
        ]

        let latest = ModelPickerSheet.sectionedGroups(groups).first { $0.section == .latest }

        XCTAssertEqual(latest?.groups.map(\.name), [
            "Gemini · Latest", "Nous Portal · Latest", "OpenRouter · Latest"
        ])
    }

    /// Searching narrows models inside a category but keeps the category, so a
    /// hit still says which provider and block it belongs to.
    func testSearchKeepsTheCategoryForMatchingModels() {
        let groups = [
            sectionGroup("OpenRouter · Free", provider: "openrouter", models: 3),
            sectionGroup("Nous Portal · Free", provider: "nous", models: 3)
        ]

        let filtered = ModelPickerSheet.filteredGroups(groups, query: "openrouter/m1")

        XCTAssertEqual(filtered.map(\.name), ["OpenRouter · Free"])
        XCTAssertEqual(filtered.first?.allModels.map(\.id), ["openrouter/m1"])
    }
}
