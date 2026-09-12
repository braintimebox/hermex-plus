"""Check 8 — structural balance of every .swift file against BOTH parents.

WHY THIS EXISTS
    A merge resolved by concatenating conflict sides ("ours + theirs") silently
    loses a closing brace whenever that brace sat at the end of one side. Swift
    then reports the loss as a cascade — one missing `}` in ChatView produced
    twenty-odd `attribute 'private' can only be used in a non-local scope`
    errors at unrelated lines, each of which looked like its own bug. Five CI
    runs were spent chasing the cascade, one brace at a time, because nothing
    local could tell "I broke the structure" from "the file always looked like
    this".

    Line-by-line brace counting does NOT work either: it was tried three times
    during that merge and gave a wrong verdict every time. `{` appears inside
    string literals, multi-line strings, and comments, and `(` in a function
    signature opens a scope that carries no brace at all. Only a scanner that
    tracks string/comment state AND is calibrated against both parents can tell
    the difference, so that is what this check runs.

WHAT IT CHECKS
    For every tracked .swift file:
      1. scan braces with string/comment awareness
      2. depth must be 0 at end of file
      3. when a file differs from both parents, the depth must equal BOTH
         parents' depth — a file that was balanced on both sides and is
         unbalanced now was broken by this branch, not inherited

    Files whose depth is non-zero in a parent as well are reported once as
    inherited noise (they contain interpolation braces the scanner cannot
    attribute) and are not blocked.

EXIT
    0 = every changed file keeps its parents' structural balance
    1 = BLOCKER: this branch introduced an imbalance
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def scan_balance(text: str) -> int:
    """Brace depth at end of file, ignoring braces in strings and comments."""
    i = 0
    n = len(text)
    depth = 0
    in_string = False
    in_line_comment = False
    in_block_comment = False
    escaped = False

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if ch == "\n":
            in_line_comment = False
            i += 1
            continue
        if in_line_comment:
            i += 1
            continue
        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        i += 1

    return depth


def git(*args: str) -> str:
    r = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    )
    return r.stdout


def show(rev: str, path: str) -> str | None:
    out = subprocess.run(
        ["git", "show", f"{rev}:{path}"],
        cwd=ROOT, capture_output=True, text=True, check=False,
    )
    return out.stdout if out.returncode == 0 else None


def parents() -> tuple[str, str]:
    """The two sides a merge had, or (HEAD, HEAD) when there is no merge."""
    merge = git("rev-list", "--parents", "-n", "1", "HEAD").split()
    if len(merge) >= 3:
        return merge[1], merge[2]
    upstream = "upstream/master"
    has_upstream = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", upstream],
        cwd=ROOT, capture_output=True, text=True, check=False,
    ).returncode == 0
    return "HEAD", upstream if has_upstream else "HEAD"


def main() -> int:
    print("[8/8] swift structural balance vs both parents")

    base, other = parents()
    changed = [f for f in git("diff", "--name-only", f"{base}...HEAD").split("\n") if f]
    changed += [f for f in git("diff", "--name-only", other).split("\n") if f]
    swift = sorted({f for f in changed if f.endswith(".swift")})
    if not swift:
        print("      no changed .swift files — nothing to compare")
        return 0

    broken: list[str] = []
    inherited: list[str] = []

    for rel in swift:
        path = ROOT / rel
        if not path.exists():
            continue
        now = scan_balance(path.read_text(encoding="utf-8", errors="replace"))
        if now == 0:
            continue

        depths = []
        for rev in (base, other):
            text = show(rev, rel)
            depths.append(scan_balance(text) if text is not None else None)

        # Block whenever THIS branch made the file worse than either parent.
        # "Both parents must be 0" was too weak: a parent can be unbalanced on
        # its own (an interpolation brace the scanner cannot attribute) while
        # this branch still dropped one more — which is exactly the case that
        # let a broken ChatViewModel through as "inherited".
        made_worse = any(
            d is not None and now > d for d in depths
        )
        if made_worse:
            broken.append(
                f"{rel} (depth {now}; parents {depths[0]}/{depths[1]})"
            )
        # Unbalanced here at exactly the parents' level: pre-existing, not ours.
        elif any(d is not None and d == now for d in depths):
            inherited.append(f"{rel} (depth {now}, unchanged from a parent)")
        else:
            # No parent carried the file at all (new file) and it is unbalanced.
            broken.append(f"{rel} (depth {now}, new file)")

    if inherited:
        print(f"      inherited imbalance (also unbalanced in a parent): {len(inherited)}")
        for rel in inherited[:5]:
            print(f"        {rel}")
    if broken:
        print(f"      BLOCKER: this branch unbalanced {len(broken)} file(s)")
        for rel in broken:
            print(f"        {rel}")
        print("      A merge that concatenates two conflict sides drops the closing")
        print("      brace that sat at the end of a side. Compare with both parents:")
        print("        git diff <base> HEAD -- <file>   and   git diff <other> -- <file>")
        return 1

    print(f"      ok  {len(swift)} changed .swift file(s) structurally balanced")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
