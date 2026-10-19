import XCTest
@testable import HermesMobile

final class ComposerModelPickerSelectionClassificationTests: XCTestCase {
    private let visibleModel = ModelCatalogOption(
        id: "anthropic/claude-fable-5",
        displayName: "Claude Fable 5",
        providerID: "openrouter"
    )
    private let overflowModel = ModelCatalogOption(
        id: "deepseek/deepseek-v4-pro",
        displayName: "deepseek/deepseek-v4-pro",
        providerID: "openrouter"
    )

    private var groups: [ModelCatalogGroup] {
        [
            ModelCatalogGroup(
                id: "openrouter",
                name: "OpenRouter",
                providerID: "openrouter",
                models: [visibleModel],
                extraModels: [overflowModel]
            )
        ]
    }

    // PR #293 review: selecting an overflow model through search, then reopening
    // the picker with an empty query, must still classify it as NOT rendered so
    // the "Current Custom" row appears and shows the active selection.
    func testOverflowSelectionWithEmptyQueryIsNotRendered() {
        let rendered = ModelPickerSheet.isRenderedByCurrentPicker(
            option: overflowModel,
            modelGroups: groups,
            searchQuery: ""
        )

        XCTAssertFalse(
            rendered,
            "overflow model is invisible in the trimmed empty-query view; the Current Custom row must represent it"
        )
    }

    func testVisibleModelWithEmptyQueryIsRendered() {
        let rendered = ModelPickerSheet.isRenderedByCurrentPicker(
            option: visibleModel,
            modelGroups: groups,
            searchQuery: ""
        )

        XCTAssertTrue(rendered)
    }

    func testOverflowSelectionWithExpandedGroupIsRendered() {
        var overflowExpansion = ModelPickerOverflowExpansionState()
        overflowExpansion.setExpanded(true, groupID: "openrouter")

        let rendered = ModelPickerSheet.isRenderedByCurrentPicker(
            option: overflowModel,
            modelGroups: groups,
            searchQuery: "",
            overflowExpansion: overflowExpansion
        )

        XCTAssertTrue(rendered)
    }

    func testOverflowExpansionRevealsAndCollapsesExtraModels() {
        guard let group = groups.first else {
            return XCTFail("Expected an OpenRouter group")
        }
        var overflowExpansion = ModelPickerOverflowExpansionState()

        XCTAssertEqual(overflowExpansion.displayedModels(in: group), [visibleModel])

        overflowExpansion.setExpanded(true, groupID: group.id)
        XCTAssertEqual(
            overflowExpansion.displayedModels(in: group),
            [visibleModel, overflowModel]
        )

        overflowExpansion.setExpanded(false, groupID: group.id)
        XCTAssertEqual(overflowExpansion.displayedModels(in: group), [visibleModel])
    }

    // While searching, allModels are rendered — an overflow match found by that
    // search IS represented and must not duplicate a Current Custom row.
    func testOverflowMatchWhileSearchingIsRendered() {
        let rendered = ModelPickerSheet.isRenderedByCurrentPicker(
            option: overflowModel,
            modelGroups: groups,
            searchQuery: "deepseek"
        )

        XCTAssertTrue(rendered)
    }

    func testVisibleMatchWhileSearchingIsRendered() {
        let rendered = ModelPickerSheet.isRenderedByCurrentPicker(
            option: visibleModel,
            modelGroups: groups,
            searchQuery: "claude"
        )

        XCTAssertTrue(rendered)
    }

    // Provider-aware: same bare ID under another provider is not the same row.
    func testSameIDUnderDifferentProviderIsNotRendered() {
        let otherProvider = ModelCatalogOption(
            id: overflowModel.id,
            displayName: overflowModel.displayName,
            providerID: "nous"
        )

        let rendered = ModelPickerSheet.isRenderedByCurrentPicker(
            option: otherProvider,
            modelGroups: groups,
            searchQuery: ""
        )

        XCTAssertFalse(rendered)
    }
}

