# Upstream sync — rehearsal results and resolution plan

Produced by merging `upstream/master` into a throwaway clone (`/tmp/upstream-rehearsal`)
on 2026-09-11, **without touching the working repository**. The point is that the
conflict set is now known in advance: it is fixed and repeatable, so it is resolved
once, deliberately, rather than discovered while panicking.

**Regenerate with the script, not by hand.** `scripts/upstream-rehearse.py` does
everything below, classifies every block, and never touches the working repo:

```bash
python3 scripts/upstream-rehearse.py                    # full report
python3 scripts/upstream-rehearse.py --resolve-pbxproj  # + mechanical union
python3 scripts/upstream-rehearse.py --clean            # remove the clone
```

The manual equivalent, if the script itself is the thing being debugged:

```bash
rm -rf /tmp/upstream-rehearsal
git clone ~/.hermes/_projects/hermex-plus /tmp/upstream-rehearsal
cd /tmp/upstream-rehearsal
git config user.email "rehearsal@local" && git config user.name "Rehearsal"
git remote add upstream https://github.com/uzairansaruzi/hermex.git
git fetch upstream master
git merge --no-commit --no-ff upstream/master
```

---

## What the merge absorbs

| | |
|---|---|
| Commits to absorb | **104** (upstream drift from the merge-base, not from the stale mirror) |
| Upstream files added | **298** (mostly `Features/Bots/*`) |
| Conflicting files | **34** |
| Conflict blocks | **141** — of which **18 require no judgement at all** |

**Measure the drift from `git merge-base main upstream/master`, never from
`origin/master`.** `origin/master` is a read-only snapshot of upstream and it can
lag arbitrarily; here it lagged 104 commits behind while still being a valid
ancestor. `sync-upstream --status` now prints both numbers separately
(`upstream drift` vs `mirror lag`) for exactly this reason.

### 18 of the 141 blocks are auto-resolved

The rehearsal separates *"one side is empty"* (pure insertion) from *"both sides
edited the same region"*. An insertion-only block has no decision in it: keep the
non-empty side. Per-file counts from the live run:

```
ChatView.swift                     26 blocks   4 insertion-only
ChatTranscriptSupportingViews.swift 21 blocks   2 insertion-only
ChatViewModel.swift                 17 blocks   5 insertion-only
ChatTranscriptView.swift            16 blocks   2 insertion-only
MarkdownRenderer.swift               5 blocks   2 insertion-only
SessionListView.swift                5 blocks   1 insertion-only
Skills.swift, .gitignore             1 block each
```

So the real decision load is **123 blocks, not 141**. Work the auto ones first:
they shrink the file before you have to reason about it.

Merge, not rebase. Rebasing replays ~413 of our commits onto upstream and dies in
`CHANGELOG.md` bookkeeping (158 of our edits vs 3 of theirs); merge yields one fixed
conflict set instead of hundreds.

---

## Work order — biggest first, so the shape is known early

| Blocks | File |
|---|---|
| 26 | `HermesMobile/Features/Chat/ChatView.swift` |
| 21 | `HermesMobile/Features/Chat/ChatTranscriptSupportingViews.swift` |
| 17 | `HermesMobile/Features/Chat/ChatViewModel.swift` |
| 16 | `HermesMobile/Features/Chat/ChatTranscriptView.swift` |
| 10 | `HermesMobile.xcodeproj/project.pbxproj` |
| 5 | `HermesMobile/Features/SessionList/SessionListView.swift` |
| 5 | `HermesMobile/Features/Chat/MarkdownRenderer.swift` |
| 3 ×3 | `SessionListMutationTests`, `CacheStore`, `APIError`, `ChatStreamCoordinator`, `ChatScrollPolicy`, `ChatComposerTextInputView` |
| 2 ×4 | `ChatScrollPolicyTests`, `APIClientAuthAndErrorTests`, `FilePreviewViewModel`, `TasksView` |
| 1 ×13 | README, AGENTS.md, CHANGELOG, .gitignore, ContentView, AppTheme, ChatMessage, Skills, SettingsView, SessionListViewModel, MarkdownMathSegmenter, ChatMessageActions, ChatComposerView, TranscriptDisplayModelTests, ChatViewModelSendTests |

Two files carry no blocks but still need a decision:

- УДАЛЁН: `docs/agents/domain.md` — **deleted by upstream, and we accept the deletion.**
  Upstream removed it but kept the `docs/agents/` directory and added `bots.md`, `i18n.md`,
  `kanban.md` there (verified: `git ls-tree upstream/master docs/agents/`). Our only edit
  was a pointer to `testing.md`, and that pointer now lives in `HERMES.md` — our own file,
  which upstream never touches. Taking upstream's deletion costs nothing and removes a
  permanent `UD` conflict. Do not resurrect it.
