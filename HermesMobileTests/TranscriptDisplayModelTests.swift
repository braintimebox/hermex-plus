import XCTest
import AVFoundation
import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers
@testable import HermesMobile

final class TranscriptMessageTests: XCTestCase {
    func testTranscriptMessagesHideToolRowsAndPreserveLoadedIndices() {
        let messages = [
            ChatMessage(role: "user", content: "Plan it", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Working on it", timestamp: 2, messageId: "a1"),
            ChatMessage(
                role: "tool",
                content: #"{"success":true,"diff":"..."}"#,
                timestamp: 3,
                messageId: "t1",
                toolCallId: "tool-1"
            ),
            ChatMessage(role: "assistant", content: "Done. Here's what changed.", timestamp: 4, messageId: "a2")
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(from: messages)

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 1, 3])
        XCTAssertEqual(transcriptMessages.map(\.message.id), ["u1", "a1", "a2"])
    }

    func testTranscriptMessagesCanHideActiveStreamingAssistantTurn() {
        let messages = [
            ChatMessage(role: "user", content: "Use tools", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: "stream-1"),
            ChatMessage(
                role: "tool",
                content: #"{"success":true}"#,
                timestamp: 3,
                messageId: "t1",
                toolCallId: "tool-1"
            ),
            ChatMessage(role: "assistant", content: "Older answer", timestamp: 4, messageId: "a2")
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(
            from: messages,
            hidingStreamingAssistantID: "stream-1"
        )

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 3])
        XCTAssertEqual(transcriptMessages.map(\.message.id), ["u1", "a2"])
    }

    func testTranscriptMessagesKeepStreamingAssistantAnchorStableAcrossContentUpdates() {
        let initialMessages = [
            ChatMessage(role: "user", content: "Write a long answer", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: "stream-1")
        ]
        let updatedMessages = [
            ChatMessage(role: "user", content: "Write a long answer", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "First streamed token.", timestamp: 2, messageId: "stream-1")
        ]

        let initialTranscriptMessages = ChatViewModel.transcriptMessages(from: initialMessages)
        let updatedTranscriptMessages = ChatViewModel.transcriptMessages(from: updatedMessages)

        XCTAssertEqual(initialTranscriptMessages.map(\.anchorID), ["u1", "stream-1"])
        XCTAssertEqual(updatedTranscriptMessages.map(\.anchorID), ["u1", "stream-1"])
        XCTAssertEqual(initialTranscriptMessages.map(\.id), updatedTranscriptMessages.map(\.id))
        XCTAssertEqual(initialTranscriptMessages.map(\.loadedIndex), updatedTranscriptMessages.map(\.loadedIndex))
    }

    func testTranscriptMessagesKeepRenderIDStableWhenServerReplacesStreamingAssistantID() {
        let streamingMessages = [
            ChatMessage(role: "user", content: "Finish the summary", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Working summary", timestamp: 2, messageId: "stream-1")
        ]
        let completedMessages = [
            ChatMessage(role: "user", content: "Finish the summary", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Final summary", timestamp: 2, messageId: "assistant-1")
        ]

        let streamingTranscriptMessages = ChatViewModel.transcriptMessages(from: streamingMessages)
        let completedTranscriptMessages = ChatViewModel.transcriptMessages(from: completedMessages)

        XCTAssertEqual(streamingTranscriptMessages.map(\.id), completedTranscriptMessages.map(\.id))
        XCTAssertEqual(streamingTranscriptMessages.map(\.anchorID), ["u1", "stream-1"])
        XCTAssertEqual(completedTranscriptMessages.map(\.anchorID), ["u1", "assistant-1"])
    }

    func testTranscriptMessagesUseRawAnchorForNilMessageIDsIndependentOfContent() {
        let initialMessages = [
            ChatMessage(role: "user", content: "Hello", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: nil)
        ]
        let updatedMessages = [
            ChatMessage(role: "user", content: "Hello", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "A streamed response.", timestamp: 2, messageId: nil)
        ]

        let initialTranscriptMessages = ChatViewModel.transcriptMessages(
            from: initialMessages,
            messageOffset: 10
        )
        let updatedTranscriptMessages = ChatViewModel.transcriptMessages(
            from: updatedMessages,
            messageOffset: 10
        )

        XCTAssertEqual(initialTranscriptMessages.map(\.anchorID), ["raw:10", "raw:11"])
        XCTAssertEqual(updatedTranscriptMessages.map(\.anchorID), ["raw:10", "raw:11"])
        XCTAssertEqual(initialTranscriptMessages.map(\.id), updatedTranscriptMessages.map(\.id))
    }

    func testTranscriptMessagesKeepRenderIDsStableWhenOlderMessagesPrepend() {
        let initialWindow = [
            ChatMessage(role: "assistant", content: "Earlier answer", timestamp: 1, messageId: "a1"),
            ChatMessage(role: "user", content: "Follow up", timestamp: 2, messageId: "u2"),
            ChatMessage(role: "assistant", content: "Latest answer", timestamp: 3, messageId: "a2")
        ]
        let expandedWindow = [
            ChatMessage(role: "user", content: "First question", timestamp: 0, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Earlier answer", timestamp: 1, messageId: "a1"),
            ChatMessage(role: "user", content: "Follow up", timestamp: 2, messageId: "u2"),
            ChatMessage(role: "assistant", content: "Latest answer", timestamp: 3, messageId: "a2")
        ]

        let initialTranscriptMessages = ChatViewModel.transcriptMessages(
            from: initialWindow,
            messageOffset: 1
        )
        let expandedTranscriptMessages = ChatViewModel.transcriptMessages(
            from: expandedWindow,
            messageOffset: 0
        )

        XCTAssertEqual(initialTranscriptMessages.map(\.id), ["transcript:1", "transcript:2", "transcript:3"])
        XCTAssertEqual(expandedTranscriptMessages.map(\.id), ["transcript:0", "transcript:1", "transcript:2", "transcript:3"])

        let initialRenderIDsByMessageID = Dictionary(
            uniqueKeysWithValues: initialTranscriptMessages.compactMap { transcriptMessage in
                transcriptMessage.message.messageId.map { ($0, transcriptMessage.id) }
            }
        )
        for expandedTranscriptMessage in expandedTranscriptMessages {
            guard let messageID = expandedTranscriptMessage.message.messageId,
                  let initialRenderID = initialRenderIDsByMessageID[messageID]
            else { continue }

            XCTAssertEqual(
                expandedTranscriptMessage.id,
                initialRenderID,
                "renderID should stay stable for message \(messageID)"
            )
        }
    }

    func testTranscriptMessagesPreserveMessagesWithNilMessageIDsWhenNoStreamingTurnHidden() {
        let messages = [
            ChatMessage(role: "user", content: "Hello", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "Hi", timestamp: 2, messageId: nil),
            ChatMessage(
                role: "tool",
                content: #"{"success":true}"#,
                timestamp: 3,
                messageId: nil,
                toolCallId: "tool-1"
            )
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(from: messages)

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 1])
        XCTAssertEqual(transcriptMessages.map(\.message.role), ["user", "assistant"])
    }
}

final class ChatTranscriptDisplaySettingsTests: XCTestCase {
    func testTypingIndicatorStaysHiddenBehindVisibleThinkingAndToolCards() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            liveReasoningText: "Inspecting files",
            hasLiveToolCalls: false,
            showsThinkingAndToolCards: true
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            liveReasoningText: "",
            hasLiveToolCalls: true,
            showsThinkingAndToolCards: true
        ))
    }

    func testTypingIndicatorShowsWhenHiddenCardsAreOnlyLiveActivity() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            liveReasoningText: "Inspecting files",
            hasLiveToolCalls: true,
            showsThinkingAndToolCards: false
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: true,
            liveReasoningText: "Inspecting files",
            hasLiveToolCalls: true,
            showsThinkingAndToolCards: false
        ))
    }

    func testTypingIndicatorHidesBehindPendingClarificationPrompt() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            hasPendingClarificationPrompt: true,
            liveReasoningText: "",
            hasLiveToolCalls: false,
            showsThinkingAndToolCards: false
        ))
    }

    func testStreamingBubbleRenderingDoesNotMatchNilMessageIDs() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "user",
            messageID: nil,
            streamingAssistantMessageID: nil
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageID: nil,
            streamingAssistantMessageID: nil
        ))
    }

    func testStreamingBubbleRenderingMatchesActiveStreamingAssistant() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageID: "stream-1",
            streamingAssistantMessageID: "stream-1"
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageID: "assistant-1",
            streamingAssistantMessageID: "stream-1"
        ))
    }

    func testCardExpansionFollowsStartExpandedPreferenceUntilToggled() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: nil, startsExpanded: false))
        XCTAssertTrue(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: nil, startsExpanded: true))
    }

    func testCardExpansionTapOverrideWinsOverPreference() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: true, startsExpanded: false))
        XCTAssertFalse(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: false, startsExpanded: true))
    }

    func testCardStartExpandedKeysAreStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey,
            "chatTranscript.thinkingCardsStartExpanded"
        )
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.toolCardsStartExpandedKey,
            "chatTranscript.toolCardsStartExpanded"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey,
            ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey
        )
    }

    func testHidesAttachmentPathsKeyIsStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.hidesAttachmentPathsKey,
            "chatTranscript.hidesAttachmentPaths"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.hidesAttachmentPathsKey,
            ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey
        )
    }

    func testAssistantTurnTimestampsKeyIsStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey,
            "chatTranscript.showsAssistantTurnTimestamps"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey,
            ChatTranscriptDisplaySettings.hidesAttachmentPathsKey
        )
    }

    func testResponseSpeedKeyIsStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.showsResponseSpeedKey,
            "chatTranscript.showsResponseSpeed"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.showsResponseSpeedKey,
            ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey
        )
    }

    func testTimestampAndResponseSpeedTogglesAreIndependent() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: false,
            showsResponseSpeed: false,
            hasResponseSpeed: true
        ))
        XCTAssertTrue(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: true,
            showsResponseSpeed: false,
            hasResponseSpeed: true
        ))
        XCTAssertTrue(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: false,
            showsResponseSpeed: true,
            hasResponseSpeed: true
        ))
        XCTAssertTrue(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: true,
            showsResponseSpeed: true,
            hasResponseSpeed: true
        ))
    }

    func testInvalidResponseSpeedAloneDoesNotCreateHeaderRow() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: false,
            showsResponseSpeed: true,
            hasResponseSpeed: false
        ))
    }

    func testAssistantTurnHeaderShowsForAssistantTextTurnWhenEnabled() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: true
        ))
    }

    func testAssistantTurnHeaderHiddenWhenToggleOff() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: false
        ))
    }

    func testAssistantTurnHeaderHiddenForEmptyOrToolOnlyAssistantRow() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: false,
            isEnabled: true
        ))
    }

    func testAssistantTurnHeaderHiddenForNonAssistantRoles() {
        for role in ["user", "system", "tool", "local_assistant", "local_notice"] {
            XCTAssertFalse(
                ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
                    role: role,
                    hasTextContent: true,
                    isEnabled: true
                ),
                "Header must not render for role \(role)"
            )
        }

        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: nil,
            hasTextContent: true,
            isEnabled: true
        ))
    }

    func testContentWithoutAttachedFilesMarkerStripsTrailingMarker() {
        // Mirrors the exact format PendingAttachment.chatMessageText appends.
        let sent = "Analyze these files\n\n[Attached files: /tmp/workspace/sample.html, /tmp/workspace/image.jpg]"
        XCTAssertEqual(
            MessageAttachment.contentWithoutAttachedFilesMarker(in: sent),
            "Analyze these files"
        )
    }

    func testContentWithoutAttachedFilesMarkerReturnsEmptyForAttachmentOnlyMessage() {
        // No typed draft: the whole content is just the appended marker.
        let sent = "\n\n[Attached files: /tmp/workspace/image.jpg]"
        XCTAssertEqual(MessageAttachment.contentWithoutAttachedFilesMarker(in: sent), "")
    }

    func testContentWithoutAttachedFilesMarkerPreservesInteriorNewlines() {
        let sent = "line one\nline two\n\n[Attached files: /tmp/a.png]"
        XCTAssertEqual(
            MessageAttachment.contentWithoutAttachedFilesMarker(in: sent),
            "line one\nline two"
        )
    }

    func testContentWithoutAttachedFilesMarkerLeavesPlainMessageUnchanged() {
        let plain = "Just a normal message with no attachments"
        XCTAssertEqual(MessageAttachment.contentWithoutAttachedFilesMarker(in: plain), plain)
    }

    func testContentWithoutAttachedFilesMarkerIgnoresMarkerWithTrailingText() {
        // The parser only treats the marker as a suffix; trailing prose means it
        // is not a real attachment marker, so the content is left untouched.
        let content = "hello\n\n[Attached files: /tmp/a.png] and then more text"
        XCTAssertEqual(MessageAttachment.contentWithoutAttachedFilesMarker(in: content), content)
    }
}

