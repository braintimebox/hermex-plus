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
    """Gate 3 — every Swift file is registered, and no pbxproj id is reused.

    Two failures this now catches, both of which produced a green earlier today:

      * a file that exists in the tree with no entry in the project at all — the
        1.6.0 merge dropped the four lines registering our
        `ClarificationRequestOverlay.swift`, so it silently stopped compiling and
        `ClarificationRequestCard` was reported "cannot find in scope"
      * one 24-hex id used for two different files. The merge left upstream's
        `ClarificationRequestCard.swift` holding the id our overlay file also
        used; Xcode resolves an id to one path, so the other disappears. A
        `grep -c` said "4 refs, registered" for both — which is why counting
        references is not the check.
    """
    print("[3/13] pbxproj: every .swift registered, every id unique")
    pbx = ROOT / "HermesMobile.xcodeproj" / "project.pbxproj"
    if not pbx.exists():
        return blockers(["project.pbxproj missing"])
    text = pbx.read_text(errors="ignore")

    problems: list[str] = []

    # (a) every Swift file in the tree appears in the project
    tracked = git("ls-tree", "-r", "--name-only", "HEAD", "--", "HermesMobile/")
    for f in tracked.splitlines():
        if not f.strip().endswith(".swift"):
            continue
        if Path(f).name not in text:
            problems.append(f"{f} is in the tree but not in project.pbxproj")

    # (b) no id defined twice
    seen: dict[str, str] = {}
    for line in text.splitlines():
        m = re.match(r"^\s*([0-9A-F]{24})\s+/\*\s*(.+?)\s*\*/\s*=\s*\{", line)
        if not m:
            continue
        ident, label = m.group(1), m.group(2)
        if ident in seen:
            problems.append(f"id {ident} used twice: '{seen[ident]}' and '{label}'")
        else:
            seen[ident] = label

    # (c) each fileRef sits in a group whose path actually leads to the file.
    # Registering a file in the wrong group is not a build error Xcode reports
    # clearly — it reports "did you forget to declare this file as an output of
    # a script phase", for a file that exists. `QuoteReplyBanner.swift` landed in
    # the Models group while living in Features/Chat.
    problems.extend(_group_path_mismatches(text, tracked.splitlines()))

    if problems:
        return blockers(["project.pbxproj is inconsistent:"] + [f"  {p}" for p in problems[:15]])
    print(f"      {len(seen)} ids, all unique; every tracked .swift registered "
          f"and in a group that resolves to its directory")
    return 0


def _group_path_mismatches(text: str, tracked: list[str]) -> list[str]:
    """fileRefs whose PBXGroup chain does not resolve to the file's own folder."""
    groups: dict[str, tuple[list[str], str]] = {}
    for m in re.finditer(
        r"([0-9A-F]{24})\s*/\*[^*]*\*/\s*=\s*\{\s*isa = PBXGroup;"
        r"(.*?)\};",
        text, re.S,
    ):
        body = m.group(2)
        children: list[str] = []
        cm = re.search(r"children = \((.*?)\);", body, re.S)
        if cm:
            children = re.findall(r"([0-9A-F]{24})", cm.group(1))
        pm = re.search(r"\bpath = \"?([^;\"]+)\"?;", body)
        groups[m.group(1)] = (children, pm.group(1) if pm else "")

    ref_path: dict[str, str] = {}
    for m in re.finditer(
        r"([0-9A-F]{24})\s*/\*\s*(\S+?\.swift)\s*\*/\s*=\s*\{\s*isa = PBXFileReference;"
        r'.*?path = "?([^;"]+)"?;',
        text,
    ):
        ref_path[m.group(1)] = m.group(3)

    # walk from each group down, accumulating the path prefix
    by_name: dict[str, list[str]] = {}
    for f in tracked:
        if f.endswith(".swift"):
            by_name.setdefault(Path(f).name, []).append(f)

    problems: list[str] = []

    def walk(gid: str, prefix: str, depth: int = 0) -> None:
        if depth > 8:
            return
        children, own = groups.get(gid, ([], ""))
        here = f"{prefix}/{own}".strip("/") if own else prefix
        for child in children:
            if child in groups:
                walk(child, here, depth + 1)
            elif child in ref_path:
                name = ref_path[child]
                real = by_name.get(name)
                if not real:
                    continue
                expected_dir = str(Path(real[0]).parent)
                resolved = f"{here}/{name}".strip("/")
                if resolved != real[0] and expected_dir.split("/")[-1] not in here.split("/")[-1:]:
                    problems.append(
                        f"{name} is registered under '{here or '<root>'}' "
                        f"but lives in '{expected_dir}'"
                    )

    root_ids = [g for g in groups if not any(g in c for c, _ in groups.values())]
    for gid in root_ids:
        walk(gid, "")
    return sorted(set(problems))


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
    print("[8/13] swift structural balance vs both parents")
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
    print("[9/13] duplicate declarations in the same type scope")
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


