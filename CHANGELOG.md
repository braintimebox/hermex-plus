# Changelog

## 2.0.7 — 2026-08-19

### Fixed
- **Message load now retries transient connection failures.** Opening a chat on a
  cold start (network/tunnel still coming up) previously made the single
  `client.session` call surface a bare "Could not connect" with no self-recovery.
  The message load now retries connectivity/transient failures with exponential
  backoff (1s → 2s → 4s → 8s, ~15s total), mirroring the session-list retry.
  Non-transient errors (auth, decoding, real 5xx) still fail fast.

## 2.0.6 — 2026-08-19

### Fixed
- **No more yank-to-bottom after scrolling up.** `shouldFollowLatestMessage` was
  only cleared while `metrics.isUserInteracting` was true, so a quick upward flick
  that ended before the next metrics sample left follow-latest armed. Once the
  0.25s cooldown lapsed, the next streaming size change (`.sizeChanges` anchor =
  bottom) yanked the viewport back down. Follow intent now tracks the scroll
  *position* (dropped whenever the viewport leaves the bottom region), not the
  momentary touch state.

## 2.0.5 — 2026-08-19

### Added
- **Streaming Lab A/B modes (DEBUG-only, no production impact).** The Streaming
  Lab now isolates the two variables behind the "smooth stream" feel with three
  replay modes: **A — current Hermes** (glyph fade, no geometry transition),
  **B — fade + smooth geometry** (glyph fade plus an animated height growth),
  **C — no fade + smooth geometry** (geometry transition only). `MarkdownRenderer`
  gained an optional `forceFadeDisabled` override (nil in production, behaviour
  unchanged) so the lab can toggle the glyph fade without writing the user's
  settings. Goal: decide which minimal change actually produces smoothness —
  glyph fade, geometry transition, or both — before touching production.

## 2.0.4 — 2026-08-19

### Fixed
- **Smooth streaming scroll (no more jitter/lag).** The follow-scroll animated on
  every token flush (~20–50/s), so each new token retargeted the previous animation
  — animations cancelled/restarted constantly, reading as rough, jerky scrolling
  while the agent types. Streaming follow now snaps to the bottom without animation
  (a hard glue per flush reads as smooth continuous growth, like Telegram), while
  explicit scroll-to-latest outside streaming keeps its glide.
- **Reduced streaming scroll latency.** Removed the 16 ms pre-scroll sleep on the
  streaming hot path; it queued a new Task per flush that had to hop back onto the
  main actor, accumulating into lag during long replies.
- **Dark gap below the last message.** The overscroll/bounce region past the tail
  could flash dark in dark mode; the scroll backdrop is now painted explicitly so
  the bounce zone matches the theme.

## 2.0.3 — 2026-08-19

### Changed
- **Scroll-to-bottom button moved to the bottom-right and enlarged.** The button was
  a small (32 pt) circle centred at the bottom of the transcript, easy to miss.
  It is now pinned to the trailing edge with a 12 pt inset from the right, and
  grown to 36 pt (icon 13 → 15 pt) so it reads clearly against the composer.

## 2.0.2 — 2026-08-18

### Changed
- **No more bottom-glue while streaming (manual "↓" instead).** Auto-follow is no
  longer re-armed just because the viewport drifted near the bottom during an
  active response — the loose 160 pt streaming threshold could briefly read "near
  bottom", snap follow back on, and yank the transcript down while you were reading
  older messages. While a response streams, follow-latest stays off once you scroll
  up, and the existing scroll-to-bottom button (Telegram/chat-site style) is how you
  return to the tail. Sending a message still re-arms follow.

## 2.0.1 — 2026-08-18

### Fixed
- **Scroll no longer yanks during streaming.** The `.sizeChanges` scroll anchor now
  also respects the user-scroll pause/cooldown, not just follow-latest intent. A
  growing bubble during an active response could previously tug the viewport back
  down while you were reading older messages ("jumps back ~0.5 s").
- **Continuous streaming reveal restored.** Removed the ~120 ms accumulation throttle
  from 1.6.9 — text now appears continuously (native "letters appear" feel) instead
  of arriving in delayed chunks. Smoothness is preserved by the 2.0.0 O(1) transcript
  hot path + memoized segmentation, not by delaying the render.

## 2.0.0 — 2026-08-18

### Performance / architecture (smoothness refactor)
This release is a single, architectural pass on the render pipeline — not a point
patch. Targets the two freeze signatures captured from on-device logs
(`AttributeGraph` + `swift_retain` + `TranscriptMessage` value-witness copies) and
the rhythmic ~30 s idle stutter:

- **O(1) transcript hot path.** `recomputeDisplayedTranscriptMessages()` no longer
  scans the whole message array twice per token flush (an id-array pass plus a
  full-string `content` compare across every message, then a full-array copy). The
  streaming assistant message is always the last element, so a trailing content
  change now updates that one slot in O(1).
