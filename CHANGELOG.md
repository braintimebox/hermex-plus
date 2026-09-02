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
