#!/usr/bin/env python3
"""Set up a rehearsal clone for an upstream sync, and report what it will cost.

Creates a throwaway clone, merges `upstream/master` into it without committing, and
prints the conflict set classified by how it should be resolved. The working repository
is never touched — this exists so the conflict set is known before you start resolving,
instead of being discovered while resolving.

Usage:
    python3 scripts/upstream-rehearse.py            # create/refresh and report
    python3 scripts/upstream-rehearse.py --clean    # remove the rehearsal clone
    python3 scripts/upstream-rehearse.py --dir /tmp/x

Exit codes: 0 = rehearsal ready, 1 = merge produced no conflicts (upstream is already
merged), 2 = the rehearsal could not be set up.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIR = Path("/tmp/upstream-rehearsal")
UPSTREAM_URL = "https://github.com/uzairansaruzi/hermex.git"

# Our files that upstream does not know about. A merge that "cleans them up" silently
# removes the release pipeline, so they are called out separately from the conflict set.
OURS = (
    "HERMES.md",
    "CONVENTIONS.md",
    ".githooks/pre-push",
    ".github/workflows/build-ipa.yml",
    "docs/agents/testing.md",
    "docs/agents/upstream-sync-plan.md",
    "scripts/lint-tests.py",
    "scripts/pipeline-precheck.py",
    "scripts/pipelines/release_hermesplus.py",
    "scripts/sync-upstream",
    "ops/",
)

BOOKKEEPING = ("CHANGELOG.md", "README.md", "AGENTS.md", ".gitignore")


def our_lines_in_conflict(target: Path, path: str) -> list[str]:
    """Lines on our side of each conflict block — what must be re-applied."""
    text = (target / path).read_text(errors="ignore")
    lines, ours, in_ours = [], [], False
    for line in text.splitlines():
        if line.startswith("<<<<<<<"):
            in_ours = True
            continue
        if line.startswith("======="):
            in_ours = False
            continue
        if line.startswith(">>>>>>>"):
            continue
        if in_ours:
            lines.append(line)
    return lines


def union_conflicts(target: Path, path: str) -> str:
    """Keep BOTH sides of every conflict block.

    Correct for `project.pbxproj`, and only for files built from independent list
    entries. Verified on this repo's 10 pbxproj blocks: the 24-hex object ids on our
    side and upstream's side do not intersect at all (16 vs 56 ids, 0 shared), so the
    two sets are disjoint registrations and concatenating them is well-defined.
    Braces and parens balance afterwards, no markers remain, and both sides' files
    are present in the Sources lists.

    Do NOT reach for this on Swift sources: two edits to the same function from the
    two sides are not independent entries, and keeping both produces code that
    compiles only by accident.
    """
    text = (target / path).read_text(errors="ignore")
    out: list[str] = []
    for line in text.splitlines():
        if line.startswith(("<<<<<<<", "=======", ">>>>>>>")):
            continue
        out.append(line)
    return "\n".join(out) + "\n"


def pbxproj_ids_are_disjoint(target: Path, path: str) -> tuple[bool, int, int, int]:
    """Confirm the union trick is safe: no object id appears on both sides."""
    text = (target / path).read_text(errors="ignore")
    ident = re.compile(r"\b([A-F0-9]{24})\b")
    ours: set[str] = set()
    theirs: set[str] = set()
    side = None
    for line in text.splitlines():
        if line.startswith("<<<<<<<"):
            side = "ours"
            continue
        if line.startswith("======="):
            side = "theirs"
            continue
        if line.startswith(">>>>>>>"):
            side = None
            continue
        if side == "ours":
            ours |= set(ident.findall(line))
        elif side == "theirs":
            theirs |= set(ident.findall(line))
    shared = ours & theirs
    return (not shared, len(ours), len(theirs), len(shared))


def run(args: list[str], cwd: Path | None = None, check: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        args, cwd=cwd, capture_output=True, text=True, check=False
    ) if not check else subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=True)


def classify(path: str) -> str:
    if path.endswith(".pbxproj"):
        return "pbxproj (four parallel registrations — keep both sides')"
    if path in BOOKKEEPING:
        return "bookkeeping — take ours"
    if "Tests" in path:
        return "tests — read both sides"
    if path.startswith("HermesMobile/"):
        return "app code — resolve by intent"
    return "other"


def main() -> int:
    ap = argparse.ArgumentParser(description="Rehearse an upstream sync")
    ap.add_argument("--dir", default=str(DEFAULT_DIR), help="rehearsal clone location")
    ap.add_argument("--clean", action="store_true", help="remove the rehearsal clone")
    ap.add_argument(
        "--resolve-pbxproj",
        action="store_true",
        help="apply the union resolution to project.pbxproj in the rehearsal clone",
    )
    args = ap.parse_args()

    target = Path(args.dir).expanduser()

    if args.clean:
        if target.exists():
            shutil.rmtree(target)
            print(f"removed {target}")
        else:
            print(f"{target} does not exist")
        return 0

    if target.exists():
        shutil.rmtree(target)

    print(f"cloning {ROOT} → {target}")
    if run(["git", "clone", "--quiet", str(ROOT), str(target)]).returncode != 0:
        print("clone failed")
        return 2

    # A fresh clone has no identity, and merge refuses without one.
    run(["git", "config", "user.email", "rehearsal@local"], cwd=target)
    run(["git", "config", "user.name", "Rehearsal"], cwd=target)

    if run(["git", "remote", "add", "upstream", UPSTREAM_URL], cwd=target).returncode != 0:
        print("could not add the upstream remote")
        return 2

    print("fetching upstream/master")
    if run(["git", "fetch", "--quiet", "upstream", "master"], cwd=target).returncode != 0:
        print("fetch failed — check network access to github.com")
        return 2

    merge = run(["git", "merge", "--no-commit", "--no-ff", "upstream/master"], cwd=target)
    already = "Already up to date" in (merge.stdout + merge.stderr)

    unmerged = run(["git", "diff", "--name-only", "--diff-filter=U"], cwd=target).stdout
    files = [f for f in unmerged.strip().splitlines() if f]

    if already or not files:
        print("\nnothing to merge — upstream is already contained in main")
        return 1

    print("\n" + "=" * 68)
    print("REHEARSAL — conflict set")
    print("=" * 68)

    blocks: list[tuple[int, str]] = []
    for path in files:
        text = (target / path).read_text(errors="ignore")
        blocks.append((text.count("<<<<<<<"), path))
    blocks.sort(reverse=True)

    total = sum(count for count, _ in blocks)
    print(f"\n{len(files)} files, {total} conflict blocks\n")
    for count, path in blocks:
        print(f"  {count:3}  {path}")

    print("\n" + "=" * 68)
    print("BY CLASS")
    print("=" * 68)
    groups: dict[str, list[str]] = {}
    for _, path in blocks:
        groups.setdefault(classify(path), []).append(path)
    for label in sorted(groups, key=lambda k: -len(groups[k])):
        print(f"\n  {label}  ({len(groups[label])})")
        for path in groups[label]:
            print(f"    {path}")

    print("\n" + "=" * 68)
    print("BOOKKEEPING — keep upstream's body, re-apply these lines")
    print("=" * 68)
    for path in BOOKKEEPING:
        if not (target / path).exists():
            continue
        ours = our_lines_in_conflict(target, path)
        ours = [line for line in ours if line.strip()]
        if not ours:
            print(f"  {path}: nothing of ours in the conflict — take upstream")
            continue
        print(f"\n  {path}  ({len(ours)} line(s) of ours):")
        for line in ours:
            print(f"    + {line}")

    print("\n" + "=" * 68)
    print("PBXPROJ — union is safe here")
    print("=" * 68)
    pbx = "HermesMobile.xcodeproj/project.pbxproj"
    if (target / pbx).exists() and "<<<<<<<" in (target / pbx).read_text(errors="ignore"):
        disjoint, n_ours, n_theirs, n_shared = pbxproj_ids_are_disjoint(target, pbx)
        print(f"  our object ids {n_ours}, upstream's {n_theirs}, shared {n_shared}")
        if disjoint:
            print("  no id is on both sides — the two sets are independent registrations,")
            print("  so keeping both sides is well-defined.")
            if args.resolve_pbxproj:
                (target / pbx).write_text(union_conflicts(target, pbx))
                resolved = (target / pbx).read_text(errors="ignore")
                markers = sum(
                    resolved.count(m) for m in ("<<<<<<<", "=======", ">>>>>>>")
                )
                balanced = resolved.count("{") == resolved.count("}")
                print(f"\n  resolved in the rehearsal clone: {markers} markers left, braces balanced: {balanced}")
                print("  NOT applied to the working repo — copy it over deliberately.")
                print("  Confirm no '.swift in Sources' entry was lost:")
                print("    git -C /tmp/upstream-rehearsal diff --stat -- " + pbx)
            else:
                print("  Re-run with --resolve-pbxproj to apply the union in the clone.")
        else:
            print("  SHARED IDS — union would duplicate registrations. Resolve by hand.")
    else:
        print("  no pbxproj conflict")

    print("\n" + "=" * 68)
    print("OUR FILES — confirm these survive the merge")
    print("=" * 68)
    missing = []
    for path in OURS:
        exists = (target / path).exists()
        dirty = run(["git", "status", "--short", "--", path], cwd=target).stdout.strip()
        print(f"  {'ok  ' if exists else 'LOST'} {path}{'  [' + dirty.split()[0] + ']' if dirty else ''}")
        if not exists:
            missing.append(path)

    print("\n" + "=" * 68)
    print("NEXT")
    print("=" * 68)
    print(f"""
  Rehearsal:  {target}   (working repo untouched)
  Plan:       docs/agents/upstream-sync-plan.md
  Clean up:   python3 scripts/upstream-rehearse.py --clean

  Resolve on a branch, not on main, and open a PR — pr-ci.yml triggers on
  pull_request, so a pushed branch alone runs no CI.
""")
    if missing:
        print("  WARNING — these files did not survive, do not commit the merge as-is:")
        for path in missing:
            print(f"    {path}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
