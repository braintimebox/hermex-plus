## 3.5.5 — UX: instant skeleton, cache-first sessions, one-tap keyboard toggle

### Performance — instant skeleton on chat open

- **Problem:** opening a chat blocked the main thread with a synchronous SwiftData fetch (`CacheStore.cachedMessages`) before showing any content. Users saw a blank screen or loading spinner for 0.5-1s.
- **Fix:** `prepareInitialMessageLoad` now wraps the cache read in `Task { @MainActor }`, showing the skeleton immediately while the cache loads in the background. Skeleton → cached content transition is seamless.

### Performance — cache-first session list

- **Problem:** session list loading blocked the main thread with `CacheStore.cachedSessions` (synchronous SwiftData fetch) before showing any sessions.
- **Fix:** `SessionListViewModel.load` wraps the cache read in `await Task { @MainActor }.value`, showing the skeleton instantly while the cache loads in the background.

### UX — one-tap keyboard toggle

- **Problem:** tapping the transcript to dismiss the keyboard required two taps: first to dismiss keyboard, second to collapse composer. This was confusing and slow.
- **Fix:** `handleTranscriptTap()` now toggles the keyboard in one tap: tap with keyboard up → dismiss; tap with keyboard down → show composer + open keyboard. No two-step dance.

## 3.5.4 — UX: hide FAB and scroll-to-bottom during clarification prompts
