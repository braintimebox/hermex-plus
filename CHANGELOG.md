## 3.5.9 — Scroll conflict elimination (↓ button one-shot + streaming follow)

### Scroll — ↓ button is now one-shot (no permanent ownership lock)

- **Problem:** tapping ↓ set `scrollOwnership = .app` permanently. When the user immediately scrolled back up, the ownership lingered `.app` for 1–2 frames (deferred metrics), during which a streaming size change re-glued the viewport to the bottom — the "↓ fights the finger" jump.
- **Fix:** ↓ button no longer sets ownership. It fires a one-shot scroll to the bottom and clears the cooldown. Ownership is determined naturally by `updateScrollMetrics` after the scroll settles: at the bottom → `.app`, scrolled up → `.user`. The send action (`prepareTranscriptForExplicitSend`) still sets `.app` — that's correct for sending.

### Scroll — streaming follow via streamingScrollTrigger (old text problem)

- **Problem:** `streamingScrollTrigger` was generated on every token flush but never consumed (removed in 3.5.8). During streaming, `messages.count` doesn't change (same message, more tokens), so `onChange(of: messages.count)` doesn't fire. Streaming text grew silently below the viewport while the user stared at stale content.
- **Fix:** re-added `onChange(of: streamingScrollTrigger)` with the same `scrollOwner == .app` guard. Streaming content growth now triggers follow-latest. When the user scrolls up (`scrollOwner == .user`), the handler exits early — no fight.

## 3.5.8 — Scroll architecture unification + instant first token

### Performance — first token appears in 16ms (was 200ms)

- **Problem:** `streamingWordRevealCadenceNanoseconds` was 200ms, batching tokens before display. First character delayed by up to 200ms after arrival.
- **Fix:** reduced to 16ms (one frame at 60fps). Tokens appear almost instantly.

### Scroll — unified bottom threshold (3 → 1)

- **Problem:** three separate thresholds (8pt ownership, 80pt UI, 160pt streaming) created confusion and conflicting behavior. User 30pt up was "near bottom" for UI but "reading" for ownership.
- **Fix:** single 80px threshold for all purposes: ownership, UI chrome, and streaming detection. User owns viewport unless within 80px of bottom.

### Scroll — removed sizeChangeAnchor (system glue)

- **Problem:** `.defaultScrollAnchor(.bottom, for: .sizeChanges)` glued viewport to bottom during content growth, fighting user scroll. Any re-measure (image decode, markdown layout) triggered the jump.
- **Fix:** removed `sizeChangeAnchor` entirely. Follow-latest driven explicitly by `onChange(of: messages.count)`. No system glue, no "scroll won't listen" jump.

### Scroll — removed streamingScrollTrigger (redundant follow)

- **Problem:** `streamingScrollTrigger` incremented on every token flush, triggering `scrollToLatestContent` even when `onChange(of: messages.count)` already handled it. Double-follow caused fight during user scroll.
- **Fix:** removed `streamingScrollTrigger` onChange handler. `onChange(of: messages.count)` is the single follow mechanism.

## 3.5.7 — Silent streaming ON by default
