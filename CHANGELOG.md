# Changelog

## 1.5.9 — 2026-08-15

### Fixed
- **Server avatar couldn't be changed:** the avatar circle in Settings → Server → Identity was a `Button` + `.photosPicker` modifier with a 36pt hit target (below iOS's 44pt minimum) — taps went unreliably and the picker often didn't present inside the scroll view. Replaced with a native `PhotosPicker` view and a 44pt hit target, so tapping the circle reliably opens the photo picker.

## 1.5.8 — 2026-08-15

### Fixed
- **Typing lag while composing a message:** every keystroke fired `reportHeight` (from both `textViewDidChange` and `updateUIView`), which ran a `sizeThatFits` and pushed the new height into the parent's `composerHeight` state. Because that state feeds the transcript's bottom padding and the composer material fade, a single typed character could re-layout the whole chat transcript. The height is now memoized — it only propagates when it actually changes (i.e. on line wrap), so typing on one line no longer re-lays-out the transcript.

## 1.5.7 — 2026-08-15

### Fixed
- **Long messages couldn't be pinned:** `MarkdownRenderer` and the user bubble both applied `.textSelection(.enabled)`, which intercepted the long-press gesture on long messages — the whole bubble was text, so the context menu (with Pin) never appeared. Short messages pinned fine because there was non-text area to grab. Removed the conflicting `.textSelection` from the transcript path (Copy/Select Text remain available via the context menu).
- **Pinned list no longer stacks in the header:** instead of stacking every pin as a banner, the chat now shows only the most recently pinned message with a `+N` badge. Long-press it (or tap "View All Pinned") to open a dedicated "Pinned Messages" page (Telegram-style) listing every pin; tapping a row scrolls to it, swipe-left unpins.
- **Pinned banner lost its accidental "x" button:** the one-tap unpin was too easy to trigger by mistake; unpinning now lives behind long-press / the pinned page, so a stray tap scrolls instead of unpinning.
- **App icon still wouldn't change on tap:** the picker used a `DisclosureGroup` inside the settings card, which didn't reliably respond to taps. Replaced with an explicit button that toggles the icon list inline.
- **Scheduled-message sheet cramped the title field:** the schedule sheet was a fixed `VStack` with a wheel `DatePicker`, so on the `.medium` detent the "New chat title" field was squeezed. The form now scrolls, so the title field always has room.
- **Couldn't rename a scheduled message's chat from the list:** the edit sheet had no title field. Added an editable "New chat title" (for new-chat messages only), persisted and synced to the server so a renamed destination survives a reschedule.

