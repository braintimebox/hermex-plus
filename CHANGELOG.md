## 3.9.41 — diagnostics only: stream-commit telemetry. A new `streamCommit` channel (per 2s window) records commits, accumulated/delta chars, commit interval, stream age, follow-latch state, programmatic follow-scrolls and the frame each commit landed in — enough to tell apart follow-scroll contention, full-text relayout, initial-layout dominance and coincidence with background operations. The 3.9.40 frame channel and the jank channel are untouched. No behaviour change

## 3.9.40 — diagnostics only: frame histogram. Every 2s window now logs the distribution of ALL frames (buckets <8.33 / 8.33-16.67 / 16.67-33.33 / 33.33-50 / >50 ms, percentiles p50-p99, max) with one context tag (idle / scroll / stream / scroll+stream / app_update). The existing jank event is untouched so the 3.9.36-3.9.39 baseline stays comparable. No behaviour change: no ProMotion key, no debounce, no fixedSize, no layout change. This build measures the physics of the system before any optimisation

## 3.9.39 — diagnostics only: instrumentation for the real streaming markdown path. The splitters, fade blocks and advanceFadeWindow were replaced by the plain-text live renderer in 3.4.0 and are no longer reachable; what runs per update is the rendering policy and, above 4000 characters, PlainMarkdownFallbackView — the view whose layout still carries the .fixedSize that P0 in 3.4.8 removed from LightStreamingRenderer. This build measures the policy cost once per frame, the empty/fallback/light branch share with text size, and splits markdown parse by isStreaming. Fallback is a branch counter, not a layout timer; .fixedSize layout cost is correlated against hitch/freeze, not measured here. No behaviour change

## 3.9.38 — cache: messages and sessions get separate serial write queues (e45aa2b) — one shared queue put a completed turn's cache write behind a session upsert and made testCompletedResponseCachesFinalTurnTpsWithoutTranscriptReload time out at 10 s. Per-scope ordering preserved, both queues stay off the main thread. This build is the verification for that regression

## 3.9.37 — test speed: retry backoff made injectable (HermesRetryBackoff) and zeroed in the two affected test classes, so a simulated connectivity failure no longer costs 15 s of wall clock per case. Production schedule unchanged (1+2+4+8 s); the retry loop still runs all five attempts. Expected Test 640 s to about 520 s

## 3.9.36 — diagnostics only: draft lifecycle probe (setContent/setDraft/clearDraft/resolveSubmission/moveDraft/restoreAbandonedNewChatDraft/hydrate) logging draft key + text length + didStartConversation, so the draft resurrection chain is proven from logs instead of inferred. No behaviour change

## 3.9.36 — diagnostics only: draft lifecycle probe (setContent/setDraft/clearDraft/resolveSubmission/moveDraft/restoreAbandonedNewChatDraft/hydrate) logging draft key + text length + didStartConversation so the draft resurrection chain is proven from logs instead of inferred. No behaviour change: markConversationStarted wiring and .newChat semantics untouched until the runtime logs land

## 3.9.35 — cache: session cache writes run on a serial cache queue off the MainActor and are awaited, so ordering and read-after-write both hold while the UI never blocks on the write; cache-write telemetry split per writer. Attribution correction: the 522/1123 ms phase readings were background time — the main-thread blocker in the logs is transcriptMessages.fullRecompute (up to 1008 ms), recorded as the next step and not touched here

## 3.9.35 — cache: session cache writes moved off the MainActor onto a serial cache queue (ordering guaranteed by construction); cache-write telemetry split per writer. Attribution correction: the 522/1123 ms phase readings were background time — the main-thread blocker in the logs is transcriptMessages.fullRecompute (up to 1008 ms), recorded as the next step and not touched here

## 3.9.35 — cache: session cache writes moved off the MainActor onto a serial cache queue, so ordering is guaranteed by construction; cache-write telemetry split per writer (Cache Write / Cache Write (sessions) / Cache Write (session)). Attribution correction: the 522/1123 ms phase readings were background time — the main-thread blocker in the logs is transcriptMessages.fullRecompute (up to 1008 ms), recorded as the next step and not touched here