final class ChatActiveRunStatusPolicyTests: XCTestCase {
    func testStatusHidesWhenTranscriptBottomIsVisible() {
        XCTAssertNil(ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: true,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: true
        ))
    }

    func testStatusShowsActiveRunWhenScrolledAwayFromBottom() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: true,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .active)
        XCTAssertEqual(presentation?.label, "Hermes is working")
    }

    func testStatusShowsStartingBeforeStreamIDExists() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: true,
            hasActiveStream: false,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .starting)
    }

    func testStatusPrioritizesRecoveryStateOverGenericActiveRun() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: true,
            activeStreamRecoveryState: .reconnecting,
            isCancellingStream: false,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .reconnecting)
        XCTAssertEqual(presentation?.accessibilityLabel, "Hermes is reconnecting the response stream")
    }

    func testStatusPrioritizesCancellationOverOtherStates() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: true,
            hasActiveStream: true,
            activeStreamRecoveryState: .checking,
            isCancellingStream: true,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .stopping)
    }

    func testStatusHidesWhenIdleAndNoRunIsStarting() {
        XCTAssertNil(ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: false,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: false
        ))
    }
}

final class AssistantTurnTimestampFormatterTests: XCTestCase {
    // 2021-01-01 14:14:00 UTC
    private let fixedTimestamp: Double = 1_609_510_440
    private let utc = TimeZone(identifier: "UTC")!