def check_initializer_completeness() -> int:
    """Gate 10 — no stored property left unset by an init that sets others.

    Gates 8 and 9 catch a union that pasted both sides of a declaration. This
    catches the mirror-image defect: upstream ADDS a stored property and our
    own init keeps its old assignment list, so Swift reports

        return from initializer without initializing all stored properties

    `SessionSummary.matchPreview` arrived exactly that way — upstream added the
    property and its decoder, while `init(sessionId:title:)` (which upstream
    does not have) still listed 32 of 34 fields. One line, one full CI round.
    """
    print("[10/13] initializer completeness (all stored properties set)")
    script = ROOT / "scripts" / "check-initializer-completeness.py"
    if not script.exists():
        print("      checker not found — skipped")
        return 0
    r = subprocess.run(
        [sys.executable, str(script)], cwd=ROOT, capture_output=True, text=True
    )
    body = [ln for ln in (r.stdout or "").strip().splitlines()
            if not ln.startswith("[10/13]")]
    for line in body:
        print(f"      {line}")
    if r.returncode != 0 and r.stderr.strip():
        print(f"      {r.stderr.strip()[:300]}")
    return r.returncode


def check_duplicate_call_arguments() -> int:
    """Gate 11 — one argument label passed twice into the same call.

    The union keeps both sides of an edited call site, which parses and then
    fails in the type checker at the OUTERMOST expression:

        error: the compiler is unable to type-check this expression in
               reasonable time; try breaking up the expression

    reported at the enclosing view, hundreds of lines from the duplicate.
    `SettingsView`'s second `title:`, `ChatView`'s second
    `onSelectReasoningEffort:` and second `onDismissKeyboard:` all came in
    that way in the 1.6.0 merge.
    """
    print("[11/13] duplicate call arguments (same label twice in one call)")
    script = ROOT / "scripts" / "check-duplicate-call-arguments.py"
    if not script.exists():
        print("      checker not found — skipped")
        return 0
    r = subprocess.run(
        [sys.executable, str(script)], cwd=ROOT, capture_output=True, text=True
    )
    body = [ln for ln in (r.stdout or "").strip().splitlines()
            if not ln.startswith("[11/13]")]
    for line in body:
        print(f"      {line}")
    if r.returncode != 0 and r.stderr.strip():
        print(f"      {r.stderr.strip()[:300]}")
    return r.returncode


def check_fork_preserved() -> int:
    """Gate 12 — our own declarations are still in the tree.

    Gates 8 and 9 catch a union that broke a file or duplicated a member. This
    catches a union that quietly took upstream's side and dropped ours: on
    2026-09-12 the 1.6.0 merge removed `ToolCallCardView.swift` and
    `InsightsRows.swift` outright and dropped 32 of our declarations inside
    files that survived. No gate noticed.

    `main` is the definition of ours — a type declared there and nowhere in
    `upstream/master`. The 32 losses that predate this gate are baselined in
    `docs/agents/fork-manifest.json` (`pending_triage`) so it is usable today;
    a NEW disappearance blocks.
    """
    print("[12/13] fork-owned symbols still present")
    script = ROOT / "scripts" / "check-fork-preserved.py"
    if not script.exists():
        print("      checker not found — skipped")
        return 0
    r = subprocess.run(
        [sys.executable, str(script)], cwd=ROOT, capture_output=True, text=True
    )
    body = [ln for ln in (r.stdout or "").strip().splitlines()
            if not ln.startswith("[12/13]")]
    for line in body:
        print(f"      {line}")
    if r.returncode != 0 and r.stderr.strip():
        print(f"      {r.stderr.strip()[:300]}")
    return r.returncode


