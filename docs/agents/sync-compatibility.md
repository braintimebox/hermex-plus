# Sync compatibility — the rule every change is written under

A fork survives only while its deviations are visible. Hermex Plus is a fork of
`uzairansaruzi/hermex`, and every release begins by merging their work into ours.
That merge is safe when it can tell our code from theirs, and destructive when it
cannot.

This is not advice. It is the base logic this repository is developed under, and
gate 13 enforces the mechanical part of it on every push.

## What it cost to learn this

On 2026-09-12 the 1.6.0 merge silently dropped six lines from function bodies:

| Line | What it broke |
|---|---|
| `actions.pendingActionCoordinator = pendingActionCoordinator` | approval and clarification prompts read `nil` for the life of the view model — 11 tests |
| the `didSet` clearing `sendErrorIsFromStreamRecovery` | a later send error was wiped by an earlier recovery confirmation |
| `transcriptRevision &+= 1` in `applyReloadedMessages` | a reload that rewrote a row never re-scanned it |
| a trailing `errorMessage = nil` | swallowed the offline timeout message — 2 tests |
| two call-site arguments to `onScrollToLatestContent` | build error |

Nothing marked those lines as ours. A union of two trees took upstream's side of
the hunk, and no gate could see inside a body to notice. The build then failed
for a day, and twenty-four tests failed when it finally compiled.

The deeper cost was not the six lines. It was that the diagnosis had to start
from scratch, because the diff carried no memory of which side was ours.

## The rule

**Every change must survive the next sync.** There are exactly two ways to
satisfy that, and every change takes one of them.

### 1. Send it upstream, when upstream owns the defect

If the defect is in their code, the fix belongs in their repository. Sent as a
PR, it arrives at our next sync as *their* code — it stops being a local diff
entirely, and the conflict does not exist. This is the only outcome that costs
nothing forever.

A fork-local copy of a fix for upstream's own bug is a debt: it conflicts on
every sync until someone re-sends it.

### 2. Mark it, when it stays local

A local change inside a file upstream also owns must carry a marker in the code
itself:

```swift
// HERMEX-FORK: <the measured cause, not a restatement of the code>
```

The marker is not decoration. In a context-free merge it is the *only* thing that
says which side is ours, and it tells the next resolver what the block is for.
It also carries the intent to upstream it, which is what retires the marking
later.

Markers are required in files that exist in `upstream/master`. New files are
fork-owned and need no marker: nothing upstream can conflict with them, so **new
behaviour belongs in a new file, not inside an upstream one.** That single
preference removes most future conflicts.

## How the gate reads it

`scripts/check-sync-surface.py`, wired as gate 13:

- the baseline is `merge-base(main, upstream/master)` — **not** `upstream/master`.
  `main` is a fork of a *past* upstream, so comparing against their present HEAD
  makes their own rewrites look like our losses. This is the same correction gate
  12 needed, and it is why 25 of 29 "lost declarations" were never lost.
- every added hunk since that baseline, in a file that exists upstream, is
  checked for a marker inside it or in the three lines above it.
- the backlog that predates the gate is recorded in `sync-surface.json`, not
  blocked. A **new** unmarked hunk blocks. The gate was usable the day it landed
  instead of demanding a migration first.

```
python3 scripts/check-sync-surface.py            # gate
python3 scripts/check-sync-surface.py --report   # surface summary
python3 scripts/check-sync-surface.py --list     # the unmarked hunks
python3 scripts/check-sync-surface.py --record   # re-baseline after a sync
```

At the time of writing the surface is: **113 changed files — 51 fork-owned and
62 upstream-owned — holding 15 796 added lines in 311 hunks, all unmarked.** That
number is the honest size of the debt this rule exists to stop growing.

## Working with it

- Touching a file that is already on the backlog? Mark the hunks you touch. The
  backlog is paid down where work happens, never as a big-bang migration.
- Re-baselining after a sync is expected: the merged upstream code stops being
  our diff, and `--record` moves the baseline forward. Re-baselining to silence a
  marker you were asked to add is not.
- If a change cannot be marked because the file has no comment syntax the gate
  knows, add the suffix to `MARKER_SUFFIXES` in the same commit.
- Gate 12 protects our *symbols*; gate 13 protects our *lines*. A type can
  survive with its body emptied, and a body can lose six lines without losing a
  single declaration. Both gates are needed; neither replaces the other.

## Applying this to other projects

The rule is not specific to Hermex Plus. Any repository that merges an upstream
needs the same three things:

1. A stated preference for upstream-first fixes over local copies.
2. A marker convention, so local deviations are identifiable in a diff.
3. A deterministic gate measuring the surface against `merge-base`, not against
   upstream's HEAD.

See `fork-upstream-sync` → `references/sync-compatibility-rule.md` for the portable
version of this playbook.
