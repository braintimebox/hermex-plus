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

    // MARK: Follow latch

    private typealias Latch = ChatScrollPolicy.FollowLatch

    private func follow(_ current: Bool, _ event: ChatScrollPolicy.FollowEvent) -> Bool {
        ChatScrollPolicy.resolveFollow(current: Latch(isFollowing: current), event: event).isFollowing
    }

    private func reduce(_ latch: Latch, _ events: ChatScrollPolicy.FollowEvent...) -> Latch {
        events.reduce(latch) { ChatScrollPolicy.resolveFollow(current: $0, event: $1) }
    }

    func testTouchDownTurnsFollowOff() {
        XCTAssertFalse(follow(true, .userScrollBegin))
        XCTAssertFalse(follow(false, .userScrollBegin))
    }

    func testDragEndAboveBottomKeepsFollowOff() {
        XCTAssertFalse(follow(false, .userScrollEnd(isAtBottom: false)))
    }

    func testExplicitResetSurvivesLateDragSettlement() {
        // Drag lifted above the bottom, then send or scroll-to-bottom landed inside the
        // 160 ms settle window. The late settle report must not undo the reset.
        let latch = reduce(Latch(), .userScrollBegin, .reset, .userScrollEnd(isAtBottom: false))
        XCTAssertTrue(latch.isFollowing)
        XCTAssertFalse(latch.ignoresCoastingGesture)
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

    func testExplicitResetSurvivesCoastingMomentum() {
        // Send or scroll-to-bottom while the transcript is still decelerating: the
        // remaining momentum ticks belong to the gesture that predates the reset.
        let coasting = reduce(
            Latch(),
            .userScrollBegin,
            .reset,
            .contentScrolled(isAtBottom: false, isUserScrolling: true)
        )
        XCTAssertTrue(coasting.isFollowing)

        // Once that momentum settles, the next real drag turns follow off as usual.
        let settled = reduce(coasting, .userScrollEnd(isAtBottom: false))
        XCTAssertTrue(settled.isFollowing)
        XCTAssertFalse(settled.ignoresCoastingGesture)
        XCTAssertFalse(reduce(settled, .contentScrolled(isAtBottom: false, isUserScrolling: true)).isFollowing)
    }

    func testNewDragAfterResetTurnsFollowOff() {
        let latch = reduce(Latch(), .reset, .userScrollBegin)
        XCTAssertFalse(latch.isFollowing)
        XCTAssertFalse(latch.ignoresCoastingGesture)
    }

    func testDragEndAtBottomReArmsFollow() {
        XCTAssertTrue(follow(false, .userScrollEnd(isAtBottom: true)))
    }

    func testMomentumEndDecidesFromWhereItSettled() {
        // A fling that stops mid-transcript stays off; one that lands at the end re-arms.
        XCTAssertFalse(follow(false, .userScrollEnd(isAtBottom: false)))
        XCTAssertTrue(follow(false, .userScrollEnd(isAtBottom: true)))
    }

    func testLayoutGrowthWhileOffNeverReArms() {
        // Streaming tokens push the bottom away; that alone must not re-pin the reader.
        XCTAssertFalse(follow(false, .contentScrolled(isAtBottom: false, isUserScrolling: false)))
    }

    func testLayoutGrowthWhileFollowingStaysOn() {
        // Keyboard presentation and token growth move the offset without a gesture.
        XCTAssertTrue(follow(true, .contentScrolled(isAtBottom: false, isUserScrolling: false)))
    }

    func testNonGestureScrollThatLandsAtBottomFromNearbyReArms() {
        // A collapse near the end clamps the offset to the bottom.
        XCTAssertTrue(follow(false, .contentScrolled(isAtBottom: true, isUserScrolling: false, wasNearBottom: true)))
    }

    func testTransientBottomFromFarAboveDoesNotReArm() {
        // A relayout that momentarily reads "at bottom" while the reader was parked
        // thousands of points up must not switch follow on.
        XCTAssertFalse(follow(false, .contentScrolled(isAtBottom: true, isUserScrolling: false, wasNearBottom: false)))
    }

    func testScrollAwayFromBottomWithoutGestureTurnsFollowOff() {
        // Status-bar tap, VoiceOver, or a hardware-keyboard scroll: no pan gesture,
        // but the reader is being carried away from the bottom.
        XCTAssertFalse(follow(true, .contentScrolled(isAtBottom: false, isUserScrolling: false, movedAwayFromBottom: true)))
    }

    func testExplicitResetSurvivesCoastingMomentumAwayFromBottom() {
        // Momentum ticks after a reset carry the away flag too; they still belong
        // to the gesture that predates the reset.
        let latch = reduce(
            Latch(),
            .userScrollBegin,
            .reset,
            .contentScrolled(isAtBottom: false, isUserScrolling: true, movedAwayFromBottom: true)
        )
        XCTAssertTrue(latch.isFollowing)
    }

    // MARK: Scroll-away detection

    private typealias Geometry = ChatScrollPolicy.ScrollGeometry

    func testDistanceGrowingPastStreamingThresholdIsAScrollAway() {
        let atBottom = Geometry(offsetY: 4300, contentHeight: 5000, visibleHeight: 700)
        // Status-bar scroll: the lazy stack may re-measure on the way, so the
        // content height is allowed to move as long as the distance grows.
        let carriedAway = Geometry(offsetY: 3200, contentHeight: 5200, visibleHeight: 700)
        XCTAssertTrue(ChatScrollPolicy.isScrollingAwayFromBottom(previous: atBottom, current: carriedAway))
        XCTAssertFalse(ChatScrollPolicy.isScrollingAwayFromBottom(previous: nil, current: carriedAway))
    }

    func testJitterViewportAndFollowScrollsAreNotScrollAways() {
        let atBottom = Geometry(offsetY: 4300, contentHeight: 5000, visibleHeight: 700)
        // Streaming jitter under the loose threshold.
        XCTAssertFalse(ChatScrollPolicy.isScrollingAwayFromBottom(
            previous: atBottom,
            current: Geometry(offsetY: 4300, contentHeight: 5150, visibleHeight: 700)
        ))
        // Keyboard inset change: viewport changes.
        XCTAssertFalse(ChatScrollPolicy.isScrollingAwayFromBottom(
            previous: atBottom,
            current: Geometry(offsetY: 4300, contentHeight: 5000, visibleHeight: 400)
        ))
        // Follow scroll heading back to the bottom from far away.
        let farAway = Geometry(offsetY: 1000, contentHeight: 5000, visibleHeight: 700)
        XCTAssertFalse(ChatScrollPolicy.isScrollingAwayFromBottom(
            previous: farAway,
            current: Geometry(offsetY: 2000, contentHeight: 5000, visibleHeight: 700)
        ))
        // Size change snapped back to the bottom by the anchor.
        XCTAssertFalse(ChatScrollPolicy.isScrollingAwayFromBottom(
            previous: atBottom,
            current: Geometry(offsetY: 4700, contentHeight: 5400, visibleHeight: 700)
        ))
    }

    func testLiveGestureWinsEvenAtBottom() {
        XCTAssertFalse(follow(true, .contentScrolled(isAtBottom: true, isUserScrolling: true)))
    }

    func testExplicitActionsBypassTheLatch() {
        XCTAssertTrue(follow(false, .reset))
        XCTAssertTrue(follow(true, .reset))
    }

    func testReArmRequiresStrictBottom() {
        XCTAssertTrue(ChatScrollPolicy.isAtBottom(distanceFromBottom: ChatScrollPolicy.followReArmThreshold))
        XCTAssertFalse(ChatScrollPolicy.isAtBottom(distanceFromBottom: ChatScrollPolicy.followReArmThreshold + 1))
        XCTAssertLessThan(ChatScrollPolicy.followReArmThreshold, ChatScrollPolicy.bottomDetectionThreshold)
    }

    func testDragSettleWaitsForLateMomentum() {
        XCTAssertEqual(ChatScrollPolicy.dragSettleDelay, 0.16, accuracy: 0.0001)
        XCTAssertLessThan(ChatScrollPolicy.momentumSettleDelay, ChatScrollPolicy.dragSettleDelay)
    }

    func testDisclosureToggleSuspendsBottomAnchorWhileFollowing() {
        XCTAssertNil(
            ChatScrollPolicy.sizeChangeAnchor(shouldFollowLatestMessage: true, isDisclosureSettling: true)
        )
        XCTAssertEqual(
            ChatScrollPolicy.sizeChangeAnchor(shouldFollowLatestMessage: true, isDisclosureSettling: false),
            .bottom
        )
        XCTAssertNil(
            ChatScrollPolicy.sizeChangeAnchor(shouldFollowLatestMessage: false, isDisclosureSettling: false)
        )
    }
}