    func testFormatsTwelveHourLocaleAsShortTime() {
        let result = AssistantTurnTimestampFormatter.shortTime(
            forUnixTimestamp: fixedTimestamp,
            locale: Locale(identifier: "en_US"),
            timeZone: utc
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("2:14") == true, "Expected 12h time, got \(result ?? "nil")")
        XCTAssertTrue(result?.contains("PM") == true, "Expected PM marker, got \(result ?? "nil")")
    }

    func testFormatsTwentyFourHourLocaleAsShortTime() {
        let result = AssistantTurnTimestampFormatter.shortTime(
            forUnixTimestamp: fixedTimestamp,
            locale: Locale(identifier: "en_GB"),
            timeZone: utc
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("14:14") == true, "Expected 24h time, got \(result ?? "nil")")
        XCTAssertFalse(result?.contains("PM") == true, "24h time must not carry a PM marker")
    }

    func testReturnsNilForNilTimestamp() {
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: nil))
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(
            forUnixTimestamp: nil,
            locale: Locale(identifier: "en_US"),
            timeZone: utc
        ))
    }

    func testReturnsNilForNonFiniteTimestamp() {
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: .nan))
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: .infinity))
    }

    func testCurrentLocaleOverloadFormatsFiniteTimestamp() {
        XCTAssertNotNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: fixedTimestamp))
    }
}

