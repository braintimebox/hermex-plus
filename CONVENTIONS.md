# Hermex Plus — project conventions

One page. Read this before adding a script, a test double, or a workflow step.
Everything here exists because the opposite caused a real failure — each rule
names the failure it prevents, so you can tell whether it still applies.

---

## 1. The repository is the single source of truth

**Rule:** anything the pipeline depends on lives in this repository, in git.

**Why:** a release script lived in `~/.hermes/scripts/` — outside git, invisible
to `git log`, and unknown to the next agent, who then wrote a second release
script. Two implementations of one lifecycle drifted apart, and a third of the
release (the README update) silently only ever ran in the orphaned copy.

**In practice:**
- Scripts → `scripts/` (or `scripts/pipelines/` for release machinery)
- Git hooks → `.githooks/` plus `git config core.hooksPath .githooks`
- Never `~/.hermes/scripts/` for anything this project depends on

---

## 2. Tools must be declared, or they do not exist

**Rule:** a new script or command is not finished until it is listed in
`HERMES.md` → "Инструменты — реестр".

**Why:** an undeclared tool is invisible to every agent that follows. The release
script existed, worked, and was documented nowhere — so it was reimplemented
from scratch. The register is the fix for that exact failure mode.

---

## 3. Tests are a gate, not a report

**Rule:** `.github/workflows/build-ipa.yml` runs `guard → test → build`. The IPA
is only packaged when the suite passes. Never add a step that packages before
the tests.

**Why:** the workflow used to package and ship whatever landed on `main`, while
the 92 XCTest files ran nowhere — `pr-ci.yml` was `pull_request`-only and this
fork pushes straight to `main`. The consequence was not theoretical: the suite
had not compiled since the initial commit, and a link-preview regex that
truncated every URL to `https://e` had been shipping for three weeks.

**Rule:** the CI log must state *why* a test failed, not just that it did. The
`Report test failures` step prints each failing case with its assertion text and
source location. Do not remove it — without it a red run is undiagnosable from
the log alone.

---

## 4. Test isolation: no process-global state survives a test

**Rule:** any `static var` cache or throttle that outlives a single test must be
reset in `setUp` (see `CacheStore.resetMaintenanceThrottleForTesting` and
`ChatComposerConfigLoader.resetMemoryCacheForTesting`, both called from
`APIClientTestCase.setUp`). Any helper that mutates a process-global cache needs
a `…ForTesting()` reset.

**Why:** `ChatComposerConfigLoader.memoryCache` is static with a 24-hour TTL and
no keying — correct for the app, where it must survive background/foreground, but
it also survived *between tests*. The first test to load a configuration
populated it, and every later test then asserted against state it never set up.
Four failures, all of which looked like logic bugs.

**Rule:** long-lived caches get a `…ForTesting()` reset in the same commit that
introduces them.

---

## 5. Test doubles conform completely, and a compile error is the signal

**Rule:** a test spy implements the whole protocol. When a protocol gains a
member, the spy's build breaks — that is the intended alarm, not an obstacle.
Fix the spy; do not delete the conformance.

**Why:** `CoordinatorDelegateSpy` had been missing `streamCoordinatorApplyDone`
since the initial commit. Because XCTest cannot build a target whose test file
does not satisfy a protocol, the *entire* 92-file suite failed to compile and
therefore reported nothing at all.

**Rule:** status-only delegate methods are recorded (a counter, a payload array),
not reimplemented. The spy asserts *that* the coordinator forwarded the event;
rendering logic belongs to the ViewModel's own tests.

---

## 6. Assert what the code promises, and name it that way

**Rule:** the assertion must test what the test's name says. `renderID` is the
position-derived scroll/compression target; `.id` is the stable SwiftUI identity
and must never contain `"transcript:"`.

**Why:** a test named `…KeepRenderIDStable…` asserted on `.id`, and another
asserted `.id == "transcript:1"` while a third in the same file asserted `.id`
must *never* contain `"transcript:"`. Two of them encoded the pre-v3.2.0
positional contract, so they contradicted both the code and their neighbours.

**Rule:** when a contract changes deliberately, update the test in the same
commit and write the reasoning inline. Silently deleting an inconvenient
assertion is how a real bug gets buried — check first whether the assertion is
describing a regression rather than a stale contract.

---

## 7. Async work must be awaited, not assumed

**Rule:** if a method starts a detached `Task`, the test waits for the observable
result (`waitUntil { … }`); it does not assert on the next line.

**Why:** `prepareInitialMessageLoad` paints cached messages from a detached
MainActor Task. Two tests asserted immediately and read an empty array, which
reads as "cache rendering is broken" but was the assertion running too early.

---

## 8. Version numbers move together

**Rule:** `scripts/pipelines/release_hermesplus.py release` writes `VERSION`,
`CHANGELOG.md`, `MARKETING_VERSION`, and a unique `CURRENT_PROJECT_VERSION`
(`YYYYMMDDHHMM`). Three gates in `pipeline-precheck.py` verify they agree.

**Why:** `CURRENT_PROJECT_VERSION` had been pinned at `1` since the initial
commit while `MARKETING_VERSION` climbed to 3.6.1. iOS compares the build number
when installing over an existing app, and a build number that never advances can
be rejected as the same build.

**Rule:** never hand-edit one of these files. Run the release command.

---

## 9. Paths resolve from the file, never from `~`

**Rule:** a script locates the repository via `Path(__file__).resolve().parents[N]`,
not `Path.home() / "Projects" / …`.

**Why:** `sync-upstream` hardcoded `~/Projects/hermex-plus`, which broke the
moment the repo moved and made the drift gate fail on every CI run with
"not a git repo".

---

## 10. Stage what a release is allowed to touch

**Rule:** the release commits an explicit list of paths. `git add -A` is banned
in pipeline code.

**Why:** `git add -A` staged every untracked file in the tree, which is how an
unrelated file ended up inside a release commit.

---

## 11. A release script is never run to see what it does

**Rule:** test release machinery against a copy of the repository, or by driving
its functions directly. Never by invoking it with no arguments.

**Why:** invoking the release script to "check it works" performed a real
release: it bumped the version, committed, and pushed to `main`. The script now
prints help when called with no arguments, but the lesson generalises — a tool
whose default action is irreversible must be exercised on a copy.

---

## 12. Report in four parts

After each slice, say: (1) files changed, (2) command run, (3) result,
(4) next step. For anything UI-facing, add a short manual test plan.

**Why:** the maintainer reviews from a phone. A change without the command that
produced it cannot be verified later.

---

## Where things live

| Thing | Path |
|---|---|
| Release pipeline | `scripts/pipelines/release_hermesplus.py` |
| Gates (5) | `scripts/pipeline-precheck.py` |
| Git hook | `.githooks/pre-push` (enable: `… release_hermesplus.py install`) |
| Status snapshot | `docs/project-snapshot.md` (generated from git) |
| Open tracks | `docs/hermesplus-status.yaml` |
| Agent rules | `HERMES.md` (overrides `AGENTS.md`) |
| Build + test + release | `.github/workflows/build-ipa.yml` |
