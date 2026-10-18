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
}

// HERMEX-FORK: tests for the fork's Telegram-shaped picker hierarchy.
/// Pins the Telegram shape of the picker: one row per provider (or per provider
/// family), the provider's groups behind it, its models behind those. The
/// failure this guards against is the one the user reported: every server group
/// rendered as its own top-level section, so one provider appeared three times
/// ("Nous Portal", "Nous Portal · Latest", "Nous Portal · Free").
final class ModelPickerHierarchyTests: XCTestCase {
    private func option(_ id: String, provider: String?) -> ModelCatalogOption {
        ModelCatalogOption(id: id, displayName: id, providerID: provider)
    }

    private var nousGroups: [ModelCatalogGroup] {
        [
            ModelCatalogGroup(
                id: "nous-free",
                name: "Nous Portal · Free",
                providerID: "nous",
                models: [option("@nous:meituan/longcat-2.5-preview:free", provider: "nous")]
            ),
            ModelCatalogGroup(
                id: "nous-latest",
                name: "Nous Portal · Latest",
                providerID: "nous",
                models: [option("@nous:anthropic/claude-sonnet-4.6-latest", provider: "nous")]
            ),
            ModelCatalogGroup(
                id: "nous",
                name: "Nous Portal",
                providerID: "nous",
                models: [
                    option("@nous:anthropic/claude-sonnet-4.6", provider: "nous"),
                    option("@nous:stealth/missingno", provider: "nous"),
                ]
            ),
        ]
    }

    func testOneProviderBecomesOneRowWhateverTheServerSplit() {
        let providers = ModelPickerCatalogBuilder.providers(from: nousGroups)

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.title, "Nous Portal")
        XCTAssertEqual(providers.first?.count, 4)
        XCTAssertFalse(providers.first?.isFamily ?? true)
    }

    func testGroupsAreAllModelsPlusEveryNonEmptyBucket() {
        let providers = ModelPickerCatalogBuilder.providers(from: nousGroups)
        let kinds = providers.first?.groups.map(\.kind) ?? []

        XCTAssertEqual(kinds, [.all, .free, .latest])
        XCTAssertEqual(providers.first?.groups.first?.count, 4)
    }

    func testAnEmptyBucketIsNotOffered() {
        let providers = ModelPickerCatalogBuilder.providers(from: nousGroups)
        let kinds = Set(providers.first?.groups.map(\.kind) ?? [])

        XCTAssertFalse(kinds.contains(.contributor))
    }

    func testOpenCodeFoldsIntoOneFamilyRowLikeTelegram() {
        let groups = [
            ModelCatalogGroup(
                id: "opencode-go",
                name: "OpenCode Go",
                providerID: "opencode-go",
                models: [option("mimo-v2.6-flash", provider: "opencode-go")]
            ),
            ModelCatalogGroup(
                id: "opencode-free",
                name: "OpenCode Free",
                providerID: "opencode-free",
                models: [option("@opencode-free:longcat-2.5-preview-free", provider: "opencode-free")]
            ),
        ]

        let providers = ModelPickerCatalogBuilder.providers(from: groups)

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.id, "opencode")
        XCTAssertEqual(providers.first?.title, "OpenCode")
        XCTAssertTrue(providers.first?.isFamily ?? false)
        XCTAssertEqual(providers.first?.memberProviderIDs, ["opencode-go", "opencode-free"])
        XCTAssertEqual(providers.first?.count, 2)
    }

    func testAFamilyDownToOnePresentMemberIsNotAFold() {
        let groups = [
            ModelCatalogGroup(
                id: "opencode-go",
                name: "OpenCode Go",
                providerID: "opencode-go",
                models: [option("mimo-v2.6-flash", provider: "opencode-go")]
            ),
        ]

        let providers = ModelPickerCatalogBuilder.providers(from: groups)

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.id, "opencode-go")
        XCTAssertFalse(providers.first?.isFamily ?? true)
    }

    func testFreeWinsOverLatestForAnIdThatIsBoth() {
        XCTAssertEqual(
            ModelPickerGroupKind.classify("@openrouter:vendor/model:free"),
            [.free]
        )
        XCTAssertEqual(
            ModelPickerGroupKind.classify("@openrouter:vendor/model:free-latest"),
            [.free]
        )
    }

    func testContributorAndLatestAreClassifiedLikeTelegramsBuckets() {
        XCTAssertEqual(ModelPickerGroupKind.classify("vendor/model-latest"), [.latest])
        XCTAssertEqual(ModelPickerGroupKind.classify("vendor/model-contributor"), [.contributor])
        XCTAssertEqual(ModelPickerGroupKind.classify("vendor/model"), [])
    }

    func testProviderRowTitlePrefersThePlainGroupName() {
        // "Nous Portal · Free" must not become the provider's row title.
        let title = ModelPickerCatalogBuilder.providers(from: nousGroups).first?.title

        XCTAssertEqual(title, "Nous Portal")
    }
}
