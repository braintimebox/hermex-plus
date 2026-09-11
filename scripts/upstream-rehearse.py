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
