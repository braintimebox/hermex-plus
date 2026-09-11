# Upstream sync — rehearsal results and resolution plan

Produced by merging `upstream/master` into a throwaway clone (`/tmp/upstream-rehearsal`)
on 2026-09-11, **without touching the working repository**. The point is that the
conflict set is now known in advance: it is fixed and repeatable, so it is resolved
once, deliberately, rather than discovered while panicking.

Regenerate the rehearsal at any time:

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
| Commits to absorb | **107** |
| Upstream files added | **298** (mostly `Features/Bots/*`) |
| Conflicting files | **34** |
| Conflict blocks | **141** |

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

- `docs/agents/domain.md` — **deleted upstream, modified by us** (`UD`). Upstream dropped
  the directory; we added the testing.md pointer to it. Decide: keep the file, or move the
  pointer into a file upstream still owns.
- `HermesMobile/Features/Chat/ClarificationRequestOverlay.swift` — **added by us, deleted
  upstream** (upstream restructured overlays). Keep ours unless our feature moved.

---

## Resolution rules per class

**Bookkeeping — take ours.** `CHANGELOG.md`, `README.md`, `AGENTS.md`, `.gitignore`.
Two-way divergence with no shared meaning; upstream's version has no knowledge of our
release history, and our `CHANGELOG` is the source `release-check.py` reads.

**Our files — take ours, never drop.** Upstream does not know these exist, so a merge
that "cleans them up" silently deletes the release pipeline:
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

**`project.pbxproj` — do not hand-resolve 10 blocks.** There is no XcodeGen or other
project generator in this repo: the pbxproj is committed and edited directly (see the
`ios-project-workflow` skill for the CLI approach). Resolving 10 conflict blocks by hand
in a 2000+ line plist is where mistakes get made.

Practical approach: for each block, keep the side that preserves **both** sides' file
registrations — the file is a list of four parallel structures (PBXBuildFile,
PBXFileReference, group children, build phase), so a block that drops either side's
entries produces a target that builds locally and fails in CI. Upstream added 298 files,
many under `Features/Bots/`; every one needs all four entries.

Verify with `scripts/pipeline-precheck.py` gate 3 afterwards — it reports any staged
`.swift` whose name does not appear at least twice in the file, which catches a dropped
registration but not a duplicated one. Also confirm the build phase lists are not
duplicated.

---

## Known traps

1. **`permissions: contents: write`** — the `build` job in `build-ipa.yml` needs it for
   `Create Release`; without it the run fails with 403 *after* tests and packaging pass.
   Already fixed in our tree. Confirm it survives the merge, since that file conflicts.
2. **`SessionTimeouts`** in `APIClient.swift` and the guard in `CacheStore.cacheMessages`
   are recent fixes. Upstream may have touched the same regions.
3. **`docs/agents/domain.md`** — our only edit is a pointer to `testing.md`. Cheapest
   resolution if upstream deleted the file: drop the file, move the pointer.
4. **CI is the only compiler.** There is no Swift toolchain on Linux. Resolve everything,
   then let CI tell you what does not typecheck — budget several runs.

---

## Cost

Each push runs `guard → test → build` on a macOS runner: ~9 min wall-clock, **≈90 billed
minutes**. Resolving 141 blocks will need several runs. The GitHub Actions quota is the
binding constraint, not the work.

**Batch the work on a branch and push sparingly.** Do not resolve one file per push.

---

## Recommended sequence

```
1. git checkout -b sync/upstream-<date>          (do not work on main)
2. merge upstream/master
3. bookkeeping + our files        (fast, mechanical)
4. tests                          (read both sides)
5. app code, biggest files first  (the real work)
6. regenerate pbxproj
7. run scripts/pipeline-precheck.py
8. push the branch, open a PR      (pr-ci.yml runs the suite)
9. only after green: merge to main
```

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
