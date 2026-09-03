import CoreGraphics
import Foundation
import SwiftUI

/// Pure decision rules for the chat transcript's auto-scroll behavior.
///
/// The transcript keeps app-owned follow-bottom intent separate from
/// user-owned manual scrolling, and a short cooldown after any user
/// interaction prevents streaming layout growth from yanking the viewport
/// while a manual scroll is still settling.
/// Who owns the transcript viewport. The single source of truth for every
/// scroll decision: all scroll sites (system sizeChanges anchor, onChange
/// channels, follow-scroll scheduler, ↓ button) read ONLY this value. No site
/// decides on its own — the class of "finger fights the stream" bugs lived in
/// six sites each applying its own gate to scattered booleans.
enum ChatScrollOwner: Equatable {
    /// The reader owns the viewport. No auto-scroll may move it — not the
    /// streaming growth, not the new-row channels. Only an explicit ↓ tap or
    /// send can take ownership back.
    case user

    /// The app owns follow-latest: streaming growth and new rows glue to the
    /// bottom while the reader is at the tail.
    case app
}

/// Observable container for scroll ownership state.
///
/// Extracted from ChatView `@State` to isolate scroll-ownership changes from
/// the ChatView body evaluation. When `owner` changes, only views that
/// directly observe this object re-evaluate — not the entire ChatView body
/// (3400+ lines) and not the environment cascade to all descendants.
///
/// This eliminates the 3–14s AttributeGraph freeze that occurred on every
/// `app→user` scroll-owner transition (the freeze was caused by SwiftUI
/// re-evaluating the full ChatView body + environment propagation to
/// ChatTranscriptView and all its children).
@Observable
final class ScrollOwnershipState {
    var owner: ChatScrollOwner = .app
}

enum ChatScrollPolicy {
    /// Existing transcripts should enter at their latest content as part of the
    /// scroll view's first layout, before the destination becomes visible.
    static let initialTranscriptAnchor = UnitPoint.bottom

    /// The ONLY place that decides scroll ownership. Total transitions:
    ///   - finger touches              → .user (finger priority over printing)
    ///   - scrolled beyond threshold   → .user
    ///   - idle AND at the bottom      → .app
    ///   - otherwise                   → keep current (sticky)
    /// A transient touch pause (cooldown) suppresses auto-scroll during the
    /// gesture but does not change ownership — it only delays follow-latest.
    /// The ↓ button is one-shot: it fires a scroll but does NOT set .app;
    /// ownership is determined by updateScrollMetrics after the scroll settles.
    static func resolveOwner(
        current: ChatScrollOwner,
        isStreaming: Bool,
        isUserInteracting: Bool,
        isAtVeryBottom: Bool,
        isInCooldown: Bool = false
    ) -> ChatScrollOwner {
        // ANY touch yields ownership to the reader — not only while streaming.
        if isUserInteracting { return .user }
        // Settle window after the finger leaves: keep the reader's ownership
        // until the cooldown expires.
        if isInCooldown { return current }
        // The reader owns the viewport unless they are LITERALLY at the bottom.
        // "Near bottom" (80/160pt bands) is a chrome affordance, not ownership —
        // a reader 20pt up is reading, not following.
        if !isAtVeryBottom { return .user }
        if !isStreaming { return .app }
        return current
    }

    /// Distance (pt) from the bottom within which we treat the transcript as
    /// pinned to the latest content. Unified threshold for all purposes:
    /// ownership, UI chrome, and streaming detection.
    static let bottomThreshold: CGFloat = 80

    /// Extra distance past the bottom threshold required before the composer
    /// chrome collapses into its compact "reading older" presentation.
    static let readingOlderHysteresis: CGFloat = 64

    /// How long automatic follow-scroll stays paused after the user last
    /// interacted with the scroll view.
    static let userScrollCooldown: TimeInterval = 0.25

    static func isNearBottom(distanceFromBottom: CGFloat) -> Bool {
        distanceFromBottom <= bottomThreshold
    }

    /// True once the user has scrolled far enough above the bottom that the
    /// composer chrome should collapse. The hysteresis keeps the chrome stable
    /// when hovering right around the bottom threshold.
    static func shouldEnterReadingOlder(distanceFromBottom: CGFloat) -> Bool {
        distanceFromBottom > bottomThreshold + readingOlderHysteresis
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
