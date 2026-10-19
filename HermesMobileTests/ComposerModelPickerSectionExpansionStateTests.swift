import XCTest
@testable import HermesMobile

final class ComposerModelPickerSectionExpansionStateTests: XCTestCase {
    func testSectionsStartCollapsedWhenSearchIsEmpty() {
        let state = ComposerModelPickerSectionExpansionState()

        XCTAssertFalse(state.isExpanded(groupID: "openai"))
    }

    func testManualExpansionPersistsWhileSearchIsEmpty() {
        var state = ComposerModelPickerSectionExpansionState()

        state.setExpanded(true, groupID: "openai")

        XCTAssertTrue(state.isExpanded(groupID: "openai"))

        state.setExpanded(false, groupID: "openai")

        XCTAssertFalse(state.isExpanded(groupID: "openai"))
    }

    func testSearchAutoExpandsAllSections() {
        var state = ComposerModelPickerSectionExpansionState()

        state.updateSearchText("gpt")

        XCTAssertTrue(state.isExpanded(groupID: "openai"))
        XCTAssertTrue(state.isExpanded(groupID: "anthropic"))
    }

    func testManualCollapseDuringSearchDoesNotChangeEmptySearchState() {
        var state = ComposerModelPickerSectionExpansionState()
        state.setExpanded(true, groupID: "openai")
        state.updateSearchText("gpt")

        state.setExpanded(false, groupID: "openai")

        XCTAssertFalse(state.isExpanded(groupID: "openai"))

        state.updateSearchText("")

        XCTAssertTrue(state.isExpanded(groupID: "openai"))
    }

    func testChangingSearchQueryReexpandsCollapsedSearchSections() {
        var state = ComposerModelPickerSectionExpansionState()
        state.updateSearchText("gpt")
        state.setExpanded(false, groupID: "openai")
        state.setExpanded(false, groupID: "anthropic")

        XCTAssertFalse(state.isExpanded(groupID: "openai"))
        XCTAssertFalse(state.isExpanded(groupID: "anthropic"))

        state.updateSearchText("gpt 5")

        XCTAssertTrue(state.isExpanded(groupID: "openai"))
        XCTAssertTrue(state.isExpanded(groupID: "anthropic"))
    }

    func testGroupExpansionStateIsIndependentAcrossSearchBoundary() {
        var state = ComposerModelPickerSectionExpansionState()
        state.setExpanded(true, groupID: "openai")

        XCTAssertTrue(state.isExpanded(groupID: "openai"))
        XCTAssertFalse(state.isExpanded(groupID: "anthropic"))

        state.updateSearchText("claude")
        state.setExpanded(false, groupID: "anthropic")

        XCTAssertTrue(state.isExpanded(groupID: "openai"))
        XCTAssertFalse(state.isExpanded(groupID: "anthropic"))

        state.updateSearchText("")

        XCTAssertTrue(state.isExpanded(groupID: "openai"))
        XCTAssertFalse(state.isExpanded(groupID: "anthropic"))
    }

    func testWhitespaceOnlySearchUsesEmptySearchState() {
        var state = ComposerModelPickerSectionExpansionState()
        state.setExpanded(true, groupID: "openai")
        state.updateSearchText("gpt")
        state.setExpanded(false, groupID: "openai")

        XCTAssertFalse(state.isExpanded(groupID: "openai"))

        state.updateSearchText("   ")

        XCTAssertTrue(state.isExpanded(groupID: "openai"))
        XCTAssertFalse(state.isExpanded(groupID: "anthropic"))
    }

    // MARK: Nothing expands by itself

    /// Primary catalogs (OpenAI, Anthropic) and the OpenAI Codex provider used to
    /// be reopened by the sheet on appear. The state now has no such notion: a
    /// fresh picker knows no expanded group at all.
    func testPrimaryAndCodexProvidersStartCollapsed() {
        let state = ComposerModelPickerSectionExpansionState()

        for groupID in ["openai", "openai-codex", "anthropic", "openrouter", "nous"] {
            XCTAssertFalse(state.isExpanded(groupID: groupID), groupID)
        }
    }

    /// Reopening the sheet builds a new state — the previous session's expansion
    /// must not survive it, otherwise the sheet reopens half-open.
    func testReopeningThePickerStartsCollapsed() {
        var first = ComposerModelPickerSectionExpansionState()
        first.setExpanded(true, groupID: "openrouter")
        first.setExpanded(true, groupID: "openai-codex")
        XCTAssertTrue(first.isExpanded(groupID: "openrouter"))

        let reopened = ComposerModelPickerSectionExpansionState()

        XCTAssertFalse(reopened.isExpanded(groupID: "openrouter"))
        XCTAssertFalse(reopened.isExpanded(groupID: "openai-codex"))
    }

    /// Expanding one provider says nothing about the others.
    func testManualExpansionLeavesEveryOtherGroupCollapsed() {
        var state = ComposerModelPickerSectionExpansionState()

        state.setExpanded(true, groupID: "nous")

        XCTAssertTrue(state.isExpanded(groupID: "nous"))
        XCTAssertFalse(state.isExpanded(groupID: "openrouter"))
        XCTAssertFalse(state.isExpanded(groupID: "openai-codex"))
    }

    /// Search renders its own flat result set, so it must not depend on, nor
    /// disturb, the expansion the user left behind.
    func testSearchExpandsResultsAndKeepsManualState() {
        var state = ComposerModelPickerSectionExpansionState()
        state.setExpanded(true, groupID: "nous")

        state.updateSearchText("deepseek")
        XCTAssertTrue(state.isExpanded(groupID: "openrouter"))

        state.updateSearchText("")

        XCTAssertTrue(state.isExpanded(groupID: "nous"))
        XCTAssertFalse(state.isExpanded(groupID: "openrouter"))
    }
}