def check_sync_surface() -> int:
    """Gate 13 — every local change is identifiable, so the next sync keeps it.

    Gate 12 protects our *symbols*; it cannot see inside a function, so it never
    noticed the six lines the 1.6.0 merge dropped from bodies — a coordinator
    binding, a `didSet`, a revision bump, an error clear, two call arguments.
    Twenty-four tests paid for that.

    This gate protects our *lines*. Any added hunk inside a file upstream also
    owns must carry a `HERMEX-FORK:` marker, which is the only thing in a diff
    that tells a context-free merge resolver which side is ours. When upstream
    itself owns the defect, the better answer is to send the change upstream:
    it then arrives as their code and stops being a local diff at all.

    The backlog that predates the gate is recorded in
    `docs/agents/sync-surface.json`, not blocked, so the gate is usable on the
    day it lands. A NEW unmarked hunk blocks.
    """
    print("[13/13] local changes are identifiable (sync surface)")
    script = ROOT / "scripts" / "check-sync-surface.py"
    if not script.exists():
        print("      checker not found — skipped")
        return 0
    r = subprocess.run(
        [sys.executable, str(script)], cwd=ROOT, capture_output=True, text=True
    )
    body = [ln for ln in (r.stdout or "").strip().splitlines()
            if not ln.startswith("[13/13]")]
    for line in body:
        print(f"      {line}")
    if r.returncode != 0 and r.stderr.strip():
        print(f"      {r.stderr.strip()[:300]}")
    return r.returncode


def check_fork_identity() -> int:
    """Gate 14 — the fork signs under its own bundle identifier.

    `Config/Shared.xcconfig` is upstream-owned and upstream signs as
    `com.uzairansar.hermesmobile`. Sharing that string makes Hermex Plus and
    Hermex the same app to iOS: the two cannot be installed side by side, and
    installing beside an App Store Hermex is refused outright — which is how
    four released builds went uninstalled while the phone stayed on an older
    version.

    The value is one line in a file nobody reads, so a merge that takes
    upstream's side restores the collision silently. Pin it here rather than
    trust a comment.
    """
    print("[14/14] the fork signs under its own bundle identifier")
    expected = "com.braintimebox.hermexplus"
    path = ROOT / "Config" / "Shared.xcconfig"
    if not path.exists():
        print("      Config/Shared.xcconfig is missing")
        return 1

    text = path.read_text(encoding="utf-8")
    bundle = re.search(r"^APP_BUNDLE_IDENTIFIER\s*=\s*([^\n$]+)", text, re.M)
    group = re.search(r"^APP_GROUP_IDENTIFIER\s*=\s*([^\n$]+)", text, re.M)

    problems: list[str] = []
    if not bundle:
        problems.append("APP_BUNDLE_IDENTIFIER is not set")
    elif bundle.group(1).strip() != expected:
        problems.append(
            f"APP_BUNDLE_IDENTIFIER is {bundle.group(1).strip()!r}, expected {expected!r}"
        )
    if not group:
        problems.append("APP_GROUP_IDENTIFIER is not set")
    elif group.group(1).strip() != f"group.{expected}":
        problems.append(
            f"APP_GROUP_IDENTIFIER is {group.group(1).strip()!r}, "
            f"expected {'group.' + expected!r}"
        )

    if problems:
        for problem in problems:
            print(f"      {problem}")
        print("      The fork's identity regressed — a merge most likely took")
        print("      upstream's side of Config/Shared.xcconfig.")
        return 1

    print(f"      ok  bundle id {expected}, group group.{expected}")
    return 0


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
    10: check_initializer_completeness,
    11: check_duplicate_call_arguments,
    12: check_fork_preserved,
    13: check_sync_surface,
    14: check_fork_identity,
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
