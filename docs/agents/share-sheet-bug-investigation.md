# Share Sheet Bug Investigation

**Date**: 2026-08-10
**Bug**: Shared content from browser opens empty chat instead of saving draft.

## Flow (Current)
```
[Share Extension]                        [Main App]
saveToPasteboard(draft, attachments)        |
  → pb.setItems(items)  // IPC → pasted     |
openHermes()                                |
  → extensionContext.open(url) // IPC → app |
                                         .task → importPendingSharedDraftIfAvailable()
                                         handleOpenURL → importPendingSharedDraftIfAvailable()
                                         scenePhase(.active) → importPendingSharedDraftIfAvailable()
```

## Root Cause
**Pasteboard IPC race**: `pb.setItems()` and `extensionContext.open(url)` are both asynchronous IPC operations with no ordering guarantee. The main app's `handleOpenURL` can fire before the `pasted` daemon has processed the write, so `loadFromPasteboard()` returns nil → `pendingSharedImport` stays nil → no destination picker → empty chat.

## Three Call-Site Analysis
`ContentView.swift` calls `importPendingSharedDraftIfAvailable()` from three places:
1. **`.task`** (line 19) — cold launch only; always misses because no prior write exists (correct behavior)
2. **`scenePhase(.active)`** (line 37) — fires right after `handleOpenURL`; redundant
3. **`handleOpenURL(share)`** (line 110) — the primary trigger; may be too early

All run on `@MainActor` so they're serialized, not concurrent. But if the pasteboard daemon hasn't flushed by the time BOTH calls (2) and (3) execute, both miss.

## Research Findings

### Q1: `localOnly:false` + `expirationDate`?
**Not helpful.** `localOnly` controls Handoff sharing, not flush timing. `expirationDate` controls auto-clear, not write visibility. Named `UIPasteboard(name:create:)` with `create:true` is already persistent. The issue is timing of the `pasted` daemon, not pasteboard lifecycle.

### Q2: URL scheme base64 fallback?
**Viable and recommended.** Encode draft text as URL-safe base64 in query parameter: `hermes-agent://share?d=<base64url>`. The URL arrives deterministically in `handleOpenURL` — zero race. Limit to ~1500 chars of base64 (fits ~1100 chars of UTF-8 text). Covers the most common case (sharing a URL from browser). Attachments still need pasteboard. Implementation is < 30 lines.

### Q3: Race between scenePhase and handleOpenURL?
**Not a true concurrency race** (both `@MainActor`). But they fire in rapid sequence and both can miss if pasteboard isn't ready. `handleOpenURL` fires first on warm launch; `scenePhase(.active)` follows almost immediately. The `.task` call on cold launch is a no-op (correct).

## Proposed Fix

Three incremental layers, ordered by impact/effort ratio:

### Layer 1: Async retry loop in `loadFromPasteboard()` (PRIMARY FIX)
- Add 3 retries with staggered delays (50ms → 150ms → 400ms)
- Total wait ≤ 600ms — imperceptible to user
- Handles the pasteboard daemon flush delay
- Changes: ~15 lines in `SharedDraftStore.swift`; make `importPendingSharedDraftIfAvailable()` async

### Layer 2: Base64 URL fallback (BELT-AND-SUSPENDERS)
- Extension encodes draft text in URL query param `?d=<base64url>`
- Main app decodes from `handleOpenURL` URL instantly — no race possible
- Covers text-only shares (browser URL sharing = most common case)
- Changes: ~30 lines in `SharedDraftStore.swift`; 2-line tweak in `ShareViewController.swift`

### Layer 3: Remove redundant import calls (CLEANUP)
- Remove `importPendingSharedDraftIfAvailable()` from `scenePhase.onChange` (line 37)
- Remove from `.task` (line 19) — stale pasteboard edge case not worth complexity
- `handleOpenURL` becomes the single entry point; base64 URL fires first (sync), pasteboard retries (async)

### Files Changed
1. `HermesMobile/Features/Share/SharedDraftStore.swift` — async retry load, URL base64 encode/decode
2. `HermesShareExtension/ShareViewController.swift` — pass draft in URL
3. `HermesMobile/ContentView.swift` — single import entry point, async

### Risk Assessment
- **Low risk**: Pasteboard retry only adds delays when pasteboard is empty; normal path unchanged
- **Backward compatible**: Old `openURL` property preserved; `draftFromShareURL` returns nil for bare `hermes-agent://share`
- **URL length**: Base64 draft limited to 1500 chars (~1100 UTF-8 chars); falls through to pasteboard for longer text
