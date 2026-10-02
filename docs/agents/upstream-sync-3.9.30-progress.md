# Upstream sync → 3.9.30 — resolution progress

**Branch:** `sync/upstream-3.9.30` · **base:** `06cf86b` (main, = v3.9.22 + local pipeline fix)
**Upstream:** `uzairansaruzi/hermex` `master` @ `2bca8e2` · **drift:** 226+ commits
**State (02.10.2026): DEFERRED — the merge was rehearsed, partially resolved, then
aborted on the owner's instruction: 3.9.30 ships on the current upstream base
(upstream 1.6.0 era) without absorbing 1.7.0/1.8.0.** The rehearsal result and the
resolution rules below are kept because they are the expensive part: they are what
a future sync starts from instead of re-measuring. The 11 resolved files and the
`1.9` defect were resolved on `sync/upstream-3.9.30`, which still exists and still
points at the base commit.

To resume: `git checkout -b sync/upstream-next main`, then
`git merge --no-commit --no-ff upstream/master`, and resolve in the order below.
Re-run `python3 scripts/upstream-rehearse.py` first — upstream moved on, so the
conflict set may differ from the 29 files recorded here.

**History:** merge started on `sync/upstream-3.9.30` (from `06cf86b`), 29 conflicted
files, 88 blocks.

Source of truth for the conflict set: `python3 scripts/upstream-rehearse.py`
(this list was produced by it, then re-confirmed by the live merge).

**Why this sync exists (product goals):** a message sent while the agent is
responding must never be lost, never erase the composer draft, and never spend
the user's attention on provider errors. Upstream already fixed the cluster:
`74d220d` (#906 refused steer must not stop the run), `c956105` (#916 Queue/Steer/
Stop & send per message), `2cbef96` (#913 queued messages survive leaving a chat),
`36a7058` (#908 reconnect + "Waiting for network"), `8e48554` (#980 composer focus).
Plus the fork's own share fix: both apps declare `hermes-agent`, so the fork needs
its own URL scheme.

## Resolved — 11 of 29 files

| file | blocks | how |
|---|---|---|
| `README.md` | 1 | union: upstream's Free/Private/Native bullets + our release link line |
| `.gitignore` | 1 | union: our `/CURRENT.md` block + upstream's Python comment, deduped |
| `HermesMobile.xcodeproj/project.pbxproj` | 8 | union (no object id on both sides), then **removed upstream's `MARKETING_VERSION = 1.9` ×10** — two models of one field, ours (3.9.22) wins |
| `Features/Chat/StreamingMarkdownSupport.swift` | 1 | **ours wins**: the fork's incremental `ScanState` scan (O(N²) fix) supersedes upstream's re-scan; upstream's constant rename (`stableChunkTargetUTF8Count`) kept |
| `ContentView.swift` | 1 | theirs (adds the pending-shared-draft import) + their more precise `run-end` wording |
| `Features/Chat/ChatComposerConfigLoader.swift` | 1 | theirs: the whole block became `resolveProfile(into:)` — pure decomposition |
| `Features/Chat/ChatMessageActions.swift` | 1 | union: our `selectText/reply/forward/save/pin` + upstream's `react/removeReaction` |
| `Models/ChatMessage.swift` | 1 | union: `serverID` (ours) + `rowID` (theirs); the body already assigns both |
| `Networking/APIError.swift` | 1 | theirs (error text now mentions local-network/Tailscale) |
| `HermesMobileTests/APIClientAuthAndErrorTests.swift` | 1 | theirs — must match the APIError text above |
| `Features/Workspace/FilePreviewViewModel.swift` | 1 | union: our `isKnownUnsupportedBinaryPath` branch + upstream's `.quickLook`/`.unavailable` branches (both symbols live in the file) |

Structural check after this batch: `scripts/check-swift-structural-balance.py` reports
**no blocker in any resolved file** — the eight it still flags are exactly the files
that still contain conflict markers.

## Remaining — 18 files, 70 blocks

| file | blocks |
|---|---|
| `Features/Chat/ChatView.swift` | 9 |
| `Features/Chat/ChatViewModel.swift` | 7 |
| `Features/Chat/ChatComposerView.swift` | 6 |
| `Features/Chat/MarkdownRenderer.swift` | 6 |
| `Models/ServerAccount.swift` | 6 |
| `Persistence/CacheStore.swift` | 4 |
| `Features/SessionList/SessionListView.swift` | 4 |
| tests `ChatViewModelSendTests.swift` | 4 |
| `Features/Chat/ChatComposerTextInputView.swift` | 3 |
| `Features/Chat/ChatTranscriptView.swift` | 3 |
| `Networking/APIClient.swift` | 3 |
| tests `ChatComposerConfigLoaderTests.swift` | 3 |
| `Features/Chat/ChatStreamCoordinator.swift` | 2 |
| `Features/Chat/MessageBubbleView.swift` | 2 |
| `Features/Chat/TranscriptMediaView.swift` | 2 |
| `Features/Settings/SettingsView.swift` | 2 |
| `Features/SessionList/SessionListViewModel.swift` | 2 |
| tests `BotChatPresentationTests.swift` | 2 |

## Rules being applied

- Upstream-first for fixes; `HERMEX-FORK:` markers for local behaviour.
- Union only for **declarations**; a block whose closing brace/comma sat at the end
  of a side must not be concatenated (see `merge-conflict-structural-integrity`).
- After each file: `scripts/check-swift-structural-balance.py` and
  `scripts/check-duplicate-declarations.py`; the whole set at the end via
  `scripts/pipeline-precheck.py`.
- Never take a side wholesale on `ChatView`/`ChatViewModel`/`ChatComposerView`:
  the fork's composer (unified card, 8pt margins, scheduled badge, mic placement)
  and the fork's additions (scheduled messages, pinned messages, share import,
  clarification surfaces, read-aloud) must survive.

## After the merge commit

1. Version bump in its own commit: `VERSION`, `CHANGELOG.md`, `MARKETING_VERSION`
   → **3.9.30** (gate 1 blocks a product change under the released 3.9.22).
2. Push the branch and open a PR — `pr-ci.yml` triggers on `pull_request`; a pushed
   branch alone runs no CI.
3. CI must be green on both sides: the fork's 2480 tests and upstream's new tests.
4. Only then: the fork's own 3.9.30 additions (share URL scheme, the three
   invariants' metrics for the existing watchdogs).

## Known traps found so far

- `MARKETING_VERSION` union (fixed) — the same shape will appear anywhere both
  sides set one logical field: check for duplicated keys per build configuration.
- Upstream renamed/deleted workflows we do not use (`internal-testflight.yml`,
  `external-testflight.yml` → `release-candidate-testflight.yml`). Our
  `build-ipa.yml` is fork-owned and survives (confirmed by the rehearsal's OURS list).