- **No second full-history copy.** The `previousMessages: [ChatMessage]` snapshot
  (a complete duplicate of the chat history, kept only for the diff) is replaced
  with three scalars (`previousLastMessageID`, `previousLastContent`,
  `previousMessageCount`). This removes doubled memory on long chats and the
  per-flush full-array copy + retain churn that fed the 357 MB footprint and
  `swift_retain` freeze frames.
- **Idle stutter removed.** The 30 s scheduled-message dispatch now fetches on a
  background `ModelContext` inside a detached task and passes only sendable scalars
  back to the main actor, instead of doing a full SwiftData fetch on `@MainActor`
  every 30 s (which woke SwiftUI/AttributeGraph even when nothing was due).

## 1.6.9 — 2026-08-18

### Fixed
- **Smooth streaming (no more "low fps" text):** the streaming markdown renderer now throttles its re-parse to a ~120ms cadence instead of re-rendering on every token. MarkdownUI's `Markdown(content)` rebuilds the full AST and view tree on each content change, and the stream delivers ~20–50 tokens/s — that quadratic rebuild on the main thread is what made typed text look stuttery/choppy compared to a native client. Tokens now accumulate and the heavy parse runs ~8× less often, so streaming is fluid while still appearing near-instant.

## 1.6.8 — 2026-08-18

### Fixed
- **Streaming hot-path (round 2):** two more per-token costs in the assistant-flush path removed. (1) `messages.firstIndex(where:)` — an O(n) scan over every message on each ~16ms flush — replaced with a `messages.last` fast path (the streaming message is always appended last). (2) In-place `content` append instead of rebuilding the whole `ChatMessage` and rewriting `messages[index]`; the rebuild copied the full accumulated string and forced a copy-on-write array copy with an array-wide retain on every flush — exactly the `swift_retain` / `TranscriptMessage` value-witness frames appearing in freeze stacks.
- **Markdown math segmentation:** `MarkdownMathSegmenter.segments(in:)` is now memoized by last content (mirroring `StreamingMarkdownBlockSplitter`). It ran inside `body` for both static and streaming renderers, doing an O(n) `Array(content)` copy plus a full math-protection mask scan on every token change.

## 1.6.7 — 2026-08-16

### Changed
- **Streaming hot-path:** removed two per-token O(n) operations in the assistant-token path (linear message lookup + buffer `joined()`). Long responses no longer do quadratic string/array work on the main thread, so generation is smoother and uses less CPU.

## 1.6.6 — 2026-08-16

### Changed
- **Hide messaging-channel sessions:** Telegram/Discord/Slack/Email/WeChat sessions are read-only from WebUI (the server rejects a chat start with 403), so the session list now hides them instead of showing chats you can't reply to. WebUI/CLI/other writable sessions are unaffected.

## 1.6.5 — 2026-08-16

### Changed
- **Cache-first session list:** the session list now paints cached sessions immediately on open and refreshes from the network in the background, instead of always waiting on the network first (including the 15s cold-start retry backoff from 1.6.2). The list feels instant even when the server is slow or unreachable — a connectivity failure keeps the cached list under the offline banner, and a real server error (500/401) reverts the cached placeholder so stale data can't mask a live failure.

## 1.6.4 — 2026-08-16

### Changed
- **Hermes-specific connection errors:** replaced the upstream Hermex error copy (which referenced "Mac", "hermes-webui", "Cloudflare tunnel", and "Tailscale") with server-agnostic wording appropriate for a direct Hermes server URL.
- **Softer chat-send failures:** when the server is provably unreachable (no connection, DNS failure, offline), sending a message now retries up to 3× with a 1.5s→3s pause before surfacing the error, so a cold start or brief network blip no longer fails instantly. The optimistic message stays in place during the retries. Retries deliberately exclude timeouts and mid-transfer drops to avoid creating a duplicate run.

## 1.6.3 — 2026-08-15

### Changed
- **Freeze diagnostics:** instrumented the known-expensive main-thread paths on chat open (JSON decode, cached-message read, message apply, tool-call grouping) with the heavy-operation tracker, so the next ChatView freeze reports exactly which step blocked the main thread instead of an empty `heavyOp`.

## 1.6.2 — 2026-08-15

### Changed
- **Offline mode (session list):** when the server can't be reached, the full-screen "Could not load sessions" error row no longer blocks the list. The app now shows a non-blocking "Offline" banner (with cached sessions if available, otherwise an empty list) and auto-reconnects every 10s until the server responds — no manual Retry needed.
- **More resilient session cache:** cached sessions are now shown even past their 7-day expiry (expiry still governs background eviction), so an offline start no longer degrades to a blank error just because the cache aged out.
- **Longer cold-start retry:** the session fetch now retries 5× with exponential backoff (1s→2s→4s→8s ≈ 15s total) instead of 3× over ~1.5s, so a tunnel that's still coming up on cold start has time to connect instead of failing straight to the offline path.
- **Cache sessions without an explicit `sessionId`:** rows are now cached under `sessionId ?? id`, so sessions that only carry an `id` no longer silently skip the cache write.

