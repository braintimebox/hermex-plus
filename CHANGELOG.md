## 3.5.6 — UX: always-visible composer + faster response start

### UX — composer always visible (except clarification)

- **Problem:** composer collapsed to FAB after every send, requiring a tap to reopen. User wanted the composer to always be visible for quick follow-up messages.
- **Fix:** `composerVisible` defaults to `true`; removed `hideComposer()` calls after text send and voice note send. Composer now stays visible throughout the session. Only auto-hides during clarification prompts (A/B/C/D).

### Performance — faster response start

- **Problem:** retry delays in `startChatWithRetry` were 1.5s and 3s, causing noticeable delay on connection failures.
- **Fix:** reduced retry delays to 0.5s and 1s. First token appears sooner on retry.

## 3.5.5 — UX: instant skeleton, cache-first sessions, one-tap keyboard toggle
