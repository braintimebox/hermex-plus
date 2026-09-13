import XCTest
@testable import HermesMobile

final class ChatMessageActionMenuTests: XCTestCase {
    func testActionRowsRemainAvailableWithoutSettledTurnTimestamp() {
        XCTAssertTrue(TranscriptMessageMetaPolicy.showsRow(hasActions: true, hasTimestamp: false))
        XCTAssertTrue(TranscriptMessageMetaPolicy.showsRow(hasActions: false, hasTimestamp: true))
        XCTAssertFalse(TranscriptMessageMetaPolicy.showsRow(hasActions: false, hasTimestamp: false))
    }

    func testAssistantMenuListsAssistantActionsInOrder() throws {
        let menu = try makeMenu(role: "assistant")

        // Reply / Forward / Save are ours — upstream's menu stopped at Fork.
        // Pinning the full list here is what makes a future sync that drops one
        // of them fail loudly instead of silently shrinking the menu.
        XCTAssertEqual(menu.items.map(\.kind), [.listen, .regenerate, .fork, .reply, .forward, .save])
        XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
    }

    func testUserMenuListsUserActionsInOrder() throws {
        let menu = try makeMenu(role: "user")

        XCTAssertEqual(menu.items.map(\.kind), [.edit, .fork, .copy, .reply, .forward, .save])
    }

    func testMutatingActionsDisableWhileStreaming() throws {
        let menu = try makeMenu(role: "assistant", hasActiveStream: true)

        let enabledByKind = Dictionary(uniqueKeysWithValues: menu.items.map { ($0.kind, $0.isEnabled) })
        XCTAssertEqual(enabledByKind[.regenerate], false)
        XCTAssertEqual(enabledByKind[.fork], false)
        XCTAssertEqual(enabledByKind[.listen], true)

        let uiMenu = menu.uiMenu()
        let disabledTitles = uiMenu.children.compactMap { $0 as? UIAction }
            .filter { $0.attributes.contains(.disabled) }
            .map(\.title)
        // Reply / Forward / Save carry the tapped message into another screen, so
        // they are held while a stream is live and the transcript is still shifting.
        XCTAssertEqual(disabledTitles, ["Regenerate Response", "Fork From Here", "Reply", "Forward", "Save"])
    }

    func testListenItemReflectsListeningState() throws {
        let idle = try makeMenu(role: "assistant")
        XCTAssertEqual(idle.items.first?.title, "Listen")

        let listening = try makeMenu(role: "assistant", listeningMessageID: "message-1")
        XCTAssertEqual(listening.items.first?.title, "Stop Listening")
    }

    func testCachedResponseRetainsListenButDisablesServerMutations() throws {
        let menu = try makeMenu(role: "assistant", isViewingCachedData: true)
        XCTAssertEqual(menu.items.filter(\.isEnabled).map(\.kind), [.listen])
    }

    func testPendingResponseMutationsAreDisabled() throws {
        let menu = try makeMenu(role: "assistant", isMutating: true)
        // Listen always, plus ours: a pending regenerate/fork does not change what
        // the message says, so Reply / Forward / Save stay available.
        XCTAssertEqual(menu.items.filter(\.isEnabled).map(\.kind), [.listen, .reply, .forward, .save])
    }

    func testPerformRoutesToTheMatchingCallback() throws {
        var copied: MessageActionContext?
        let menu = try makeMenu(role: "user", onCopy: { copied = $0 })

        let copy = try XCTUnwrap(menu.items.first { $0.kind == .copy })
        copy.perform()

        XCTAssertEqual(copied?.messageID, "message-1")
    }

    private func makeMenu(
        role: String,
        listeningMessageID: String? = nil,
        hasActiveStream: Bool = false,
        isViewingCachedData: Bool = false,
        isMutating: Bool = false,
        onCopy: @escaping (MessageActionContext) -> Void = { _ in }
    ) throws -> ChatMessageActionMenu {
        let message = ChatMessage(
            role: role,
            content: "Hello there",
            timestamp: 1_770_000_000,
            messageId: "message-1"
        )
        let context = try XCTUnwrap(
            MessageActionContext(message: message, visibleIndex: 0, messagesOffset: 0)
        )
        return ChatMessageActionMenu(
            context: context,
            listeningMessageID: listeningMessageID,
            isViewingCachedData: isViewingCachedData,
            hasActiveStream: hasActiveStream,
            isRegeneratingMessage: isMutating,
            isEditingMessage: false,
            isForkingMessage: isMutating,
            onToggleListening: { _ in },
            onRegenerate: { _ in },
            onEdit: { _ in },
            onFork: { _ in },
            onCopy: onCopy,
            onSelectText: nil,
            onReply: { _ in },
            onForward: { _ in },
            onSave: { _ in },
            onPin: nil,
            isPinned: false
        )
    }
}
