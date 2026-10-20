import Foundation
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

/// Guards the behaviour no test of `ComposerModelPickerSectionExpansionState`
/// can see.
///
/// The sheet used to reopen provider groups by itself: `onAppear` and
/// `onChange(of: modelGroups)` expanded every "primary" catalog and the group
/// holding the current selection. That call lived in the view body, not in the
/// state struct — which is why state-only tests pass on both sides of the fix.
///
/// This guard reads production sources. That is a deliberate, narrow exception
/// to the "no source-reading tests" rule: the view exposes no seam for its
/// expansion state, and the alternative — screenshot the list and OCR it — is
/// this suite's flakiest mechanism and would only prove a negative as reliably
/// as the recognizer. The guard cannot prove the UI looks right; it proves the
/// automatic call has not come back. It will not catch the same behaviour
/// reintroduced under another name.
final class ModelPickerAutoExpansionGuardTests: XCTestCase {
    /// Calls that expanded a group without the user touching it.
    /// `expandPrimaryProviderSections` is the removed helper; the second string
    /// is the only other call that ever expanded a group outside the disclosure
    /// binding's own setter.
    private static let forbiddenCalls = [
        "expandPrimaryProviderSections",
        "sectionExpansion.setExpanded(true"
    ]

    func testPickerNeverExpandsGroupsOnItsOwn() throws {
        let sources = productionSwiftSources()
        XCTAssertGreaterThan(sources.count, 100,
                             "scan reached almost no sources — the guard would pass vacuously")

        var offenders: [String] = []
        for url in sources {
            let text = try String(contentsOf: url, encoding: .utf8)
            // Comment lines are skipped so a note that merely names the old
            // helper (this file's own doc comment, a changelog line, a TODO)
            // does not turn the guard red.
            for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("*"), !code.hasPrefix("/*") else { continue }
                for call in Self.forbiddenCalls where code.contains(call) {
                    offenders.append("\(url.lastPathComponent):\(offset + 1) \(call)")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Model Picker expands groups without the user: \(offenders.joined(separator: ", "))"
        )
    }

    private func productionSwiftSources() -> [URL] {
        var root = URL(fileURLWithPath: #filePath)
        root.deleteLastPathComponent()          // HermesMobileTests
        root.deleteLastPathComponent()          // repository root

        let appDirectory = root.appendingPathComponent("HermesMobile", isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: appDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return walker
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !$0.path.contains("/Tests/") }
    }
}