## 3.9.34 — telemetry bridge: #920 phase durations (Stream Batch Apply, Transcript Apply, Markdown Parse, Cache Read/Write, Session Open) now aggregate into hermex-logs.jsonl as type=phase events with count/p50/p90/max and context (chars, mutated, messages, rows). No per-interval disk I/O; signposts and the hitch meter unchanged; the watchdog and jank events untouched

## 3.9.34 — telemetry bridge: #920 phase durations (Stream Batch Apply, Transcript Apply, Markdown Parse, Cache Read/Write, Session Open) now aggregate into hermex-logs.jsonl as type=phase events with count/p50/p90/max and context (chars, mutated, messages, rows). No per-interval disk I/O; signposts and the hitch meter unchanged; the watchdog and jank events untouched

## 3.9.34 — instrumentation: upstream #920 signposts (Session Open, Transcript Apply, Markdown Parse, Stream Batch Apply, Cache Read/Write) plus a DEBUG-only frame-hitch meter behind --hitch-meter. Measures only — no optimisation, no behaviour change; the existing watchdog and freeze telemetry stack is untouched

## 3.9.33 — draft: a message sent during a run no longer returns as a draft — the streaming send path clears the durable draft store the same way the standard path does, so re-entering the chat stops restoring text that was already sent; the two paths now share one sequence, pinned by a regression test

## 3.9.32 — goal card: the notice clears itself after three seconds — the card is one line with its own dismissal, a send clears it, and now the timer does too, so a status nobody acts on cannot hold reading space; all three exits share one method so they cannot drift apart

## 3.9.31 — share: the payload no longer depends on the URL arriving — the drain runs on activation and the destination dialog is re-asked when the app returns from the extension, so a share sent while Hermex was backgrounded lands in the chosen chat instead of opening an empty one (measured 02.10 20:54: the payload was reserved while backgrounded, the dialog was requested with the scene inactive and dropped, and the text was retyped by hand); the goal status card is one line with its own dismissal and clears on the next send, instead of holding a third of the transcript with the keyboard up until the chat was reloaded; pipeline: tests and the device build run in parallel and publication sits behind both (needs: [test, build]) so a red suite still cannot release

## 3.9.30 — release 3.9.30

## 3.9.30 — every failed delivery is caught, in one shape: send, steer, queued message, voice note, attachment, scheduled send, approval and clarification each report their failure through `DeliveryTelemetry`, which classifies it (offline, unreachable, timeout, rate limited, quota, server, bad request, unauthorized, decoding, cancelled) with the privacy-safe category the log already uses and whether repeating it could duplicate work — the point being that a message which did not arrive is never silent, whatever the error happens to be called; only a transport that is down reaches the screen; share opens Hermex Plus and not the App Store app (the fork declares its own URL scheme `hermesplus` instead of upstream's `hermes-agent`, which both installed apps claimed — a test pins it, like gate 14 does for the bundle id); Send during a response no longer stops the run — a refused steer queues the message instead of cancelling the agent's work in progress; Reply, Forward, Save and Pin stay available while the agent writes (a pin is screen-local, the rest only read), while Edit, Fork and Regenerate stay disabled; gate 17

## 3.9.22 — share: fallback to a named pasteboard when the app group container is unreachable (sideloaded builds lose the entitlement), with the transport logged; composer: 8pt horizontal margin

## 3.9.21 — composer: widen layout to 8 pt horizontal margin (closer to edges while keeping safe clearance from hardware rounded corners)

## 3.9.20 — composer: attach files through a UIKit document picker (asCopy, multi-select) — the SwiftUI .fileImporter never delivered a picked file, so the picker's Open button did nothing

## 3.9.19 — composer: unified solid card block enclosing the input field and toolbar row, no transparency, mic and scheduled badge in place

## 3.9.18 — composer: the mic and the scheduled-messages badge leave the horizontal scroller and join the fixed part of the row (with Send), so they are always on screen; the scroller keeps the selectors

## 3.9.17 — revert: the composer is back to the 3.9.13 view — my last three changes lost the mic while typing, hid Send on an empty field and pushed the model/workspace row behind a menu. The measured field-height fix and the telemetry stay

## 3.9.16 — composer: adaptive layout — the collapsed row stays the reference, the expanded state becomes two zones inside the same card (full-width field + a compact tools band), so the field gets its width back and the controls stop drifting to the middle

