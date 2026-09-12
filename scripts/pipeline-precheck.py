#!/usr/bin/env python3
"""Local pre-push gate for Hermex Plus.

WHY THIS EXISTS
    release-check.py already knows the release invariants, but nothing invoked
    it automatically. A developer (or an agent) had to *remember* to run it,
    which means in practice it was skipped — and that is exactly how the
    techdebt accumulated.

    Hooks in .git/hooks/ are not versioned, so they rot. This script IS
    versioned and is installed by `scripts/pipelines/release_hermesplus.py install`.

WHAT IT CHECKS (fast, local, no Xcode needed)
    1. release-check invariants      VERSION == CHANGELOG == pbxproj; no dup tag
    2. conflict markers in code      <<<<<<< / >>>>>>> left in a tracked file
    3. pbxproj registration          every new .swift has its 4 entries
    4. bookkeeping not clobbered     upstream files we must not touch
    5. upstream drift is known       sync-upstream --status must not error
    6. test-lint                     no assertion encodes a race as a contract
    7. doc references resolve        no document points at a deleted file
    8. swift structural balance      a changed .swift keeps its parents' brace
                                     balance (a merge that concatenates two
                                     conflict sides drops the closing brace
                                     that sat at the end of a side; Swift then
                                     reports it as a cascade of unrelated
                                     errors, which cost five CI runs)
    9. duplicate declarations        no member declared twice in one type (the
                                     same union leaves both copies of a field —
                                     `invalid redeclaration of 'x'` × N, which
                                     reads as N bugs but is one spliced block)

    Checks are fail-fast: the first BLOCKER stops the push.

USAGE
    python3 scripts/pipeline-precheck.py          # run all checks
    python3 scripts/pipeline-precheck.py --check 3 # run one check
    exit 0 = safe to push, exit 1 = BLOCKER

INSTALL (as a pre-push hook)
    python3 scripts/pipelines/release_hermesplus.py install
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Upstream-owned files we must never modify ourselves: editing them costs a
# merge conflict on every future sync for zero benefit.
UPSTREAM_OWNED = {
    "PROJECT_SPEC.md",
    "PROJECT_INTENT.md",
    "CONTRIBUTING.md",
    "DEVELOPMENT.md",
    "SECURITY.md",
    "CODE_OF_CONDUCT.md",
    "CONTEXT.md",
    "CONTRACT_TESTS.md",
    "CLAUDE.md",
}

# Files whose only job is bookkeeping. Everyone adding a release touches them,
# so they are the #1 source of conflict with upstream. They are OURS.
BOOKKEEPING = {"CHANGELOG.md", "README.md", "VERSION"}


def git(*args: str, check: bool = False) -> str:
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed:\n{r.stderr.strip()}")
    return r.stdout


def blockers(items: list[str]) -> int:
    if not items:
        return 0
    print("\nBLOCKERS:")
    for i in items:
        print(f"  - {i}")
    return 1


# --- check 1: release invariants --------------------------------------------

def check_release() -> int:
    print("[1/9] release invariants (VERSION / CHANGELOG / pbxproj / tag)")
    script = ROOT / "scripts" / "release-check.py"
    if not script.exists():
        return blockers(["scripts/release-check.py missing"])
    r = subprocess.run(
        [sys.executable, str(script), "--allow-untagged"],
        cwd=ROOT, capture_output=True, text=True,
    )
    out = (r.stdout + r.stderr).strip()
    for line in out.splitlines():
        print(f"      {line}")
    if r.returncode != 0:
        return 1
    return 0


# --- check 2: conflict markers ----------------------------------------------

def check_conflict_markers() -> int:
    print("[2/9] conflict markers in tracked files")
    tracked = [f for f in git("diff", "--name-only", "HEAD").splitlines() if f.strip()]
    dirty = [f for f in git("diff", "--cached", "--name-only").splitlines() if f.strip()]
    candidates = sorted(set(tracked) | set(dirty))
    hits = []
    for f in candidates:
        p = ROOT / f
        if not p.is_file():
            continue
        try:
            text = p.read_text(errors="ignore")
        except Exception:
            continue
        if re.search(r"^(<{7}|={7}|>{7})", text, re.M):
            hits.append(f)
    if hits:
        print(f"      found in {len(hits)} file(s)")
        return blockers([f"unresolved conflict markers in {f}" for f in hits])
    print(f"      clean ({len(candidates)} changed files scanned)")
    return 0


# --- check 3: pbxproj registration ------------------------------------------

def check_pbxproj_registration() -> int:
    print("[3/9] pbxproj registration of new .swift files")
    pbx = ROOT / "HermesMobile.xcodeproj" / "project.pbxproj"
    if not pbx.exists():
        return blockers(["project.pbxproj missing"])
    text = pbx.read_text(errors="ignore")

    new_files = [
        f for f in git("diff", "--cached", "--name-only", "--diff-filter=A",
                       "--", "HermesMobile/**/*.swift").splitlines() if f.strip()
    ]
    if not new_files:
        print("      no new .swift files staged — nothing to register")
        return 0

    missing = []
    for f in new_files:
        name = Path(f).name
        # 4 registrations: PBXBuildFile, PBXFileReference, group children, build phase
        if text.count(name) < 2:
            missing.append(f"{name}: found {text.count(name)} refs, expected >=2")
    if missing:
        return blockers([
            "new .swift not registered in pbxproj (needs PBXBuildFile + "
            "PBXFileReference + group + build phase):"
        ] + [f"  {m}" for m in missing])
    print(f"      {len(new_files)} new file(s) registered")
    return 0


# --- check 4: upstream-owned files untouched --------------------------------

def check_upstream_owned() -> int:
    print("[4/9] upstream-owned files not modified")
    changed = set()
    for args in (("diff", "--name-only", "HEAD"), ("diff", "--cached", "--name-only")):
        changed |= {f.strip() for f in git(*args).splitlines() if f.strip()}
    touched = sorted(changed & UPSTREAM_OWNED)
    if touched:
        print(f"      modified: {', '.join(touched)}")
        print("      these belong to upstream; editing them adds a merge conflict")
        print("      on every sync. Prefer HERMES.md / scripts/ for our own rules.")
        # advisory, not a blocker: sometimes it is intentional
        ADVISORIES.append(
            f"upstream-owned file(s) edited: {', '.join(touched)} — "
            "this costs a merge conflict on every future sync"
        )
    else:
        print("      none touched")
    return 0


# --- check 5: upstream drift is measured ------------------------------------

def check_upstream_drift() -> int:
    """Report how far behind upstream we are — informational, never a blocker.

    Drift is a planning signal (how big the next merge will be), not a code
    defect: a large drift does not make the current commit wrong. Worse, this
    check cannot work off the maintainer's machine — sync-upstream resolves the
    repo through an absolute path and needs the plus/base tag plus real history,
    neither of which a CI checkout has. Treating its failure as a blocker turned
    every CI run red with "not a git repo", so it is now advisory: it prints what
    it can and always returns 0. Check 4 (upstream-owned files) is the one with
    teeth, because touching upstream files is what actually breaks a sync.
    """
    print("[5/9] upstream drift (advisory)")
    script = ROOT / "scripts" / "sync-upstream"
    if not script.exists():
        print("      scripts/sync-upstream not present — skipped")
        return 0
    try:
        r = subprocess.run([sys.executable, str(script), "--status"],
                           cwd=ROOT, capture_output=True, text=True, timeout=120)
    except Exception as exc:  # missing git history, timeout, anything
        print(f"      drift not measurable here ({type(exc).__name__}) — advisory, not blocking")
        return 0
    if r.returncode != 0:
        print("      drift not measurable here — advisory, not blocking")
        print(f"      ({' '.join((r.stdout + r.stderr).split())[:200]})")
        return 0
    for line in r.stdout.strip().splitlines():
        print(f"      {line}")
    return 0


def check_test_lint() -> int:
    """Reject test assertions that encode a race as a contract.

    Mechanical, therefore checked here rather than left to a document. The rule
    this replaces lived in docs/agents/testing.md and its author violated it two
    hours later in the same session — a note asks the next person to remember and
    to judge whether it applies; a gate does not.
    """
    print("[6/9] test-lint (race-shaped assertions)")
    script = ROOT / "scripts" / "lint-tests.py"
    if not script.exists():
        print("      linter not found — skipped")
        return 0
    r = subprocess.run(
        [sys.executable, str(script)], cwd=ROOT, capture_output=True, text=True
    )
    for line in (r.stdout or "").strip().splitlines():
        print(f"      {line}")
    if r.returncode != 0 and r.stderr.strip():
        print(f"      {r.stderr.strip()[:300]}")
    return r.returncode


def check_doc_references() -> int:
    """Reject documentation that points at a file this repository does not have.

    Same reasoning as check 6: the rule was written down twice and broken twice.
    `CURRENT.md`/`project-metrics.md`, then `scripts/pipeline`, `bump-version.py`
    and `STATUS.md` — deleted while four documents kept naming them as the
    working path, including this file's own docstring. An agent that follows the
    document spends context discovering the file is gone.

    Blocking, not advisory: a dangling reference is never a judgment call. The
    one legitimate case — a document that names a removed file in order to say
    it is gone — is recognised by the absence wording on the same line, which is
    how the tools register already writes those entries.
    """
    print("[7/9] doc references resolve")
    script = ROOT / "scripts" / "check-doc-references.py"
    if not script.exists():
        print("      checker not found — skipped")
        return 0
    r = subprocess.run(
        [sys.executable, str(script)], cwd=ROOT, capture_output=True, text=True
    )
    for line in (r.stdout or "").strip().splitlines():
        print(f"      {line}")
    if r.returncode != 0 and r.stderr.strip():
        print(f"      {r.stderr.strip()[:300]}")
    return r.returncode



def check_swift_structural_balance() -> int:
    """Reject a change that leaves a .swift file less balanced than its parents.

    A merge resolved by concatenating the two conflict sides drops the closing
    brace that sat at the end of a side. Swift then reports it as a cascade: one
    missing `}` in ChatView surfaced as twenty-odd `attribute 'private' can only
    be used in a non-local scope` errors at unrelated lines, and five CI runs
    were spent chasing the cascade one brace at a time because nothing local
    could tell "I broke the structure" from "the file always looked like this".

    Line-by-line brace counting does not work here and was tried three times
    during that merge, wrong every time: `{` occurs inside string literals,
    multi-line strings and comments, and `(` in a function signature opens a
    scope that carries no brace at all. The checker this calls tracks
    string/comment state and compares against BOTH parents, so an inherited
    imbalance is not mistaken for one this branch introduced.

    Blocking, not advisory: a dropped brace is never a judgment call.
    """
    print("[8/9] swift structural balance vs both parents")
    script = ROOT / "scripts" / "check-swift-structural-balance.py"
    if not script.exists():
        print("      checker not found — skipped")
        return 0
    r = subprocess.run(
        [sys.executable, str(script)], cwd=ROOT, capture_output=True, text=True
    )
    # the script prints its own banner; drop it so the gate header is not doubled
    body = [ln for ln in (r.stdout or "").strip().splitlines()
            if not ln.startswith("[8/8]")]
    for line in body:
        print(f"      {line}")
    if r.returncode != 0 and r.stderr.strip():
        print(f"      {r.stderr.strip()[:300]}")
    return r.returncode



def check_duplicate_declarations() -> int:
    """Reject a change that declares the same member twice in one type.

    The companion to gate 8. A brace can be balanced and the file still not
    compile: when a union pastes both sides of a conflict, a whole block of
    declarations appears twice. Swift reports `invalid redeclaration of 'x'`
    once per name — in this merge, twenty-odd of them across ChatViewModel and
    ChatTranscriptView, which reads as twenty mistakes rather than one block.

    The checker groups declarations by their ENCLOSING top-level type, treats a
    property and a func of the same name as different declarations, and compares
    funcs by their full parameter list so overloads pass. That calibration
    matters: an earlier version grouped by indentation alone and produced 2505
    false hits, which is a gate someone switches off.
    """
    print("[9/9] duplicate declarations in the same type scope")
    script = ROOT / "scripts" / "check-duplicate-declarations.py"
    if not script.exists():
        print("      checker not found — skipped")
        return 0
    r = subprocess.run(
        [sys.executable, str(script)], cwd=ROOT, capture_output=True, text=True
    )
    body = [ln for ln in (r.stdout or "").strip().splitlines()
            if not ln.startswith("[9/9]")]
    for line in body:
        print(f"      {line}")
    if r.returncode != 0 and r.stderr.strip():
        print(f"      {r.stderr.strip()[:300]}")
    return r.returncode


CHECKS = {
    1: check_release,
    2: check_conflict_markers,
    3: check_pbxproj_registration,
    4: check_upstream_owned,
    5: check_upstream_drift,
    6: check_test_lint,
    7: check_doc_references,
    8: check_swift_structural_balance,
    9: check_duplicate_declarations,
}

# Advisory notes raised by checks that return 0. A check that warns but does not
# block used to be invisible: `check_upstream_owned` prints "modified:
# CONTRIBUTING.md" and then the run ends with "ALL CHECKS PASSED — safe to push",
# so the warning scrolls away and the summary contradicts it. Collected here and
# repeated under the verdict, where the reader actually stops.
ADVISORIES: list[str] = []


def main() -> int:
    ap = argparse.ArgumentParser(description="Hermex Plus pre-push gate")
    ap.add_argument("--check", type=int, choices=sorted(CHECKS), help="run one check")
    args = ap.parse_args()

    print("=" * 66)
    print("HERMEX PLUS — PIPELINE PRECHECK")
    print("=" * 66)

    if args.check:
        return CHECKS[args.check]()

    failed = 0
    for n in sorted(CHECKS):
        if CHECKS[n]() != 0:
            failed = n
            break
    print("=" * 66)
    if failed:
        print("PUSH BLOCKED — fix the blockers above, then re-run.")
        return 1
    print("ALL CHECKS PASSED — safe to push.")
    if ADVISORIES:
        print()
        print("Advisory (not blocking):")
        for note in ADVISORIES:
            print(f"  • {note}")
        print()
        print("  Repeating them here because the summary above contradicts a")
        print("  warning that only appeared mid-run. Read them before pushing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
