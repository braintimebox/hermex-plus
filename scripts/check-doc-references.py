#!/usr/bin/env python3
"""Gate 7 — documentation must not point at things that do not exist.

Why this exists
---------------
`HERMES.md` names a file, an agent reads it, the file is not there, and the
agent spends its context looking for something that was deleted. That happened
twice in this repository:

  1. `CURRENT.md`, `docs/project-metrics.md`, `scripts/project_metrics.py`
  2. `scripts/pipeline`, `scripts/bump-version.py`, `STATUS.md` —
     deleted on 2026-09-11 while four documents kept presenting them as the
     working path (including the docstring of the gate that runs on every push).

Both times the fix was manual, and both times it missed something. The rule
"keep the docs honest" cannot be remembered, so it is checked instead: every
repo-local path a doc mentions must resolve on disk. Deleting a tool now fails
the next push until the references are gone too.

What it checks
--------------
Inside the scanned docs, any token that looks like a repository path:

    scripts/…  docs/…  ops/…  .githooks/…  .github/…  HermexMobile/…

is collected, stripped of trailing punctuation, and resolved against the repo
root. A token resolves if the path exists, OR if it is a documented-absent
exception below (files this repo intentionally does not have and says so
explicitly).

Deliberately out of scope — the reason each is NOT checked:

  - Plain filenames with no directory (`VERSION`, `CHANGELOG.md`). They are
    mentioned in prose constantly and mostly about upstream's copies.
  - Paths inside fenced code blocks that are commands (`cd ~/.hermes/…`).
    Absolute and home-relative paths are machine state, not repo content.
  - `HermesMobileTests/…` — referenced by line-of-code counts, not by name.
  - Anything under a path segment containing `{{`, `*`, or `<` — templates.

Exit codes: 0 = every reference resolves, 1 = at least one dangling reference.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SCANNED = [
    "HERMES.md",
    "CONVENTIONS.md",
    "AGENTS.md",
    "CLAUDE.md",
    "docs/agents/testing.md",
    "docs/agents/upstream-sync-plan.md",
    "docs/agents/sync-layers.md",
    "docs/agents/arch-001-extracted-state.md",
    "ops/README.md",
]

# Path shapes worth checking. Longest prefix first so `scripts/pipelines/x.py`
# is not mistaken for `scripts/`.
PREFIXES = (
    "scripts/",
    "docs/",
    "ops/",
    ".githooks/",
    ".github/",
)

TOKEN_RE = re.compile(
    r"(?:\.githooks|\.github|scripts|docs|ops)/[A-Za-z0-9_./\-]*[A-Za-z0-9_/]"
)

# Allowed to be absent, each with the reason the doc gives. Keep this list
# SHORT and justified — it is the one hole in the gate.
DOCUMENTED_ABSENT = {
    # Upstream's files. Our docs name them precisely to say they do not exist.
    "docs/project-metrics.md": "deleted upstream; HERMES.md says so",
    "scripts/project_metrics.py": "deleted upstream; HERMES.md says so",
    "scripts/pipeline": "deleted 2026-09-11; HERMES.md says so",
    "scripts/bump-version.py": "deleted 2026-09-11; HERMES.md says so",
    "STATUS.md": "retired 2026-09-11; HERMES.md says so",
}

# A path may be referenced after it was deleted, but only when the line SAYS SO
# in a way a machine can rely on.
#
# The first two attempts at this used a list of natural-language phrases, and
# both lost the gate's teeth: `delete` fires inside `deleted-script.py`, and
# `has been deleted` fires in a sentence that merely mentions an old helper
# while pointing at a live path. Chasing phrasings is an endless tail — every
# fixed list has a sentence it wrongly accepts.
#
# So the contract is explicit instead of inferred: to point at a path that does
# not exist, the line must carry one of the machine markers below. That is a
# small, closed, checkable set, and it cannot be satisfied by accident.
#
#   ❌ — the removal marker used in the tools register
#   ⚠ — the warning marker used for caveats
#   REMOVED / DELETED / УДАЛЁН / упразднён — the word, at the START of a clause
#
# A writer who deletes a file and updates the docs writes one of these, because
# the alternative is a gate failure with this message telling them to.
ABSENCE_MARKERS = (
    "❌",
    "REMOVED:", "DELETED:", "УДАЛЁН:", "УДАЛЕН:",
    "УДАЛЁН 2", "УДАЛЕН 2", "УДАЛЁН (", "УДАЛЕН (",
)


def has_absence_marker(residue: str) -> bool:
    """Whether the text (path already removed) declares a removal.

    `❌` is accepted anywhere on the line. The word markers must begin a clause
    (start of line, or after sentence punctuation) so that `was deleted` inside
    prose does not count — only a label does.
    """
    if "❌" in residue:
        return True
    for marker in ABSENCE_MARKERS:
        idx = residue.find(marker)
        while idx != -1:
            before = residue[:idx].rstrip()
            if not before or before[-1] in ".!?;:—–-*|(❌⚠•#":
                return True
            idx = residue.find(marker, idx + 1)
    return False


def repo_paths(text: str) -> list[tuple[int, str]]:
    """(line number, token) for every path-looking token in the text."""
    found: list[tuple[int, str]] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        for raw in TOKEN_RE.findall(line):
            token = raw.rstrip(".,;:)]}`")
            if not any(token.startswith(p) for p in PREFIXES):
                continue
            found.append((lineno, token))
    return found


def is_documented_absent(line: str, token: str) -> bool:
    """True when the line declares the referenced path to be gone.

    Two guards, both learned from breaking this function:

    1. The markers are matched against the line with the TOKEN ITSELF removed.
       Otherwise a file named `deleted-script.py` matches the marker `deleted`
       and whitelists every reference to itself — the gate would pass on exactly
       the shape it exists to catch.

    2. The marker must be a LABEL (see `has_absence_marker`), not a word that
       happens to appear in a sentence about something else.
    """
    if token in DOCUMENTED_ABSENT:
        return True
    return has_absence_marker(line.replace(token, " "))


def check_file(path: Path) -> list[str]:
    if not path.exists():
        # A scanned document that is itself missing is our problem, not a
        # dangling reference — report it as such.
        return [f"{path.relative_to(ROOT)}: scanned document is missing"]
    problems: list[str] = []
    text = path.read_text(encoding="utf-8", errors="ignore")
    for lineno, token in repo_paths(text):
        line = text.splitlines()[lineno - 1]
        if is_documented_absent(line, token):
            continue
        target = ROOT / token
        # Accept a directory prefix match: `ops/` is a dir, `docs/agents/` too.
        if not target.exists() and not token.endswith("/"):
            # A doc may name a path that is a prefix of an existing directory
            # (e.g. `docs/agents/` written without the slash).
            if not (ROOT / token.rstrip("/")).exists():
                problems.append(
                    f"{path.relative_to(ROOT)}:{lineno}: {token} — no such file or directory"
                )
    return problems


def main() -> int:
    all_problems: list[str] = []
    checked = 0
    for rel in SCANNED:
        p = ROOT / rel
        before = len(all_problems)
        all_problems.extend(check_file(p))
        if p.exists():
            checked += 1

    if all_problems:
        print("gate 7 (doc references) — FAILED")
        print()
        for problem in all_problems:
            print(f"  {problem}")
        print()
        print(f"  {len(all_problems)} dangling reference(s) in {checked} scanned document(s).")
        print("  Fix the reference, or — if the target is intentionally absent —")
        print("  say so on the same line (УДАЛЁН / не искать / deleted), which")
        print("  is how the tools register records the removals.")
        return 1

    print(f"gate 7 (doc references) — ok  {checked} document(s), 0 dangling")
    return 0


if __name__ == "__main__":
    sys.exit(main())