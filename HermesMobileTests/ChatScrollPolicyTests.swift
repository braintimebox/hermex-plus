import XCTest
@testable import HermesMobile

/// Tests for the scroll ownership policy — the single place that decides whether
/// the app or the reader owns the viewport during streaming.
///
/// History worth knowing before editing this file: v3.6.0 ("scroll cleanup")
/// deleted a family of near-duplicate threshold helpers (`sizeChangeAnchor`,
/// `bottomDetectionThreshold`, `streamingBottomDetectionThreshold`, and the
/// `isStreaming:` variant of `isNearBottom`) and replaced them with two things —
/// one unified `bottomThreshold`, and `resolveOwner`, which decides ownership
/// from five inputs. These tests still asserted the deleted API, so the whole
/// test target failed to compile. The production change was the improvement;
/// the tests were simply never updated, because nothing ran them.
///
/// So: the assertions below track the *current* contract. When the policy
/// changes again, update these tests in the same commit — a red build here means
/// the tests have fallen behind the code, not that the code is wrong.
final class ChatScrollPolicyTests: XCTestCase {

    // MARK: - Initial layout anchor

    func testExistingTranscriptUsesBottomAsItsInitialLayoutAnchor() {
        XCTAssertEqual(ChatScrollPolicy.initialTranscriptAnchor, .bottom)
    }

    // MARK: - resolveOwner — the ownership decision
    //
    // Ownership answers "who is allowed to move the viewport right now?".
    // .app means follow the newest content; .user means leave the reader alone.
    // Every transition in the app routes through this one function.

    func testAnyTouchGivesOwnershipToReaderRegardlessOfStreaming() {
        // Finger priority beats printing: while the user is touching the scroll
        // view, the app must never yank the viewport, streaming or not.
        for isStreaming in [true, false] {
            XCTAssertEqual(
                ChatScrollPolicy.resolveOwner(
                    current: .app,
                    isStreaming: isStreaming,
                    isUserInteracting: true,
                    isAtVeryBottom: true
                ),
                .user
            )
        }
    }

    func testCooldownKeepsCurrentOwnerWhenIdle() {
        // The settle window after the finger leaves: keep whoever had it, so a
        // fling does not hand control back mid-momentum.
        XCTAssertEqual(
            ChatScrollPolicy.resolveOwner(
                current: .user,
                isStreaming: false,
                isUserInteracting: false,
                isAtVeryBottom: true,
                isInCooldown: true
            ),
            .user
        )
    }

    func testReaderKeepsOwnershipWhenNotLiterallyAtBottom() {
        // "Near bottom" is a chrome affordance; it is NOT ownership. A reader
        // 20pt up from the bottom is reading, not following — so the app must
        // not resume auto-scroll. This is the distinction that keeps the
        // transcript from snapping back while the user reads.
        XCTAssertEqual(
            ChatScrollPolicy.resolveOwner(
                current: .user,
                isStreaming: true,
                isUserInteracting: false,
                isAtVeryBottom: false
            ),
            .user
        )
    }

    func testAppResumesOwnershipWhenIdleAtBottomAndNotStreaming() {
        XCTAssertEqual(
            ChatScrollPolicy.resolveOwner(
                current: .user,
                isStreaming: false,
                isUserInteracting: false,
                isAtVeryBottom: true
            ),
            .app
        )
    }

    func testOwnershipIsStickyWhileStreamingAtBottom() {
        // At the very bottom and streaming: keep whatever the current owner is.
        // If the user owns it, streaming must not silently steal it back.
        XCTAssertEqual(
            ChatScrollPolicy.resolveOwner(
                current: .user,
                isStreaming: true,
                isUserInteracting: false,
                isAtVeryBottom: true
            ),
            .user
        )
        XCTAssertEqual(
            ChatScrollPolicy.resolveOwner(
                current: .app,
                isStreaming: true,
                isUserInteracting: false,
                isAtVeryBottom: true
            ),
            .app
        )
    }

    // MARK: - Unified bottom threshold

    func testBottomThresholdIsASingleUnifiedValue() {
        // v3.6.0 collapsed the idle/streaming threshold pair into one constant:
        // ownership, chrome and streaming detection all share it now.
        XCTAssertEqual(ChatScrollPolicy.bottomThreshold, 80)
        XCTAssertGreaterThan(ChatScrollPolicy.bottomThreshold, 0)
    }

    func testInitialAsyncWorkWaitsForNavigationAppearanceCompletion() {
        XCTAssertFalse(ChatInitialAppearancePolicy.shouldBeginAsyncWork(hasCompletedAppearance: false))
        XCTAssertTrue(ChatInitialAppearancePolicy.shouldBeginAsyncWork(hasCompletedAppearance: true))
    }

    // MARK: - isNearBottom

    func testIsNearBottomUsesTheUnifiedThreshold() {
        XCTAssertTrue(
            ChatScrollPolicy.isNearBottom(
                distanceFromBottom: ChatScrollPolicy.bottomThreshold
            )
        )
        XCTAssertFalse(
            ChatScrollPolicy.isNearBottom(
                distanceFromBottom: ChatScrollPolicy.bottomThreshold + 1
            )
        )
    }

    // MARK: - Reading-older hysteresis

    func testShouldEnterReadingOlderRequiresHysteresisPastThreshold() {
        let threshold = ChatScrollPolicy.bottomThreshold
        let hysteresis = ChatScrollPolicy.readingOlderHysteresis

        XCTAssertFalse(
            ChatScrollPolicy.shouldEnterReadingOlder(
                distanceFromBottom: threshold + hysteresis
            )
        )
        XCTAssertTrue(
            ChatScrollPolicy.shouldEnterReadingOlder(
                distanceFromBottom: threshold + hysteresis + 1
            )
        )
    }

    // MARK: - Auto-scroll pause

    func testAutoScrollPausedWhileUserInteracting() {
        XCTAssertTrue(
            ChatScrollPolicy.isAutoScrollPaused(
                isUserInteracting: true,
                cooldownUntil: nil
            )
        )
    }

    func testAutoScrollPausedDuringCooldownWindow() {
        let now = Date()
        let future = now.addingTimeInterval(0.1)

        XCTAssertTrue(
            ChatScrollPolicy.isAutoScrollPaused(
                isUserInteracting: false,
                cooldownUntil: future,
                now: now
            )
        )
    }

    func testAutoScrollResumesAfterCooldownExpires() {
        let now = Date()
        let past = now.addingTimeInterval(-0.1)

        XCTAssertFalse(
            ChatScrollPolicy.isAutoScrollPaused(
                isUserInteracting: false,
                cooldownUntil: past,
                now: now
            )
        )
    }

    func testAutoScrollNotPausedWithoutInteractionOrCooldown() {
        XCTAssertFalse(
            ChatScrollPolicy.isAutoScrollPaused(
                isUserInteracting: false,
                cooldownUntil: nil
            )
        )
    }

    // MARK: - Cooldown deadline

    func testCooldownDeadlineIsUserScrollCooldownInFuture() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000)
        let deadline = ChatScrollPolicy.cooldownDeadline(after: base)

        XCTAssertEqual(
            deadline.timeIntervalSince(base),
            ChatScrollPolicy.userScrollCooldown,
            accuracy: 0.0001
        )
    }
}