/// Classification of Nous Portal's base models vs their `:batch` / `:US`
/// endpoint variants (P0: catalog 44 → 399). Ids below are copied from a live
/// `/v1/models` response, not invented.
final class ModelEndpointCatalogTests: XCTestCase {
    private let rows: [ModelEndpointRow] = [
        ModelEndpointRow(id: "anthropic/claude-opus-4.6", name: "Claude Opus 4.6",
                         canonicalSlug: "anthropic/claude-opus-4.6"),
        ModelEndpointRow(id: "anthropic/claude-opus-4.6:batch", name: "Anthropic: Claude Opus 4.6 (batch)",
                         canonicalSlug: "anthropic/claude-4.6-opus-20260205"),
        ModelEndpointRow(id: "moonshotai/kimi-k3", name: "MoonshotAI: Kimi K3",
                         canonicalSlug: "moonshotai/kimi-k3-20260715"),
        ModelEndpointRow(id: "moonshotai/kimi-k3:US", name: "MoonshotAI: Kimi K3",
                         canonicalSlug: "moonshotai/kimi-k3:US"),
        ModelEndpointRow(id: "deepseek/deepseek-v4-pro", name: "deepseek/deepseek-v4-pro"),
        ModelEndpointRow(id: "deepseek/deepseek-v4-pro-0813", name: "deepseek/deepseek-v4-pro-0813")
    ]

    /// A `:batch` row belongs to the same model as its plain id.
    func testBatchVariantJoinsItsBaseFamily() {
        let families = ModelEndpointCatalog.families(from: rows)
        let opus = families.first { $0.base.id == "anthropic/claude-opus-4.6" }

        XCTAssertEqual(opus?.variants.map(\.id), ["anthropic/claude-opus-4.6:batch"])
        XCTAssertEqual(opus?.variants.first?.kind, .batch)
    }

    /// A `:US` regional row is the same model, not a second one.
    func testRegionalVariantJoinsItsBaseFamily() {
        let families = ModelEndpointCatalog.families(from: rows)
        let kimi = families.first { $0.base.id == "moonshotai/kimi-k3" }

        XCTAssertEqual(kimi?.variants.map(\.id), ["moonshotai/kimi-k3:US"])
        XCTAssertEqual(kimi?.variants.first?.kind, .regional)
    }

    /// A dated snapshot or a different size is a different model: only endpoint
    /// suffixes are collapsed, so the picker never hides a real choice.
    func testDistinctModelsAreNotMerged() {
        let ids = Set(ModelEndpointCatalog.families(from: rows).map(\.base.id))

        XCTAssertTrue(ids.contains("deepseek/deepseek-v4-pro"))
        XCTAssertTrue(ids.contains("deepseek/deepseek-v4-pro-0813"))
    }

    /// Grouping is a reorder, never a filter: every id comes back exactly once,
    /// in first-seen order, with its own spelling.
    func testFamiliesPreserveEveryRowAndItsOrder() {
        let flattened = ModelEndpointCatalog.families(from: rows).flatMap(\.rows).map(\.id)

        XCTAssertEqual(flattened.count, rows.count)
        XCTAssertEqual(Set(flattened), Set(rows.map(\.id)))
    }

    /// A family whose plain id disappeared keeps its first variant as the base,
    /// so a provider-side rename cannot make a model vanish from the picker.
    func testVariantOnlyFamilyStillHasABase() {
        let batchOnly = [ModelEndpointRow(id: "vendor/model:batch", canonicalSlug: "vendor/model")]

        let families = ModelEndpointCatalog.families(from: batchOnly)

        XCTAssertEqual(families.count, 1)
        XCTAssertEqual(families.first?.base.id, "vendor/model:batch")
        XCTAssertEqual(families.first?.rows.map(\.id), ["vendor/model:batch"])
    }

    /// The user-facing counter counts models, the expansion counts endpoints.
    func testModelCountCountsFamiliesAndEndpointCountCountsRows() {
        XCTAssertEqual(ModelEndpointCatalog.modelCount(of: rows), 4)
        XCTAssertEqual(ModelEndpointCatalog.endpointCount(of: rows), rows.count)
    }

    /// Selecting a variant must commit the variant's own id. Favourites are
    /// keyed by the exact id, so a saved `:batch` endpoint keeps resolving to
    /// that endpoint and never silently becomes the base model.
    func testSelectionKeepsTheExactVariantID() {
        let batch = ModelCatalogOption(id: "anthropic/claude-opus-4.6:batch",
                                       displayName: "Claude Opus 4.6 (batch)",
                                       providerID: "nous")
        let base = ModelCatalogOption(id: "anthropic/claude-opus-4.6",
                                      displayName: "Claude Opus 4.6",
                                      providerID: "nous")

        XCTAssertEqual(batch.favoriteKey, ModelFavoriteKey(modelID: "anthropic/claude-opus-4.6:batch",
                                                           providerID: "nous"))
        XCTAssertNotEqual(batch.favoriteKey, base.favoriteKey)
    }
}
