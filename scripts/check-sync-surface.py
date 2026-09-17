#!/usr/bin/env python3
"""Gate 13 — every local change to code upstream also owns is identifiable.

Why this exists
---------------
A fork stays mergeable only while its deviations are *visible*. On 2026-09-12
the 1.6.0 merge dropped six of our lines — a coordinator binding, a `didSet`, a
revision bump, an error clear and two call-site arguments. Nothing marked them
as ours, so the union took upstream's side of the hunk and the loss stayed
invisible until twenty-four tests failed.

Gate 12 answers that at the level of *symbols*: a declared type may not vanish.
It cannot see inside a function, so it never noticed those six lines. This gate
answers it at the level of *lines*: a change we make to a file upstream also
owns must say, in the code itself, that it is ours and why.

The rule this encodes
---------------------
Every change must survive the next sync. That is only possible when each one is

  1. sent upstream when upstream owns the defect, so it arrives as their code
     and stops being a local diff at all, or
  2. marked `HERMEX-FORK: <measured cause>` when it stays local, so the next
     merge resolver — human or agent — can see which side is ours and keep it.

A marker is not decoration: it is the only thing in the diff that survives a
context-free merge. It also carries the intent to upstream it, which is what
retires the marking later.

What it checks
--------------
For every file that exists in `upstream/master` and that we have changed since
`merge-base(main, upstream/master)`, each added hunk must contain a
`HERMEX-FORK:` marker. Files that do not exist upstream are fork-owned and are
never asked for one.

`merge-base` and not `upstream/master` as the baseline — the same correction
gate 12 needed. Comparing against their current HEAD makes their own rewrites
look like our losses, because `main` is a fork of a *past* upstream.

The unmarked backlog that already exists is recorded, not blocked: the gate
fails only on an unmarked hunk that is *new*. That keeps it usable on the day it
lands instead of demanding a migration before it can run.

Usage
-----
    python3 scripts/check-sync-surface.py            # gate
    python3 scripts/check-sync-surface.py --report   # full surface, no verdict
    python3 scripts/check-sync-surface.py --record   # re-baseline the backlog
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECORD = ROOT / "docs" / "agents" / "sync-surface.json"
OUR_BRANCH = "main"
THEIR_BRANCH = "upstream/master"

MARKER = "HERMEX-FORK:"

# Comment syntaxes we can demand a marker in. A file outside this set is
# reported but never blocked: we cannot state the rule for a language we have
# not taught the gate.
MARKER_SUFFIXES = {".swift", ".py", ".sh", ".yml", ".yaml", ".mjs", ".js"}

# A hunk is a contiguous run of added lines. One line is enough: the six lines
# lost in the 1.6.0 merge were five separate one-liners and a two-line call.
HUNK_CONTEXT = 3


def git(*args: str) -> str:
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True)
    return r.stdout.decode("utf-8", errors="replace")


def git_ok(*args: str) -> int:
    return subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True
    ).returncode


def upstream_tree() -> set[str]:
    out = git("ls-tree", "-r", "--name-only", THEIR_BRANCH)
    return {f.strip() for f in out.splitlines() if f.strip()}


def changed_files(base: str) -> list[str]:
    out = git("diff", "--name-only", f"{base}..HEAD")
    files = [f.strip() for f in out.splitlines() if f.strip()]
    # Uncommitted work counts too: the gate runs from the pre-push hook, but a
    # developer reading a failing run should see the hunk they just wrote.
    out = git("diff", "--name-only", "HEAD")
    files += [f.strip() for f in out.splitlines() if f.strip()]
    return sorted(set(files))


def added_hunks(base: str, path: str) -> list[tuple[int, list[str]]]:
    """Contiguous runs of lines added in `path` since `base`.

    Returns (first line number in the new file, added lines) per hunk. `-U0`
    so a hunk is exactly what we added, with no upstream context to confuse the
    marker search.
    """
    diff = git("diff", "-U0", base, "--", path)
    hunks: list[tuple[int, list[str]]] = []
    current_start = None
    current_lines: list[str] = []

    for line in diff.splitlines():
        if line.startswith("@@"):
            if current_start is not None and current_lines:
                hunks.append((current_start, current_lines))
            current_lines = []
            m = re.search(r"\+(\d+)", line)
            current_start = int(m.group(1)) if m else 0
        elif line.startswith("+") and not line.startswith("+++"):
            current_lines.append(line[1:])
        elif line.startswith("-") or line.startswith("\\"):
            # A deletion splits the run: the lines either side of it are not
            # one insertion, and only one of them may need a marker.
            if current_start is not None and current_lines:
                hunks.append((current_start, current_lines))
                current_lines = []
            current_start = None

    if current_start is not None and current_lines:
        hunks.append((current_start, current_lines))
    return hunks


def file_lines(ref: str, path: str) -> list[str]:
    return show(ref, path).splitlines()


def show(ref: str, path: str) -> str:
    if ref == ":WORKTREE:":
        p = ROOT / path
        if not p.exists():
            return ""
        return p.read_text(encoding="utf-8", errors="replace")
    return git("show", f"{ref}:{path}")


def hunk_is_marked(lines: list[str], preceding: list[str]) -> bool:
    """A marker inside the hunk, or in the lines immediately above it."""
    for line in lines + preceding:
        if MARKER in line:
            return True
    return False


def hunk_id(path: str, lines: list[str]) -> str:
    """Stable identity for a hunk: the file plus its exact content.

    Content and not a line number, so a hunk that merely moved down the file
    after an unrelated edit is the same hunk, and one that was rewritten is a
    different one.
    """
    body = "\n".join(l.rstrip() for l in lines)
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]
    return f"{path}::{digest}"


def analyse() -> tuple[list[dict], list[dict], str]:
    base = git("merge-base", OUR_BRANCH, THEIR_BRANCH).strip()
    if not base:
        sys.exit(f"no merge-base between {OUR_BRANCH} and {THEIR_BRANCH} — fetch first")

    theirs = upstream_tree()
    rows: list[dict] = []
    unmarked: list[dict] = []

    for path in changed_files(base):
        fork_owned = path not in theirs
        hunks = added_hunks(base, path)
        if not hunks:
            continue

        marked = 0
        for start, lines in hunks:
            all_lines = file_lines(":WORKTREE:", path)
            preceding = all_lines[max(0, start - 1 - HUNK_CONTEXT): max(0, start - 1)]
            if hunk_is_marked(lines, preceding):
                marked += 1
            elif not fork_owned and Path(path).suffix in MARKER_SUFFIXES:
                unmarked.append({
                    "id": hunk_id(path, lines),
                    "path": path,
                    "line": start,
                    "preview": (lines[0].strip()[:90] if lines else ""),
                })

        rows.append({
            "path": path,
            "fork_owned": fork_owned,
            "hunks": len(hunks),
            "marked": marked,
            "added_lines": sum(len(l) for _, l in hunks),
        })

    return rows, unmarked, base


def load_record() -> dict:
    if not RECORD.exists():
        return {"baseline_unmarked": [], "baseline_base": ""}
    return json.loads(RECORD.read_text(encoding="utf-8"))


def write_record(unmarked: list[dict], base: str, rows: list[dict]) -> None:
    RECORD.parent.mkdir(parents=True, exist_ok=True)
    RECORD.write_text(json.dumps({
        "_comment": (
            "Generated by scripts/check-sync-surface.py --record. "
            "`baseline_unmarked` is the local-edit backlog that predates gate 13: "
            "changes to upstream-owned files with no HERMEX-FORK marker. The gate "
            "fails only on an unmarked hunk that is NOT listed here, so the backlog "
            "is a debt to pay down when a file is next touched, not a blocker. "
            "`baseline_base` is the merge-base it was measured at."
        ),
        "baseline_base": base,
        "baseline_unmarked": sorted(u["id"] for u in unmarked),
        "baseline_detail": sorted(unmarked, key=lambda u: (u["path"], u["line"])),
        "surface": sorted(rows, key=lambda r: r["path"]),
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="Hermex Plus gate 13 — sync surface")
    ap.add_argument("--report", action="store_true", help="print the surface, no verdict")
    ap.add_argument("--record", action="store_true", help="re-baseline the unmarked backlog")
    ap.add_argument("--list", action="store_true", help="print the unmarked hunks")
    args = ap.parse_args()

    if git_ok("rev-parse", "--verify", f"{THEIR_BRANCH}") != 0:
        print("      upstream/master is not fetched — gate skipped")
        return 0

    rows, unmarked, base = analyse()
    record = load_record()
    known = set(record.get("baseline_unmarked", []))
    fresh = [u for u in unmarked if u["id"] not in known]

    if args.record:
        write_record(unmarked, base, rows)
        print(f"      baseline recorded: {len(unmarked)} unmarked hunk(s), "
              f"{len(rows)} changed file(s), base {base[:8]}")
        return 0

    if args.list:
        for u in sorted(unmarked, key=lambda u: (u["path"], u["line"])):
            tag = "new" if u["id"] not in known else "old"
            print(f"      [{tag}] {u['path']}:{u['line']}  {u['preview']}")
        return 0

    fork_owned = sum(1 for r in rows if r["fork_owned"])
    edited = len(rows) - fork_owned
    added = sum(r["added_lines"] for r in rows)
    marked = sum(r["marked"] for r in rows)

    if args.report:
        print(f"      base {base[:8]} · {len(rows)} changed file(s): "
              f"{fork_owned} fork-owned, {edited} upstream-owned")
        print(f"      {added} added line(s) in {marked + len(unmarked)} hunk(s), "
              f"{marked} marked, {len(unmarked)} unmarked")
        return 0

    if fresh:
        print(f"      {len(fresh)} new unmarked change(s) in upstream-owned code:")
        for u in fresh[:8]:
            print(f"        {u['path']}:{u['line']}  {u['preview']}")
        if len(fresh) > 8:
            print(f"        … and {len(fresh) - 8} more (--list)")
        print(f"      add `// {MARKER} <why>` inside the hunk, or send it upstream "
              f"so it arrives as their code.")
        return 1

    print(f"      ok  {marked} marked, {len(unmarked)} recorded backlog, "
          f"no new unmarked change")
    return 0


if __name__ == "__main__":
    sys.exit(main())