## 3.9.15 — the goal button in the header comes back after re-entering the chat: the state is restored from the server on entry, silently. The goal block itself is left as it was

## 3.9.14 — the composer keeps one row with the keyboard up: focus no longer inserts the selector row (it moved behind the plus menu), so the expanded state matches the collapsed look he liked

## 3.9.13 — the field's container is no longer a flexible frame: it is pinned to the measured text height, so the field stops stretching to its 108pt ceiling and the surface stops reserving 110pt around an empty draft

## 3.9.12 — measurement build: the composer reports its own numbers (field width/laid-out height/clamped, plus surface and row heights) so the next fix targets the real addend instead of a guess

## 3.9.11 — composer field height comes from the laid-out text (layoutManager.usedRect) instead of sizeThatFits, which returned the 96pt ceiling for an empty field — the field stops sitting five lines tall

## 3.9.10 — composer height stops oscillating: re-measure on width change, publish only on a real height change (3.9.9 closed a feedback loop through the transcript inset)

## 3.9.9 — composer height unstuck: the field re-measures when its width changes, so a one-line draft no longer keeps a four-line card (telemetry showed the field pinned at its 96pt ceiling)

## 3.9.8 — composer look restored: the 3.9.7 composer change is reverted, controls and plus menu are back where they were

## 3.9.7 — composer is one line at rest like Telegram: the 44pt control row now waits for content instead of appearing on focus, so the transcript keeps that height until you type

## 3.9.6 — multi-line drafts stay inside the composer card: the ceiling moved onto the text frame and the container admits its padding, so text scrolls inside instead of drawing over the border

## 3.9.5 — composer is shorter at rest: the empty focused card loses ~50pt (field one line, tighter padding, controls row closer), glass look untouched

## 3.9.4 — composer opens as one line and no longer shows the transcript through the field; Copy is back for assistant replies

## 3.9.3 — composer opens as one line and stops showing the transcript through the field; Copy is back for assistant replies

## 3.9.2 — schedule wiring restored (long-press Send works again, counter badge back), opaque header bar, composer growth policy, gates 15-16

## 3.9.1 — the fork signs as com.braintimebox.hermexplus, so it installs beside the App Store Hermex instead of colliding with it; gate 14 pins the identifier so a merge cannot take upstream's side and restore the collision; includes 3.8.2's composer fix (no reading-mode FAB, no state that could hide the composer)

## 3.9.0 — Hermex Plus signs under its own bundle identifier (com.braintimebox.hermesplus), so it installs beside Hermex instead of colliding with it — first install lands as a fresh app and the server password is entered once. Also lands the release-pipeline fixes: the build watch no longer abandons a green build

## 3.8.2 — the composer never disappears — the reading-mode FAB and the state that could hide both it and the composer are gone, so tapping the chat only dismisses the keyboard; the reasoning list is computed once per frame instead of twice, and the typing indicator stops once a response's content is final

## 3.8.1 — attachments are read off the main actor (an iCloud file no longer freezes the composer) and a refused attachment names its reason; the composer offers None to turn reasoning off

## 3.8.0 — the session list self-recovers from any load failure, and the failure is now logged

## 3.7.0 — Upstream 1.6.0 sync

Merged `uzairansaruzi/hermex` upstream `1.6.0` (105 commits since the fork point).
Every conflict block was resolved by measurement, not by preference: our blocks
carry a measured cause in their comments and were kept, their structural
additions were taken, and independent additions were unioned.

### Scroll — the two models now cooperate instead of competing

- `sizeChangeAnchor` is **back**, conditioned on `shouldFollowLatestMessage` and
  `isDisclosureSettling`. It returns `nil` while the reader is parked, so the
  engine can no longer yank the viewport on its own. Our own code had removed
  this anchor because the unconditional form yanked, then compensated by hand
  across 27 commits.
- Their `FollowLatch` is the **only** owner of the viewport. `ChatScrollOwner`
  and `ScrollOwnershipState` are gone, and the comments in `ChatView` say so:
  two owners was the conflict, and a change of owner re-evaluated the whole
  `ChatView` body plus its environment cascade — the shape behind the 3–14 s
  AttributeGraph freezes. Their latch produces far fewer transitions, so the
  container had nothing left to isolate. It is covered by 27 of their tests.