final class ResponseSpeedFormatterTests: XCTestCase {
    func testFormatsOneDecimalWithCompactAndAccessibleUnits() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(ResponseSpeedFormatter.compactText(12.34, locale: locale), "12.3 t/s")
        XCTAssertEqual(
            ResponseSpeedFormatter.accessibilityText(12.34, locale: locale),
            "12.3 tokens per second"
        )
    }

    func testReturnsNilForMissingNonPositiveOrNonFiniteValues() {
        XCTAssertNil(ResponseSpeedFormatter.compactText(nil))
        XCTAssertNil(ResponseSpeedFormatter.compactText(0))
        XCTAssertNil(ResponseSpeedFormatter.compactText(-1))
        XCTAssertNil(ResponseSpeedFormatter.compactText(.infinity))
        XCTAssertNil(ResponseSpeedFormatter.compactText(.nan))
    }
}

/// F1 Stable Identity regression invariants (3.2.0).
///
/// Guards the core contract: a `serverID` must SURVIVE every reconstruction,
/// reach `TranscriptMessage.id`, never be replaced by a positional/digest
/// fallback when a stable id exists, and duplicate serverIDs must stay unique
/// with a deterministic, position-independent discriminator.
final class StableIdentityInvariantTests: XCTestCase {

    private func msg(
        id: Int? = nil,
        messageId: String? = "mid-\(UUID().uuidString)",
        role: String = "assistant",
        content: String = "hello"
    ) -> ChatMessage {
        ChatMessage(role: role, content: content, timestamp: 1, messageId: messageId, serverID: id)
    }

