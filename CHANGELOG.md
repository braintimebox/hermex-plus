# Changelog

## 1.4.7 — 2026-08-13

### Fixed
- **"Send Now" re-sent the message automatically (duplicate delivery):** the Tasks and Session List send paths removed the local row but never deleted the server-side webhook record, so the scheduled-endpoint timer fired at the scheduled time and delivered the message a second time. All send paths (Tasks, Session List, Chat) plus the client dispatch loop now cancel the server timer via a shared `PendingScheduledMessage.deleteFromServer` after delivery.
- **Latency between creating a scheduled message and it appearing in Tasks → Scheduled:** the message was inserted into SwiftData without an explicit save, so the detached-context fetches (which only see committed rows) didn't show it until the autosave fired seconds later. Both creation sites now `save()` immediately.

## 1.4.6 — 2026-08-13

### Fixed
- **Freeze opening Tasks → Scheduled Messages (still present in 1.4.5):** `TasksView` still used `@Query` — a synchronous SwiftData fetch on the main thread at view construction. The count now loads asynchronously on a detached context. `ScheduledMessagesView` also fetched synchronously in `.task` (main actor); the fetch now runs on a detached context and models are re-resolved on the main context, so opening the page never blocks.
- **"Send Now" gave zero visible reaction:** the message was actually delivered, but the list held a stale snapshot — the row never disappeared and the sheet never closed. The list now reloads after a send/delete, and the sheet dismisses so the delivered message is visible in the chat.
- **Double-tap sent the same message repeatedly:** "Send Now" is now guarded while a send is in flight (12 taps previously produced multiple deliveries).

## 1.4.5 — 2026-08-12

### Fixed
- **Freeze (3-4s) when opening Tasks → Scheduled Messages:** `ScheduledMessagesView` used a synchronous `@Query` fetch on the main thread at appear. Now loads asynchronously after the view appears — opening the page never blocks. (Confirmed by freeze diagnostics: `tasks opened → scheduled list opened → freeze` ×3.)
- **"Send Now" from the calendar inside a chat actually sends:** it previously only pasted the text into the composer (`draftMessage = msg.draftText`). Now it delivers via the chat composer when the target is the current session, or via direct API for another/new chat, then removes the pending row locally + on the server.
- **@Model crossing into background tasks:** `syncScheduledMessageToServer` was passed the `PendingScheduledMessage` model object into `Task.detached` (not thread-safe — could crash/hang). Now captures scalar values only.
- **App version in diagnostics:** `appVersion` showed `1.3` because `MARKETING_VERSION` in pbxproj was never synced. `bump-version.py` now updates it; current build reports `1.4.5`.

### Changed
- `bump-version.py`: syncs VERSION + pbxproj MARKETING_VERSION (README header has no version — public file).

## 1.4.4 — 2026-08-12

### Fixed
- **"Tasks > Scheduled" page did not open:** `ScheduledMessagesView` wrapped itself in a `NavigationStack` while being pushed inside a `NavigationLink` — a nested navigation stack that breaks the push. Removed the inner stack (sheet presentation wraps it externally instead).
- **Scheduled Messages row visibility:** the row now shows only when there are pending messages (was always visible since 1.4.2 — hidden again per request).

### Changed
- **Explicit destination when scheduling:** `ScheduleMessageSheet` now requires a visible choice before scheduling when the message is not attached to the current chat — a segmented picker "New Chat / Existing Chat" with a session picker for the latter. No silent default to a new chat; the user always sees where the message will go.

## 1.4.3 — 2026-08-12

### Added
- **Freeze diagnostics context:** HermexLogger now attaches a ring buffer of the last 20 events to every `freeze` report — the server sees what the user was doing (screen, button, action) right before the main-thread hang, plus app version and foreground/background state
- Screen tracking: ChatView / SessionList / TasksView / ScheduledMessages / ScheduleSheet set the watchdog's active screen on appear
- Action markers: schedule button tapped, schedule confirmed (with target), scheduled message saved, send-now tapped, scene foreground/background

### Changed
- Files: `HermexLogger.swift`, `MainThreadWatchdog.swift`, `ChatView.swift`, `ChatComposerView.swift`, `TasksView.swift`, `SessionListView.swift`, `ScheduledMessagesView.swift`, `HermesMobileApp.swift`

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