- `HermesMobile/Features/Chat/ClarificationRequestOverlay.swift` — **added by us, deleted
  upstream** (upstream restructured overlays). Keep ours unless our feature moved.

---

## Resolution rules per class

### Bookkeeping — the conflict is small; upstream's body wins

Measured in the rehearsal: the merge already takes upstream's file wholesale, and only
our inserted block conflicts. So the resolution is "keep upstream, re-apply our lines",
not "take ours" — which would discard upstream's rewrite.

| File | Upstream | Ours | Our lines inside the conflict |
|---|---|---|---|
| `README.md` | 146 lines | 63 | 3 — the License section |
| `AGENTS.md` | 169 lines | 86 | 18 — the Session start & wrap-up section |
| `CHANGELOG.md` | 91 lines | 55 | 1 — the `sizeChangeAnchor` entry |
| `.gitignore` | 59 lines | 65 | 7 — `/CURRENT.md` and the Python block |

Take upstream's side, then re-insert exactly these:

- **README.md** — keep our `## 📄 License` / `MIT — same as upstream.` section.
  Upstream's is a store-facing landing page; ours says the fork is MIT.
- **AGENTS.md** — keep our `## Session start & wrap-up` section (18 lines):
  `CURRENT.md` first, `docs/project-snapshot.md` as the state source,
  `PROJECT_SPEC.md` sections only as named, and the wrap-up step. Upstream's AGENTS.md
  has no equivalent, and dropping it loses the session-handoff convention.
- **CHANGELOG.md** — keep the single `sizeChangeAnchor` line under the 3.6.0 heading,
  then append upstream's `[1.6.0]` section **below** our release history. Our
  CHANGELOG is read by `release-check.py` (top heading must equal VERSION), so our
  entries must stay on top.
- **.gitignore** — keep `/CURRENT.md`, `__pycache__/`, `*.pyc`. Upstream has no
  Python or session-handoff rules.

### Our files — take ours, never drop

Upstream does not know these exist, so a merge that "cleans them up" silently deletes
the release pipeline:
`HERMES.md`, `CONVENTIONS.md`, `.githooks/pre-push`, `.github/workflows/build-ipa.yml`,
`docs/agents/testing.md`, `scripts/lint-tests.py`, `scripts/pipeline-precheck.py`,
`scripts/pipelines/release_hermesplus.py`, `scripts/sync-upstream`, `ops/`.
All verified present and unmodified after the rehearsal merge.

**Tests — take ours where we added coverage, upstream's where they added coverage.**
Our test files carry session/cache/link-preview coverage that upstream lacks. Read both
sides: upstream may have fixed a test we worked around.

**App code — resolve by intent, not by side.** These are the SHIM files: both sides
edited the same regions, so neither "ours" nor "theirs" is correct wholesale. For each
block, decide whether our change and upstream's are about the same behaviour:

- Same behaviour, different implementation → take upstream's, then re-apply our intent on
  top if it is still missing.
- Different behaviour → keep both, in upstream's structure.

**`project.pbxproj` — mechanically resolvable, and verified so.** This is not a
judgement call and should not be treated as one. There is no XcodeGen or other project
generator in this repo: the pbxproj is committed and edited directly, so both sides
append entries to the same lists.

The rehearsal **proves** the union is safe: the 24-hex object ids on our side (16) and
upstream's (56) **do not intersect at all** — 0 shared out of 72. Both sides are adding
independent `PBXBuildFile` / `PBXFileReference` / group / build-phase entries, so keeping
both is well-defined by construction. The checker is `pbxproj_ids_are_disjoint()` in
`scripts/upstream-rehearse.py`; the numbers above are its output on the live run, not an
estimate.

```bash
python3 scripts/upstream-rehearse.py --resolve-pbxproj
# resolves it in the rehearsal clone only; copy the file over deliberately
```

After copying, the result has 0 markers and balanced braces, and both sides' files are
present in the Sources lists (verified: `SavedMessage.swift`, `HermexLogger.swift`,
`BotChatView.swift`, `BotConnection.swift`, `ResponseTextSelection.swift`,
`MainThreadWatchdog.swift` all present).

Then confirm nothing was dropped:

```bash
git diff --stat -- HermesMobile.xcodeproj/project.pbxproj   # expect added lines on both sides
python3 scripts/pipeline-precheck.py                        # gate 3: new .swift must be registered
```

Gate 3 reports a staged `.swift` whose name appears fewer than twice — it catches a
dropped registration, not a duplicated one.

**Union is correct for this file and for nothing else.** Two edits to the same Swift
function from the two sides are not independent entries, and keeping both produces code
that compiles only by accident.

---

## Known traps