    // MARK: - serverID survives reconstruction

    /// F1 §4 invariant: reconstruct(old) must preserve old.serverID when non-nil.
    func testServerIDSurvivesReconstruction() {
        let original = msg(id: 132)
        XCTAssertEqual(original.serverID, 132)

        // Simulate a reconstruction path (e.g. updateLocalMessage / appendInterim):
        // a new ChatMessage built from the SAME logical message keeps serverID.
        let rebuilt = ChatMessage(
            role: original.role,
            content: original.content! + " more",
            timestamp: original.timestamp,
            messageId: original.messageId,
            name: original.name,
            toolCallId: original.toolCallId,
            toolUseId: original.toolUseId,
            toolCalls: original.toolCalls,
            contentParts: original.contentParts,
            reasoning: original.reasoning,
            attachments: original.attachments,
            turnTps: original.turnTps,
            serverID: original.serverID
        )
        XCTAssertEqual(rebuilt.serverID, 132, "F1: serverID must survive reconstruction")
    }

    // MARK: - serverID precedence over messageId

    func testServerIDWinsOverMessageIdInTranscriptIdentity() {
        let m = msg(id: 7, messageId: "stream-uuid")
        let row = ChatViewModel.transcriptMessages(from: [m]).first
        XCTAssertEqual(row?.id, "srv-7", "F1: serverID must take precedence")
    }

    // MARK: - no positional identity

    func testNoPositionalIdentityInTranscriptID() {
        let m = msg(id: 7)
        let row = ChatViewModel.transcriptMessages(from: [m], messageOffset: 42).first
        XCTAssertEqual(row?.id, "srv-7", "F1: id must not include index/offset")
        XCTAssertFalse(row?.id.contains("transcript:") ?? true, "F1: renderID must not be the identity")
    }

    // MARK: - duplicate serverID -> unique deterministic discriminator

    func testDuplicateServerIDProducesUniqueStableIdentities() {
        // id=132 persisted as several rows (one logical turn => N server rows).
        let a = msg(id: 132, messageId: "ma", content: "alpha")
        let b = msg(id: 132, messageId: "mb", content: "beta")
        let rows = ChatViewModel.transcriptMessages(from: [a, b])
        XCTAssertEqual(rows.count, 2, "F1: duplicate serverID must NOT collapse rows")
        XCTAssertNotEqual(rows[0].id, rows[1].id, "F1: duplicate serverID must yield unique ids")
        XCTAssertTrue(rows[0].id.hasPrefix("srv-132-h"), "F1: duplicate needs -h discriminator")
        XCTAssertTrue(rows[1].id.hasPrefix("srv-132-h"))
        // Deterministic: rebuilding with the same content yields the same ids.
        let rowsAgain = ChatViewModel.transcriptMessages(from: [a, b])
        XCTAssertEqual(rows.map(\.id), rowsAgain.map(\.id), "F1: discriminator must be deterministic")
    }

    // MARK: - byte-identical duplicates collapse but do not lose the whole group

    func testByteIdenticalDuplicateCollapsesOneRowOnly() {
        let a = msg(id: 132, messageId: "ma", content: "same")
        let b = msg(id: 132, messageId: "mb", content: "same")
        let rows = ChatViewModel.transcriptMessages(from: [a, b])
        XCTAssertEqual(rows.count, 1, "F1: byte-identical duplicate collapses to first")
        XCTAssertTrue(rows[0].id.hasPrefix("srv-132-h"),
                      "F1: surviving row keeps a stable -h discriminator even when its twin collapses")
    }

    // MARK: - offset / pagination identity stability

    func testIdentityStableAcrossOffsetShift() {
        let messages = [msg(id: 1, content: "x"), msg(id: 2, content: "y"), msg(id: 3, content: "z")]
        let before = ChatViewModel.transcriptMessages(from: messages, messageOffset: 0)
        let after = ChatViewModel.transcriptMessages(from: messages, messageOffset: 50)
        XCTAssertEqual(before.map(\.id), after.map(\.id),
                       "F1: identity must be stable across offset shift / pagination")
    }
}