## 1.6.1 — 2026-08-15

### Fixed
- **Scheduled message "Existing Chat" selection not saving:** the session picker fed a computed `id` into the chosen session instead of the real `sessionId`, so re-targeting to an existing chat silently fell back to an empty/new-chat destination. Now uses `sessionId` (with `id` as fallback) in both the create and edit sheets, and the edit-sheet Save guards against an un-picked existing chat.
- **Pin on long messages:** added `contentShape(Rectangle())` to the message bubble so the long-press context menu (with Pin) triggers across the whole bubble, not just on the text itself.

## 1.6.0 — 2026-08-15

### Added
- **Scheduled message edit → destination picker:** the edit sheet now has the same "New Chat | Existing Chat" segmented picker as the create sheet, so a pending message can be re-targeted from a new chat to an existing conversation (and vice-versa).

### Changed
- **App renamed to "Hermex Plus":** display name (`APP_DISPLAY_NAME` in pbxproj), README header/alt/app-name, and the session-list accessibility label now read "Hermex Plus" (was "Hermes Plus"). README "Current build" link no longer hardcodes a stale CI run.

## 1.5.16 — 2026-08-15

### Fixed
- **Avatar picker still wouldn't open:** the photo picker was presented with `fullScreenCover`, which doesn't reliably present from these navigation contexts on iOS 26. Switched all three avatar pickers (global Sessions Avatar, per-server editor, add-server) to `.sheet`.
- **Scheduled message "choose existing chat":** the session picker reused for scheduling still showed the "Forward To" title; it now shows "Choose Chat" in the schedule flow.
- **Pinned messages:** added an explicit "View in chat" link on each pinned message row (the row already scrolled to the original; now it's visible as a link).

## 1.5.15 — 2026-08-15

### Fixed
- **Sessions avatar (the actual one you tapped):** the global Settings → Identity → "Sessions Avatar" circle was never a button at all — it was a static `Text` with initials. Made it a tappable button backed by a UIKit photo picker, added a `sessionIdentity.avatarImageData` storage key (mirrored to the active server and seeded on new-server creation), and showed the chosen photo in the session-list header avatar. This is the real fix for "avatar doesn't change" — earlier fixes targeted the per-server editor instead.

## 1.5.14 — 2026-08-15

### Fixed
- **Scheduled-message date picker consistency:** the wheel `DatePicker` was presented in a separate sheet that felt detached from the form. Moved it back inline at the bottom of the `Form` (with the title field above it, so the title stays visible above the keyboard). Also aligned the edit-sheet (`EditScheduledMessageSheet`) to the same layout — `TextEditor` for the message and an inline wheel picker — so creating and editing a scheduled message now look the same.

## 1.5.13 — 2026-08-15

### Fixed
- **Scheduled-message date picker layout:** the wheel `DatePicker` was convenient but so tall (~216pt) that the "New chat title" field no longer fit on screen and slipped under the keyboard. Moved the wheel into its own sheet — the main form now shows a compact "Send at" row (tap to open the wheel), so the title field stays visible above the keyboard.

## 1.5.12 — 2026-08-15

### Fixed
- **Settings cards unresponsive (root cause):** the Liquid Glass `glassEffect` on `SettingsCard` was swallowing taps on iOS 26 — the Display Name/Initials text fields and the avatar button did nothing, while `ColorPicker` and preset buttons still worked. Removed the `adaptiveGlass` effect from `SettingsCard` so text input and the avatar tap work again. (Avatar picker presentation was also hoisted to the navigation root — see 1.5.11.)

## 1.5.11 — 2026-08-15

### Fixed
- **Server avatar (root cause):** the photo picker was being presented (`fullScreenCover`/`PhotosPicker`) from the deeply nested `ServerIdentityEditor` inside Settings scroll → card, which does not reliably present on iOS 26. Hoisted the presentation to the top-level `ServerDetailView` and `AddServerView` via an `onPickAvatar` callback — the picker now presents from the navigation root.
- **Scheduled-message date picker:** restored the wheel `DatePicker` (compact style was too fiddly); the `Form` still keeps the title field above the keyboard.

## 1.5.10 — 2026-08-15

### Fixed
- **Server avatar still wouldn't change:** the SwiftUI `PhotosPicker` (both modifier and view) did not present from inside the Settings scroll view / Liquid Glass card on iOS 26 — tapping the circle did nothing. Replaced with a UIKit-backed `UIImagePickerController` presented via `fullScreenCover`, the same reliable path already used for the camera.
- **Scheduled-message sheet keyboard overlap:** the sheet was a `ScrollView` + `VStack`, which does not do keyboard avoidance inside a `.medium` sheet — the keyboard covered the "New chat title" field like a separate window. Replaced with a `Form` (native keyboard avoidance) and a compact `DatePicker`, so the title field stays above the keyboard and the form fits the `.medium` detent.

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
