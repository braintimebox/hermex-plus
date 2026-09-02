## 3.5.7 — Silent streaming ON by default

### Fix — silent streaming default was false

- **Problem:** `suppressesReasoningAndToolUpdates` defaulted to `false` in SettingsView, ChatView, and ChatStreamCoordinator. Users had to manually enable "Silent Streaming" in Settings → Chat. Most users never found or enabled it, so the 42-81 → 2-5 updates/token improvement was never applied.
- **Fix:** changed default to `true` in all three locations. Silent streaming is now ON by default for all users. The toggle remains in Settings for users who want to disable it.
- **Effect:** per-token UI updates drop from ~80 to ~2-5 out of the box. Tool cards and reasoning appear once the stream completes.

## 3.5.6 — UX: always-visible composer + faster response start
