import SwiftUI

/// Composer growth and reserved-space policy. Fork-owned: this file does not
/// exist upstream, so no sync can conflict with it — the rule in
/// `docs/agents/sync-compatibility.md` ("new behaviour belongs in a new file").
///
/// Measured cause. On a 16 Pro the composer sat at 123pt against Telegram's 76pt
/// (transcript got 56% of the screen instead of 74%), and the frame-by-frame
/// analysis of the user's screenshot found two defects that are geometry, not
/// taste:
///
///   * the attachment strip rendered on every expanded state, attachments or
///     not, reserving a band of ~25pt above an empty field;
///   * the field itself does grow (minHeight 42 → maxHeight 96 in
///     ChatComposerTextInputView), but the composer's *layout* does not: focus
///     morphs pill→card and the morph, not the text, decides the height. The
///     two stable telemetry heights — 136 and 193 — are the chrome, not the
///     draft.
///
/// This type makes the empty-state reservation provably zero and keeps the
/// growth ceiling in one place, so the 260pt runaway clamp in `ChatView` and
/// the 96pt field ceiling can no longer disagree silently.
enum ChatComposerGrowth {

    /// Ceiling for the text field alone — mirrors `ChatComposerTextInputView`'s
    /// `.frame(maxHeight:)`. Four lines at body size; beyond that the field
    /// scrolls internally. Single source so the two cannot drift apart.
    static let fieldMaxHeight: CGFloat = 96

    /// Floor keeps the field tappable at one line (42pt) — mirrors the minHeight.
    static let fieldMinHeight: CGFloat = 42

    /// The strip above the field exists to hold attachment thumbnails. With
    /// nothing attached it draws no content, and an empty `VStack` band is pure
    /// lost transcript height: the whole point of the composer's geometry is
    /// that it does not occupy space it has nothing to show.
    ///
    /// `hasAttachments` is the only condition; the expanded morph must not
    /// reserve space for a strip that will be empty.
    static func showsAttachmentStrip(hasAttachments: Bool) -> Bool {
        hasAttachments
    }

    /// Показывать ли ряд селекторов (модель, воркспейс, профиль, git, контекст)
    /// под полем. Фокус его не открывает: ряд появляется только по явному запросу
    /// пользователя из меню «＋». Телеметрия 3.9.13 с устройства: с клавиатурой
    /// композер был 110pt против 54pt в свёрнутом виде, и вся разница приходилась
    /// на этот ряд (44pt) плюс зазоры. Свёрнутый вид — эталон: одна строка.
    static func showsControlRow(isExpanded: Bool, requested: Bool) -> Bool {
        isExpanded && requested
    }

    /// The composer's own height budget for the collapsed state: one row of
    /// controls, no strip, no toolbar. `ChatView` uses this only to sanity-check
    /// telemetry against a real number, so a chrome regression shows up in data
    /// rather than in a screenshot someone has to eyeball.
    static let collapsedTargetHeight: CGFloat = 76

    /// Rejects a measured height that cannot come from content. `onHeightChange`
    /// in `ChatView` clamps at 260pt because a focus feedback loop once ballooned
    /// the composer past 1000pt of empty space; that clamp is the safety net, and
    /// this is the same number phrased as a predicate so the gate and the clamp
    /// share one truth.
    static let runawayHeightLimit: CGFloat = 260

    static func isRunawayHeight(_ height: CGFloat) -> Bool {
        height > runawayHeightLimit
    }
}