1. **`permissions: contents: write`** — the `build` job in `build-ipa.yml` needs it for
   `Create Release`; without it the run fails with 403 *after* tests and packaging pass.
   Already fixed in our tree. Confirm it survives the merge, since that file conflicts.
2. **`SessionTimeouts`** in `APIClient.swift` and the guard in `CacheStore.cacheMessages`
   are recent fixes. Upstream may have touched the same regions.
3. **УДАЛЁН: `docs/agents/domain.md`** — deleted by upstream, accepted by us.
   Its only unique content was a pointer to `testing.md`, and that pointer now lives in
   `HERMES.md` (our file — upstream never conflicts with it). Upstream kept the
   `docs/agents/` directory and added `bots.md`, `i18n.md`, `kanban.md`, so nothing in the
   directory is lost by accepting the deletion of this one file.
4. **CI is the only compiler.** There is no Swift toolchain on Linux. Resolve everything,
   then let CI tell you what does not typecheck — budget several runs.

---

## Cost

**The Actions quota is NOT a constraint on this repository.** `braintimebox/hermex-plus`
is **public** (verified: `gh repo view` → `visibility: PUBLIC`), and GitHub does not bill
Actions minutes for standard runners on public repositories — macOS included. The earlier
"≈90 billed minutes per push, quota is the binding constraint" line was carried over from
`telegram-plus`, which is private and where the 10× macOS multiplier really did exhaust
2000 free minutes. Do not plan the sync around a budget that does not apply here.

What each push **does** cost is wall-clock: `guard → test → build` is roughly 9–11 minutes
on a macOS runner, and `build-ipa.yml` has no `concurrency` block, so every push to `main`
runs the full job to completion. `pr-ci.yml` has `cancel-in-progress: true`.

**Batch the work on a branch anyway** — not for minutes, but because a half-resolved
conflict must not land on `main`, and because `build-ipa.yml` publishes a Release on every
push to `main` (verified: `Create Release` step is `if: github.event_name == 'push'`).
Merging the sync through a branch makes the sequence restartable and keeps the release
channel clean. Expect several CI iterations to find the type errors Linux cannot see.

---

## Recommended sequence

Run the rehearsal first — it costs nothing and answers every question below.

```bash
cd ~/.hermes/_projects/hermex-plus
python3 scripts/upstream-rehearse.py       # conflict set + our lines to re-apply
# read docs/agents/upstream-sync-plan.md alongside the output
```

Then, in the working repo:

```bash
# 1. a branch, never main — build-ipa.yml releases on every push to main
git checkout -b sync/upstream-$(date +%Y%m%d)

# 2. merge (not rebase)
git remote add upstream https://github.com/uzairansaruzi/hermex.git   # once
git fetch upstream master
git merge --no-commit --no-ff upstream/master

# 3. bookkeeping — §Bookkeeping above, 26 lines total
# 4. our files — confirm they are still present
# 5. tests — read both sides
# 6. app code, largest first (ChatView 26 → ChatViewModel 17 → ChatTranscriptView 16)
# 7. pbxproj — 10 blocks, keep both sides' registrations
git add -A && git commit

# 8. the gate, then push and open a PR (pr-ci.yml needs the PR, not just the branch)
python3 scripts/pipeline-precheck.py
git push -u origin sync/upstream-$(date +%Y%m%d)
gh pr create --draft --base main --head sync/upstream-$(date +%Y%m%d) \
  --title "sync: merge upstream/master" --body "Plan: docs/agents/upstream-sync-plan.md"

# 9. only after the suite is green: merge to main
gh pr ready && gh pr merge --merge
```

Verified in advance: `gh` is authenticated as `braintimebox`, push permission on the
repo is `true`, and `sync/*` branches can be created and deleted. Nothing in this
sequence needs access that is not already present.

Working on a branch matters for cost: `build-ipa.yml` triggers on `main` only and
publishes a release on push, and it has **no** `concurrency` block, so every push runs
the full macOS job to completion. `pr-ci.yml` has `cancel-in-progress: true`, so a
corrected push cancels the previous run instead of paying for both — that alone is the
difference between a workable and an unworkable reconciliation under the current quota.

**How to get CI feedback on a branch:**

```bash
git push -u origin sync/upstream-<date>
gh pr create --draft --base main --head sync/upstream-<date> \
  --title "sync: merge upstream/master" --body "Rehearsal plan: docs/agents/upstream-sync-plan.md"
```

`pr-ci.yml` triggers on `pull_request`, so the PR must exist — pushing a branch alone
runs nothing. Keep it a draft until the suite is green; drafts still run CI.

`main` is currently **not** branch-protected (`gh api .../branches/main/protection`
returns 404), so nothing technically prevents a direct push. Use a branch anyway: a
conflict resolution you have to inspect mid-way should not land on `main` by accident.
