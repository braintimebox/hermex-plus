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


# --- second shape: two string literals where one argument was expected --------
#
# A union that keeps both sides of an edited string argument produces
#
#     "first wording"
#     "second wording"
#
# with no operator between them. Swift allows adjacent literals only in a
# concatenation context; inside an argument list it reports
# `expected ',' separator` at the SECOND literal, which is why three of these
# were reported as errors at column ~90 of a line the diff never touched.
def strip_comments(text: str) -> str:
    """Remove comments only, keeping string literals intact.

    `strip_noise` blanks literals too (correct for the label scan, wrong for a
    check whose subject is the literal text). This variant keeps them and only
    blanks comment bodies, preserving line structure.
    """
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
            out.append(ch)
            if raw_delim:
                if text.startswith(raw_delim, i):
                    out.extend(raw_delim[1:])
                    i += len(raw_delim)
                    in_str = False
                    raw_delim = None
                    continue
            elif ch == "\\":
                if i + 1 < n:
                    out.append(text[i + 1])
                i += 2
                continue
            elif ch == '"':
                in_str = False
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
            hm = re.match(r'(#+)"""', text[i:])
            if hm:
                raw_delim = '"""' + hm.group(1)
                in_str = True
                out.extend(hm.group(0))
                i += len(hm.group(0))
                continue
            in_str = True
        out.append(ch)
        i += 1
    return "".join(out)

STR_CONT_RISK = re.compile(r'^\s*"')
ARG_HEAD = re.compile(r'^\s*(?:[a-zA-Z_]\w*\s*:\s*)?".*",?\s*$')


def scan_adjacent_strings(path: Path) -> list[str]:
    # RAW text, not the stripped one: this check is about string CONTENT, and
    # strip_noise blanks literals by design. Using the stripped text here made
    # the check silently report nothing.
    raw = path.read_text(encoding="utf-8", errors="replace")
    lines = strip_comments(raw).splitlines()
    problems: list[str] = []
    depth = 0
    for idx in range(len(lines) - 1):
        cur, nxt = lines[idx], lines[idx + 1]
        depth += cur.count("(") - cur.count(")")
        if not ARG_HEAD.match(cur):
            continue
        if not STR_CONT_RISK.match(nxt):
            continue
        # a following line that is only a literal, and the current line has no
        # trailing comma or operator, and we are inside an argument list
        if cur.rstrip().endswith((",", "+", "&&", "||", ")", "]")):
            continue
        if nxt.strip().startswith('"""') or '"""' in nxt:
            continue
        if depth <= 0:
            continue
        # `case "a":` / `return "a"` / `let x = "a"` are not argument lists
        if re.match(r'^\s*(case|return|let|var|if|guard|else|for|while|switch|default)\b', cur):
            continue
        problems.append(
            f"{path.name}:{idx + 2} string literal directly after the literal on "
            f":{idx + 1} — a union kept both wordings"
        )
    return problems


# --- third shape: the same modifier applied twice in one chain ---------------
#
# A union of two branches that both added a modifier to the same view produces
#
#     .onChange(of: streamingScrollTrigger) { ... }   // ours
#     .onChange(of: streamingScrollTrigger) { ... }   // theirs
#
# in one modifier chain. It parses, and then the compiler gives up:
#
#     error: the compiler is unable to type-check this expression in
#            reasonable time
#
# reported at an unrelated line inside the chain, with a cascade after it —
# `ForEach` over a plain array appears to need a Binding, `Binding<Subject>`
# turns up where a String is expected. `transcriptScrollView` cost a CI round
# that way: 154 lines against upstream's 98.
MODIFIER_RE = re.compile(r"^\s*\.(onChange|onReceive|onAppear|onDisappear|task|"
                         r"onSubmit|onDrop|onPaste|onScrollGeometryChange)\s*\(\s*(.+?)\)\s*\{")


def scan_duplicate_modifiers(path: Path) -> list[str]:
    lines = strip_noise(path.read_text(encoding="utf-8", errors="replace")).splitlines()
    seen: dict[tuple[int, str], int] = {}
    problems: list[str] = []
    depth = 0
    prev_depth = 0
    for idx, line in enumerate(lines, start=1):
        if depth < prev_depth:
            # a scope closed: every chain at that depth or deeper has ended, so
            # two same-named modifiers at the same depth in *different* chains
            # (a second `var body`, a sibling builder) must not be paired up.
            # Keep chains at the current depth: a closure body closing back to
            # the chain's own depth is still the same chain. Only a drop BELOW a
            # chain's depth means it ended (a sibling `var body`, another view).
            seen = {k: v for k, v in seen.items() if k[0] <= depth}
        prev_depth = depth
        m = MODIFIER_RE.match(line)
        if m:
            # key by the enclosing brace depth so two chains on different views
            # (different depths, or separated by a closer) do not collide
            normalised = re.sub(r"\s+", "", m.group(2))
            key = (depth, f".{m.group(1)}({normalised})")
            if key in seen:
                problems.append(
                    f"{path.name}:{idx} {m.group(1)}({m.group(2).strip()}) applied twice "
                    f"in one chain (first at :{seen[key]})"
                )
            else:
                seen[key] = idx
        depth += line.count("{") - line.count("}")
        if depth < 0:
            depth = 0
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
            total.extend(scan_adjacent_strings(p))
            total.extend(scan_duplicate_modifiers(p))

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