- Kept our ↓ button behaviour. The tap cancels an in-flight deceleration before
  the programmatic scroll, because `ScrollViewProxy.scrollTo` is silently ignored
  while a flick is still coasting — without it the button looks dead until the
  scroll stops. The merge kept the observer and dropped the `post`, so this is a
  restoration, not a new feature.
- `ChatPrependScrollPositionController` is replaced by
  `ChatScrollPositionController`, which is that class plus `Mode.hold`,
  `hasPrependCapture`, `didRevertSwiftUIOffset`, `resyncAfterHold`,
  `contentSizeChangedThisTurn` and `quietReleaseTask`. Position is released
  when content settles rather than after a fixed one-second timer.
- Their `ignoresCoastingGesture` closes a case we never modelled: a send or
  scroll-to-bottom while the transcript is still decelerating.

### Share — one transport, one visible failure path

- The share extension and the app now exchange drafts through the App Group
  container with a reservation, instead of our pasteboard channel plus a
  URL payload. The extension also reports every failure in place
  ("Could not save shared content.", "Shared content saved. Open Hermex
  manually.") and tries four ways of opening the host app.
- Destination **choice is kept**: shared content asks where it should land
  ("New Chat" / "Choose existing…"), and the reservation is released exactly
  once for whichever branch consumes it, cancel included.

### Streaming — cheap live path, complete settled path

- Kept our O(1) live renderer; the settled path takes their
  `MarkdownMathLayoutCache` and selectable headings. Formatting and math still
  appear when the stream settles; the hot path never pays for them.
- Kept our measured per-token fixes: the incremental transcript fast path, the
  reload-amplification guard, the pagination cursor, EXPERIMENT B identity and
  the pan-gesture metrics hook. `TranscriptMessageContent` is gone: it was our
  3.4.8 scroll-isolation container, dead since their latch took the viewport, and
  Swift still type-checked its 40-argument row on every build.
- Took their terminal content fence (it survives `streamEnd`, which our flag did
  not) and `setLiveTokensPerSecondIfChanged` (no write when the value is
  unchanged).

### Chat — features

- Pin, Save, Scheduled Messages, Forward and Reply are preserved. All five are
  expressed through the upstream `ChatMessageActionItem` API so the SwiftUI
  menu and the UIKit context menu stay in step.
- Took `ChatDraftStore`: drafts are keyed per chat **and per server**, flushed
  to disk, and carry quotes, attachments and settings. On-hydration text is
  preserved instead of being overwritten.

### Composer

- Collapsed pill / expanded card behaviour, where a tap on the field expands it
  and presenting a sheet never snaps it shut. Our height cap (96pt) and the
  no-op height-update guard are kept, so the field cannot balloon and typing
  does not relayout the transcript.

### Workspace

- The file tree **opens closed**. Upstream expanded every top-level folder on
  first visit, which on a phone buries the workspace's own entries behind a wall
  of their children. The reader now expands what they need, and that choice is
  remembered per server and workspace.

### Sessions

- Messaging-channel sessions (Telegram, Discord, Slack…) are **listed** again.
  We hid them because the server refused to continue them; upstream #320 removed
  that refusal and routes them through the import step, so the filter was hiding
  rows the app can now open.

### Lines the union dropped

The merge could not be compiled for a day, and that hid every error behind the
first one. Six lines had been lost to a union that took one side of a hunk, and
they only became visible once the file compiled:

- `actions.pendingActionCoordinator = pendingActionCoordinator` in
  `ChatViewModel.init`. `ChatActionsState` holds the coordinator weakly, so the
  approval prompt, the clarification prompt, the session approval bypass and both
  action error messages read `nil`/`false` for the life of the view model.
- the `didSet` that clears `sendErrorIsFromStreamRecovery`, so a later send error
  was wiped by an earlier recovery confirmation;
- `transcriptRevision &+= 1` in `applyReloadedMessages`, so a reload that only
  rewrote a row's contents never re-scanned it;
- a trailing `errorMessage = nil` that swallowed the offline timeout message;
- two call sites still passing two arguments to `onScrollToLatestContent`.

Twenty-four tests failed the moment the build first succeeded. All of them pass.

### Release mechanics

- `VERSION`, the CHANGELOG heading and every `MARKETING_VERSION` now agree.

---

## 3.6.1 — release 3.6.1

## 3.6.0 — Scroll cleanup (dead code removal + stream guard)

### Scroll — removed dead `sizeChangeAnchor`

- `ChatScrollPolicy.sizeChangeAnchor()` was defined (25 lines) but never called. Removed with its documentation block.

### Scroll — removed dead `explicitFollowCommand` parameter

- `resolveOwner(explicitFollowCommand:)` was accepted but never passed `true` by any caller. Removed. The ↓ button is now documented as one-shot in the `resolveOwner` docstring.

### Scroll — streaming follow guard against double-fire

- `onChange(of: streamingScrollTrigger)` now checks `activeStreamID != nil`. Without this, non-streaming events (loadMessages, reloadMessages) that also bump the trigger caused a redundant `scrollTo` alongside `onChange(of: messages.count)`.

### Scroll — stale comments cleaned

- Removed 4 outdated comments referencing `sizeChangeAnchor`, the old "160pt streaming band", and "Telegram-style no auto-glue" — all describe mechanisms that no longer exist in the codebase.

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

---

# Upstream history

Synced from `uzairansaruzi/hermex`. Kept below our release history because
`scripts/release-check.py` requires the top heading to equal `VERSION`.

## [1.6.0] - 2026-09-05

### Added
- Redesigned chat transcript: settled tool calls, live tool activity, and
  thinking render as compact log rows, finished turns fold behind one
  elapsed-time row, a working-for counter sits at the transcript tail, and
  each message carries a timestamp and copy button. Expanded rows are capped at
  a scrollable window and new rows fade in.
- Pill-shaped Liquid Glass composer with a toolbar row when focused, combined
  model and effort controls with provider glyphs, and haptics for disclosures,
  copies, and Git actions.
- Reference workspace files from the composer with `@path` chips.
- Slash and skill autocomplete triggers at the caret, ranks by match quality,
  and shows a picked skill as a chip in the composer and in the sent bubble.
- Workspace file tree that loads lazily, a syntax-coloured source viewer for
  files, file-type icons, and chat file links that open in the viewer.
- Git review surface that shows every changed file in one diff.
- Markdown workspace images render inline and zoom in a full-bleed viewer;
  Markdown files render in workspace previews.
- Tasks list rebuilt as an agenda with filters, row actions, and recent runs
  across all tasks; Task Detail redesigned with per-task run history and a
  model, provider, and profile picker.
- Insights rebuilt as a Usage screen with a window chart.
- Session rows show Approval, Input, and Working states, and search results
  show why they matched.
- `/clear` clears the session's server-side history.
- Settings > Default Model and Default Profile share the composer's model
  picker; Providers gets matching glyphs and list chrome.
- The clarification card pins above the composer.
- Attachments can be sent without composer text.

### Changed
- Reasoning effort changes are scoped to the session instead of applying
  globally.
- The "Checking stream" chip and status polls stay hidden while transport
  heartbeats are fresh.
- HTTP 403 responses surface the server's reason.

### Fixed
- Partial streams survive relaunch, foreground stream recovery no longer races
  itself, and late events after a response completes are ignored.
- Unsent composer text, attachments, and settings persist as drafts.
- The default model persists with its provider and the picker exposes the full
  model catalog.
- Trusted-header and OIDC sign-in report their real state, and stale auth
  status is invalidated when the URL or headers change during onboarding.
- Incoming shares are transactional and no longer leave half-staged imports.
- "Working for" and "Worked for" count from the server's turn start.
- Transcript scroll position survives reloads and disclosure toggles, and
  auto-follow is an explicit latch.
- CLI and messaging sessions can be continued from the app, and duplicating a
  session uses the server's duplicate endpoint instead of branching.
- Kanban restores the browsed Board per server after relaunch, and the Board
  picker stays visible for long Board names.
- Server First dictation runs until the user stops it, and oversized
  transcription uploads are rejected before they fail.
- Inline assignment math renders correctly.
- Streaming thinking stays responsive, cached-message lookups are batched, and
  settled Markdown math layouts are cached.

## [1.5.0] - 2026-08-04
