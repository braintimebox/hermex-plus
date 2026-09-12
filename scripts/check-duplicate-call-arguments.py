#!/usr/bin/env python3
"""Gate 11 — the same argument label passed twice to one call.

Why this exists
---------------
A union that keeps both sides of an edited call site does not always produce a
syntax error. When both sides are arguments of the *same* call, the result
parses and then fails deep in the type checker:

    SettingsToggleRow(
        title: String(localized: "Response Timestamps"),   // ours
        title: String(localized: "Message Timestamps"),    // upstream
        ...
    )

Swift reports that as

    the compiler is unable to type-check this expression in reasonable time

at the *outermost* expression — i.e. at `SettingsView`, hundreds of lines from
the actual duplicate. Two more instances survived in the same merge:
`onSelectReasoningEffort` and `onDismissKeyboard` in `ChatView`, both passed
twice into one initializer.

What separates a real duplicate from noise
------------------------------------------
Two things the first ad-hoc scan got wrong and this one does not:

  1. **Call boundaries.** `onSelectReasoningEffort` appearing twice in a file
     is normal if the file has two calls. Only labels inside ONE parenthesised
     argument list count. Paren depth is tracked properly: a `(` opens a new
     scope unless it belongs to a call whose labels are already being
     collected, and a label is recorded against the innermost open scope.

  2. **`case` is not an argument.** `switch x { case "a": ... case "b": ... }`
     matches the `label:` shape while being a statement. A label followed by
     `:` inside a switch body is skipped; the file's brace/paren state decides.

A duplicate is reported only for the same label at the same paren depth inside
the same call, with no intervening closing delimiter.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

LABEL_RE = re.compile(r"^(\s*)([a-zA-Z_]\w*)\s*:\s*(?!:)")


def strip_noise(text: str) -> str:
    """Blank out comments and string literals, preserving line structure."""
    out: list[str] = []
    i, n = 0, len(text)
    in_line = False
    in_block = 0
    in_str = False
    raw_delim: str | None = None
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line:
            out.append("\n" if ch == "\n" else " ")
            if ch == "\n":
                in_line = False
            i += 1
            continue
        if in_block:
            if ch == "*" and nxt == "/":
                in_block -= 1
                out.extend("  ")
                i += 2
                continue
            if ch == "/" and nxt == "*":
                in_block += 1
                out.extend("  ")
                i += 2
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            continue
        if in_str:
            if raw_delim:
                if text.startswith(raw_delim, i):
                    out.extend(" " * len(raw_delim))
                    i += len(raw_delim)
                    in_str = False
                    raw_delim = None
                    continue
            elif ch == "\\":
                out.extend("  ")
                i += 2
                continue
            elif ch == '"':
                out.append(" ")
                i += 1
                in_str = False
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            continue
        if ch == "/" and nxt == "/":
            in_line = True
            out.extend("  ")
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block += 1
            out.extend("  ")
            i += 2
            continue
        if ch == '"':
            m = re.match(r'"""(.*?)"""', text[i:], re.S)
            if m:
                out.extend(" " * len(m.group(0)))
                i += len(m.group(0))
                continue
            hm = re.match(r'(#+)"""', text[i:])
            if hm:
                raw_delim = '"""' + hm.group(1)
                in_str = True
                out.extend(" " * len(hm.group(0)))
                i += len(hm.group(0))
                continue
            in_str = True
            out.append(" ")
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def scan(path: Path) -> list[str]:
    lines = strip_noise(path.read_text(encoding="utf-8", errors="replace")).splitlines()
    problems: list[str] = []

    # each frame: {"labels": {label: line}, "switch": bool}
    stack: list[dict] = []
    brace_depth = 0
    switch_stack: list[int] = []  # brace depth at which each switch body opened

    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()

        # entering a switch body?
        if re.search(r"\bswitch\b", stripped):
            switch_stack.append(brace_depth)

        m = LABEL_RE.match(line)
        if m and stack and not stripped.startswith("case "):
            label = m.group(2)
            if label not in ("default",):
                frame = stack[-1]
                if label in frame["labels"]:
                    problems.append(
                        f"{path.name}:{idx} '{label}' passed twice in the same call "
                        f"(first at :{frame['labels'][label]})"
                    )
                else:
                    frame["labels"][label] = idx

        opens_paren = line.count("(")
        closes_paren = line.count(")")
        opens_brace = line.count("{")
        closes_brace = line.count("}")

        for _ in range(opens_paren):
            stack.append({"labels": {}})
        for _ in range(closes_paren):
            if stack:
                stack.pop()

        brace_depth += opens_brace - closes_brace
        while switch_stack and brace_depth < switch_stack[-1]:
            switch_stack.pop()

    return problems


def changed_swift() -> list[str]:
    try:
        base = subprocess.run(
            ["git", "merge-base", "HEAD", "upstream/master"],
            cwd=ROOT, capture_output=True, text=True,
        ).stdout.strip()
    except Exception:
        base = ""
    ref = base or "HEAD~1"
    out = subprocess.run(
        ["git", "diff", "--name-only", ref, "HEAD", "--", "*.swift"],
        cwd=ROOT, capture_output=True, text=True,
    ).stdout
    files = {f for f in out.split("\n") if f.strip()}
    dirty = subprocess.run(
        ["git", "status", "--porcelain", "--", "*.swift"],
        cwd=ROOT, capture_output=True, text=True,
    ).stdout
    for row in dirty.split("\n"):
        rel = row[3:].strip()
        if rel:
            files.add(rel)
    return sorted(files)


def main() -> int:
    files = changed_swift()
    if not files:
        print("[11/11] duplicate call arguments — no changed .swift files")
        return 0

    total: list[str] = []
    for rel in files:
        p = ROOT / rel
        if p.exists() and p.suffix == ".swift":
            total.extend(scan(p))

    print("[11/11] duplicate call arguments (same label twice in one call)")
    if total:
        print(f"      BLOCKER: {len(total)} duplicated argument(s)")
        for line in total[:20]:
            print(f"        {line}")
        print("      A union kept both sides of an edited call. Swift parses it,")
        print("      then reports `unable to type-check ... in reasonable time`")
        print("      at the OUTERMOST expression — far from the duplicate.")
        return 1
    print(f"      ok  {len(files)} changed .swift file(s), no duplicate arguments")
    return 0


if __name__ == "__main__":
    sys.exit(main())
