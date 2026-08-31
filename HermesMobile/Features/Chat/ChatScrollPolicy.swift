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
    ///   - explicit ↓ tap / send          → .app (unconditional)
    ///   - finger touches during stream   → .user (finger priority over printing)
    ///   - scrolled beyond the threshold  → .user
    ///   - idle AND at the bottom         → .app
    ///   - otherwise                      → keep current (sticky)
    /// A transient touch pause (cooldown) remains a separate suppression —
    /// it never changes ownership, it only delays auto-scroll during a gesture.
    static func resolveOwner(
        current: ChatScrollOwner,
        isStreaming: Bool,
        isUserInteracting: Bool,
        isAtVeryBottom: Bool,
        isInCooldown: Bool = false,
        explicitFollowCommand: Bool = false
    ) -> ChatScrollOwner {
        if explicitFollowCommand { return .app }
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

    /// Rich Markdown can finish measuring after the scroll view's initial
    /// layout. Keep those size changes bottom-pinned only while the app still
    /// owns follow-latest AND the user is not mid-scroll; return nil as soon
    /// as the reader owns the viewport (or during the settle cooldown) so a
    /// streaming bubble's size growth can never yank the viewport back down.
    ///
    /// When idle (no stream), the system `.sizeChanges` anchor must stay nil
    /// entirely: idle follow-latest is already driven explicitly by
    /// `onChange(of: messages.count)` → `scrollToLatestContent`. A `.bottom`
    /// anchor here only competes with that path — and worse, outruns the async
    /// scroll-metrics that drop app ownership. The metrics arrive deferred
    /// (DispatchQueue.main.async), so ownership can linger `.app` for a frame
    /// or two after the reader scrolled back up; any incidental size change in
    /// that window (a LazyVStack row re-measuring, an image decoding, markdown
    /// finishing layout) makes the system silently re-glue the viewport to the
    /// bottom — the "scroll won't listen" jump. Restricting the anchor to
    /// streaming only removes that idle race.
    static func sizeChangeAnchor(
        owner: ChatScrollOwner,
        isAutoScrollPaused: Bool,
        isStreaming: Bool
    ) -> UnitPoint? {
        (isStreaming && owner == .app && !isAutoScrollPaused) ? .bottom : nil
    }

    /// Distance (pt) from the bottom within which we treat the transcript as
    /// pinned to the latest content while idle (drives chrome state).
    static let bottomDetectionThreshold: CGFloat = 80

    /// Looser bottom threshold while a response is streaming, so small layout
    /// jitter from incoming tokens does not flip follow state off.
    static let streamingBottomDetectionThreshold: CGFloat = 160

    /// OWNERSHIP threshold — much stricter than the UI bands. The reader owns
    /// the viewport unless they are literally AT the bottom (≤8pt) or pressed
    /// ↓ / sent a message. The old 80/160pt bands re-armed the app while the
    /// reader was 30-70pt up (still "near bottom"), so a quiet event (stream
    /// end reload, cache reconcile, keyboard) slammed the viewport down —
    /// "листаю вверх — меня отбрасывает, агент даже не печатает", and the
    /// same fight is what makes a fast flick feel jerky.
    static let ownershipBottomThreshold: CGFloat = 8

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
