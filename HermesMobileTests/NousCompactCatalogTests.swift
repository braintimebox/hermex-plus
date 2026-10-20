import XCTest
@testable import HermesMobile

/// The compact Nous list must shrink the provider catalog without losing a
/// single model: whatever leaves the primary list has to reappear in overflow.
final class NousCompactCatalogTests: XCTestCase {
    private func group(
        name: String = "Nous Portal",
        providerID: String = "nous",
        ids: [String]
    ) -> ModelCatalogGroup {
        ModelCatalogGroup(
            id: "\(providerID)-group",
            name: name,
            providerID: providerID,
            models: ids.map { ModelCatalogOption(id: $0, displayName: $0, providerID: providerID) },
            extraModels: []
        )
    }

    func testCompactListKeepsOnlyTheAgreedIDsInThePrimaryList() {
        let allowed = Array(NousCompactCatalog.modelIDs.prefix(3))
        let others = ["vendor/not-listed-1", "vendor/not-listed-2", "vendor/not-listed-3"]
        let compacted = NousCompactCatalog.compact(group(ids: allowed + others))

        XCTAssertEqual(Set(compacted.models.map(\.id)), Set(allowed))
        XCTAssertEqual(Set(compacted.extraModels.map(\.id)), Set(others))
    }

    func testCompactListNeverDropsAModel() {
        let ids = Array(NousCompactCatalog.modelIDs.prefix(5)) + ["vendor/a", "vendor/b"]
        let original = group(ids: ids)
        let compacted = NousCompactCatalog.compact(original)

        XCTAssertEqual(
            Set(compacted.allModels.map(\.id)),
            Set(original.allModels.map(\.id)),
            "a model that left the primary list must stay reachable through overflow"
        )
        XCTAssertEqual(compacted.allModels.count, original.allModels.count)
    }

    func testDerivedSlicesAreNotCompacted() {
        // "Nous Portal · Free" is a category view; compacting it would empty the
        // FREE section, so only the base provider group is touched.
        let ids = ["vendor/a", "vendor/b"]
        let derived = group(name: "Nous Portal · Free", ids: ids)
        XCTAssertEqual(NousCompactCatalog.compact(derived).models.map(\.id), ids)
    }

    func testOtherProvidersAreUntouched() {
        let ids = ["vendor/a", "vendor/b"]
        let deepseek = group(name: "DeepSeek", providerID: "deepseek", ids: ids)
        XCTAssertEqual(NousCompactCatalog.compact(deepseek).models.map(\.id), ids)
    }

    func testPrefixedServerIDsMatchTheBareID() {
        let bare = "anthropic/claude-opus-5"
        XCTAssertTrue(NousCompactCatalog.isCompact("@nous:\(bare)"))
        XCTAssertTrue(NousCompactCatalog.isCompact(bare))
        XCTAssertFalse(NousCompactCatalog.isCompact("vendor/unknown-model"))
    }

    func testCandidateListExcludesBatchRegionalAndRetiredModels() {
        XCTAssertEqual(NousCompactCatalog.modelIDs.count, 59)
        XCTAssertFalse(NousCompactCatalog.modelIDs.contains("stealth/space-bunny-alpha"))
        XCTAssertTrue(NousCompactCatalog.modelIDs.allSatisfy { !$0.hasSuffix(":batch") && !$0.hasSuffix(":US") })
        // Free models that only produced reasoning tokens, or that failed outright.
        XCTAssertFalse(NousCompactCatalog.modelIDs.contains("poolside/laguna-xs-2.1:free"))
        XCTAssertFalse(NousCompactCatalog.modelIDs.contains("stepfun/step-3.7-flash:free"))
        XCTAssertFalse(NousCompactCatalog.modelIDs.contains("meituan/longcat-2.0:free"))
        XCTAssertFalse(NousCompactCatalog.modelIDs.contains("meituan/longcat-2.5-preview:free"))
    }

    func testVerifiedFreeModelsAreIncluded() {
        XCTAssertTrue(NousCompactCatalog.modelIDs.contains("poolside/laguna-s-2.1:free"))
        XCTAssertTrue(NousCompactCatalog.modelIDs.contains("upstage/solar-mini4:free"))
        XCTAssertTrue(NousCompactCatalog.modelIDs.contains("reflection/beam-1.0-501b-a23b:free"))
    }
}