### Changed
- **Freeze diagnostics now capture the full backtrace:** the watchdog previously read only the top frame (PC/LR/FP), so a freeze showed `blocked at <redacted>` — a stripped symbol with no library name. It now walks the arm64 frame-pointer chain (via `vm_read_overwrite`, which can't fault the watchdog on a bad address) to emit the whole call path, and `dladdr` reports the binary name (`UIKitCore`, `SwiftUI`, `HermesMobile`…) even when the symbol is stripped.
- **Streaming markdown split is memoized:** `StreamingMarkdownBlockSplitter.split` ran an O(N) line scan several times per streamed token (body + onChange handlers), re-copying the active markdown each time. It now caches the last result, removing repeated main-thread work on long streams.

## 1.5.6 — 2026-08-15

### Fixed
- **Pinning is now multi-message and tappable:** a single `pinnedMessageID` was replaced with an ordered `pinnedMessageIDs` list, so you can pin several messages at once (Telegram-style, stacked in a banner). Tapping a pinned banner row now scrolls the transcript to that message (id → renderID resolution); the `xmark` unpins. Long multi-paragraph messages are collapsed to a single-line preview instead of a raw `prefix(80)`.
- **"Could not load sessions" on cold start:** the first session fetch could fail while the tunnel (Tailscale/cloudflared) was still coming up, surfacing a "Cannot reach server" error that only a manual Retry cleared. The initial load now retries transient connectivity failures up to 3 times with short backoff, so the tunnel can come up without user action (auth/other errors still fail fast).

### Changed
- **Versioned IPA artifact:** CI reads `VERSION` and names the build artifact `HermesPlus-<version>-unsigned` with the IPA inside as `HermesPlus-<version>.ipa`, instead of a bare `HermesPlus.ipa`.

## 1.5.5 — 2026-08-15

### Added
- **Name a new chat when scheduling a message:** when a scheduled message targets "New Chat" (from inside a chat or the home screen), a new optional "New chat title" field names the chat it will create. The title rides along in `PendingScheduledMessage.sessionTitle` and is applied in every dispatch path (server dispatcher, client 30s dispatcher, and both "Send Now" paths) via `/api/session/rename` right after session creation.

### Fixed
- **"Pin message" was missing from the message menu:** `ChatTranscriptMessageRow` hardcoded `onPin: nil` / `isPinned: false` into `ChatMessageActionMenu`, so the Pin/Unpin row never appeared even though the parent wired `onPin` and `isMessagePinned`. Now passes the real callbacks through.
- **App icon couldn't be changed:** `Info.plist` declared no `CFBundleIcons` / `CFBundleAlternateIcons`, so `UIApplication.shared.supportsAlternateIcons` was always false and the whole icon picker never rendered. Added the `CFBundleIcons` block mapping all seven alternate icon sets (Light/Dark/Disco/Monochrome Light/Monochrome Dark/Gradient Light/Gradient Dark) plus the primary `AppIcon`.
- **Freeze reports were blind:** the main-thread watchdog captured its own stack via a `Thread.callStackSymbols` loop that ran *on* the main thread — so every freeze report showed the watchdog's own frames and an empty `heavyOp`, never the code actually blocking. Replaced with a Mach `thread_get_state` capture that reads the main thread's PC/LR/FP directly from the watchdog's background queue and symbolicates them with `dladdr`. Also removed the 1/s main-queue capture loop, which itself added main-thread work.

## 1.5.4 — 2026-08-14

### Added
- **Server avatar photo from gallery:** tapping the "Server Avatar" circle in Settings → Identity opens the system photo picker; the chosen image replaces the initials badge. Stored locally on the device only (never synced to the server); falls back to initials + color when unset. Works in the server list, the per-server editor, and the add-server flow.

## 1.5.3 — 2026-08-14

### Added
- **Visible "Compressing context…" status:** the client now parses the SSE `compressing` / `context_status` / `warning` events the server already emits. During a long compaction the transcript shows a progress indicator with "Сжимаю контекст…" instead of a bare typing indicator (a 60s+ compaction previously looked like a freeze).
- **Edit scheduled messages:** new "Edit" button on scheduled-message rows opens a sheet to change the text and/or delivery time. Saves locally and POSTs to the scheduled-endpoint server, which upserts by scheduleKey and reschedules its dispatch timer.

### Fixed
- **"Scheduled message from yesterday still stuck":** the server dispatches a scheduled message and removes it from its own state but never notified the client, so the local row lingered forever. Opening the Scheduled list now reconciles local rows against the server and drops rows whose delivery time has passed and that the server no longer tracks (server unreachable = no deletion).
- **Human-readable context-exhausted error:** the terminal "context length exceeded / cannot compress further" error is now surfaced as "This session's context is exhausted… start a new chat" instead of the raw token-count message.

## 1.5.2 — 2026-08-13

### Fixed
- **Local image attachments no longer decode at full resolution on the main thread:** chat bubbles with locally attached photos rendered via `UIImage(data:)` on the full-size data — a 12MP shot cost ~48MB RAM and a 200-500ms main-thread decode per bubble, janking scroll through photo-heavy chats. Bubbles now render a ~512px downsampled thumbnail (same path the remote images already used); the full image still opens on tap.
- (Audit note: the file-size-before-read check in the paste/import path was already correct — validation runs via metadata before `Data(contentsOf:)`; no change needed.)

## 1.5.1 — 2026-08-13

### Changed
- **Cache writes fully off the main thread:** `CacheStore.cacheMessages` is no longer MainActor-isolated. All chat-send cache writes (6 call sites: send, rollback, stream-complete, load) now run on a background ModelContext created from the shared container and discarded after the save — the main thread only reads the cache. Even the one-fetch write can no longer stall the send. Maintenance throttle is now lock-protected (it runs on background workers).
- Audit of remaining main-thread SwiftData: only small bounded ops remain (single-fetch reads on chat open, tiny session rows) — no per-message loops anywhere.

## 1.5.0 — 2026-08-13

### Added
- **Freeze diagnostics v2 — real hangs, attributed:**
  - **Main-thread stack capture:** every foreground freeze now ships the symbolicated stack of the main thread (where it was stuck) plus physical memory footprint and the instrumented heavy operation in flight (`heavyOp`). "blocked 3s" becomes "blocked 3s at `CacheStore.cacheMessages:149`".
  - **Frame-time jank monitor (CADisplayLink):** sustained sub-30 FPS over a 2s window (or a single >50ms frame) logs a `jank` event with avg/max frame ms and fps — catches the "interface lags while the agent thinks" case that never hard-blocks the main thread. Rate-limited 1/30s.
  - **Stutter detection:** 1-3s main-thread stalls (below the 3s hard-freeze threshold) log rate-limited `stutter` events.
  - **Server-side watchdog** now alerts on `jank`/`stutter` too, still silent when healthy.

## 1.4.9 — 2026-08-13

### Fixed
- **UI freeze when submitting a task (3-4s foreground block, longer perceived):** every chat send wrote the offline cache synchronously on the main thread — one SwiftData predicate fetch PER message plus full-table maintenance scans. With hundreds of cached messages that was hundreds of queries on the MainActor, blocking the UI exactly when the user submitted a task. `cacheMessages` now fetches the session's cache once and upserts from a dictionary (N queries → 1), and maintenance (expiry/eviction full scans) is throttled to once a minute.
- **Watchdog false positives (multi-minute "freezes"):** the on-device watchdog counted app suspension as a main-thread block (its timer fires on resume and measures the whole pause — 491s/729s reports were simply the phone being locked). It now only reports when the app is active; the server-side freeze watchdog ignores `foreground=false` events too.

## 1.4.8 — 2026-08-13

### Fixed
- **"Send Now" looked like a no-op when the message targeted another chat:** the message was delivered to its target session, but the user stayed in the current chat and saw nothing; the delivery only became visible after back/forward navigation (reported as "рассинхрон состояний"). ChatView now navigates to the target session after Send Now when it differs from the chat on screen, so the delivered message is immediately visible.

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
