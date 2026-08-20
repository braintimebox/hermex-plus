import CoreGraphics
import Foundation
import SwiftUI

/// Pure decision rules for the chat transcript's auto-scroll behavior.
///
/// The transcript keeps app-owned follow-bottom intent separate from
/// user-owned manual scrolling, and a short cooldown after any user
/// interaction prevents streaming layout growth from yanking the viewport
/// while a manual scroll is still settling.
enum ChatScrollPolicy {
    /// Existing transcripts should enter at their latest content as part of the
    /// scroll view's first layout, before the destination becomes visible.
    static let initialTranscriptAnchor = UnitPoint.bottom

    /// Rich Markdown can finish measuring after the scroll view's initial
    /// layout. Keep those size changes bottom-pinned only while the app still
    /// owns follow-latest intent AND the user is not mid-scroll; return nil as
    /// soon as the reader scrolls away (or during the settle cooldown) so a
    /// streaming bubble's size growth can never yank the viewport back down.
    ///
    /// When idle (no stream), the system `.sizeChanges` anchor must stay nil
    /// entirely: idle follow-latest is already driven explicitly by
    /// `onChange(of: messages.count)` → `scrollToLatestContent`. A `.bottom`
    /// anchor here only competes with that path — and worse, outruns the async
    /// scroll-metrics that reset `shouldFollowLatestMessage`. The metrics
    /// arrive deferred (DispatchQueue.main.async), so the flag can linger
    /// `true` for a frame or two after the reader scrolled back up; any
    /// incidental size change in that window (a LazyVStack row re-measuring, an
    /// image decoding, markdown finishing layout) makes the system silently
    /// re-glue the viewport to the bottom — the "scroll won't listen" jump.
    /// Restricting the anchor to streaming only removes that idle race.
    static func sizeChangeAnchor(
        shouldFollowLatestMessage: Bool,
        isAutoScrollPaused: Bool,
        isStreaming: Bool
    ) -> UnitPoint? {
        (isStreaming && shouldFollowLatestMessage && !isAutoScrollPaused) ? .bottom : nil
    }

    /// Distance (pt) from the bottom within which we treat the transcript as
    /// pinned to the latest content while idle.
    static let bottomDetectionThreshold: CGFloat = 80

    /// Looser bottom threshold while a response is streaming, so small layout
    /// jitter from incoming tokens does not flip follow state off.
    static let streamingBottomDetectionThreshold: CGFloat = 160

    /// Extra distance past the bottom threshold required before the composer
    /// chrome collapses into its compact "reading older" presentation.
    static let readingOlderHysteresis: CGFloat = 64

    /// How long automatic follow-scroll stays paused after the user last
    /// interacted with the scroll view.
    static let userScrollCooldown: TimeInterval = 0.25

    static func bottomThreshold(isStreaming: Bool) -> CGFloat {
        isStreaming ? streamingBottomDetectionThreshold : bottomDetectionThreshold
    }

    static func isNearBottom(distanceFromBottom: CGFloat, isStreaming: Bool) -> Bool {
        distanceFromBottom <= bottomThreshold(isStreaming: isStreaming)
    }

    /// True once the user has scrolled far enough above the bottom that the
    /// composer chrome should collapse. The hysteresis keeps the chrome stable
    /// when hovering right around the bottom threshold.
    static func shouldEnterReadingOlder(distanceFromBottom: CGFloat, isStreaming: Bool) -> Bool {
        distanceFromBottom > bottomThreshold(isStreaming: isStreaming) + readingOlderHysteresis
    }

    static func cooldownDeadline(after date: Date = Date()) -> Date {
        date.addingTimeInterval(userScrollCooldown)
    }

    /// Automatic follow-scroll is paused while the user is actively touching the
    /// scroll view and for a brief cooldown window afterward. Explicit user
    /// actions (tapping scroll-to-bottom, sending a message) bypass this.
    static func isAutoScrollPaused(
        isUserInteracting: Bool,
        cooldownUntil: Date?,
        now: Date = Date()
    ) -> Bool {
        if isUserInteracting {
            return true
        }

        guard let cooldownUntil else {
            return false
        }

        return now < cooldownUntil
    }
}

/// Keeps transcript reconciliation and other state-heavy startup work out of
/// the system navigation transition. Cache preparation remains synchronous so
/// an available transcript can participate in the destination's first layout.
enum ChatInitialAppearancePolicy {
    static func shouldBeginAsyncWork(hasCompletedAppearance: Bool) -> Bool {
        hasCompletedAppearance
    }
}
