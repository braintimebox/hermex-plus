# Changelog

## 1.4.2 — 2026-08-12

### Fixed
- **Scheduled message disappearing + freeze on Schedule:** `scheduleKey` was built from `sessionId|timestamp` — the DatePicker wheel zeroes seconds, so two messages scheduled in the same minute for the same chat collided on SwiftData's `@Attribute(.unique)` and the second insert was silently dropped. Key now includes a UUID.
- **"Tasks > Scheduled" page missing:** the "Scheduled Messages" row in Tasks was hidden when the list was empty — there was no way to reach the page. Row is now always visible.
- **"Send Now" button dead from Tasks/Session list:** the callback was an empty closure. It now actually sends the message (creates a session when none is attached, then sends via the API and removes the pending row).
- **No chat picker when scheduling:** `ScheduleMessageSheet` only had an "Attach to current chat" toggle. Now, when not attached, you can pick an existing chat from the session list or create a new one.

### Changed
- Files: `PendingScheduledMessage.swift`, `TasksView.swift`, `ScheduledMessagesView.swift`, `ChatView.swift`, `SessionListView.swift`

## 1.4.1 — 2026-08-12

### Added
- **Diagnostics channel (24/7 freeze detection):** `HermexLogger` ships app events (freeze/error/recovered) to the server's `/webhook/hermex-logs` ingest endpoint; `MainThreadWatchdog` detects main-thread hangs in real time and reports them from a background queue — the agent is notified within a minute of any freeze
- Files: `HermesMobile/HermexLogger.swift`, `HermesMobile/MainThreadWatchdog.swift`, watchdog starts in `HermesMobileApp.init()`

## 1.3.1 — 2026-08-09

### Fixed
- **Streaming performance:** incremental transcript update replaces O(n) full recompute with O(1) slot swap per token flush — eliminates UI hangs on long chat threads
- **SSE decoder re-use:** static `JSONDecoder` replaces per-event allocation — ~50 fewer allocs/sec during fast streaming

### Changed
- CI now triggers on any push (not just master/main)
- Tagged releases for stable builds (`git tag vX.Y.Z`)

## 1.0.0 → 1.3.0 — 2026-08-05

### Added
- App header now shows "Hermes Plus" (Hermes logo + "Plus" text)

### Changed
- App display name: "Hermex" → "Hermes Plus"
- Swipe-to-pin/archive/delete removed (use long-press context menu instead)
- README: restored clean Hermes Plus header (dropped marketing rewrite)

### Fixed
- Build pipeline: `macos-26` runner required (Xcode 26 beta for `Glass` API)
- Unsigned IPA: `build` instead of `archive` to avoid extension signing failures

### Forked from
- [Hermex](https://github.com/uzairansaruzi/hermex) — native iOS client for Hermes Agent
