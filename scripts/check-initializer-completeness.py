#!/usr/bin/env python3
"""Gate 10 — every stored property is initialized on every path of every init.

Why this exists
---------------
Gate 8 (structural balance) and gate 9 (duplicate declarations) catch unions
that pasted both sides. This one catches the *other* half of a merge: upstream
adds a stored property, our own convenience init keeps compiling "almost" —
until Swift reports

    return from initializer without initializing all stored properties

`SessionSummary.matchPreview` arrived that way: upstream added `let
matchPreview: String?` and set it in their decoder, while our
`init(sessionId:title:)` (which upstream does not have) still listed 32 of 34
properties. One line, but a full CI round to discover.

What it checks
--------------
For each Swift type that declares stored properties AND at least one `init`:

  * collect stored properties — `let`/`var` at member level, excluding
    `static`/`class` and excluding computed properties (`var x: T {`)
  * a property with an initializer on its own line (`= ...`) needs no assignment
  * an optional `var` is implicitly nil-initialized; an optional `let` is NOT
  * for each init body, collect `self.x =` assignments and check the init
    either assigns or delegates (`self.init(`) — a delegating init is exempt

Reports a property as UNINITIALIZED when an init assigns *some* properties
but not that one. An init that assigns none is treated as a delegating or
stub init and skipped, which keeps protocol-requiring inits quiet.

Calibration note: an earlier attempt flagged every `var` in the file including
computed ones and produced noise; the check below only reports when the
enclosing initializer has at least one `self.` assignment, so an empty
placeholder init in a test double does not fail the build.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

TYPE_RE = re.compile(
    r"^(?P<indent>\s*)(?:(?:public|internal|private|fileprivate|final|open|"
    r"@\w+(?:\([^)]*\))?)\s+)*(?:class|struct|actor)\s+(?P<name>\w+)"
)
INIT_RE = re.compile(
    r"^(?P<indent>\s*)(?:(?:public|internal|private|fileprivate|convenience|"
    r"required|override|@\w+(?:\([^)]*\))?)\s+)*init\b"
)
PROP_RE = re.compile(
    r"^(?P<indent>\s*)(?:(?:public|internal|private|fileprivate|final|lazy|"
    r"weak|unowned|nonisolated|@\w+(?:\([^)]*\))?)\s+)*"
    r"(?P<kind>let|var)\s+(?P<name>\w+)\s*:\s*(?P<type>[^={]+?)\s*(?P<tail>=|\{|$)"
)
ASSIGN_RE = re.compile(r"(?<![\w.])(?:self\.|_)?(\w+)\s*=(?!=)")
DELEGATE_RE = re.compile(r"\bself\.init\s*\(")


def strip_noise(text: str) -> str:
    """Blank out comments and string literals, keeping line count and offsets."""
    out = []
    i = 0
    n = len(text)
    in_line = False
    in_block = 0
    in_str = False
    raw_delim = None
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line:
            if ch == "\n":
                in_line = False
                out.append(ch)
            else:
                out.append(" ")
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
            hash_m = re.match(r'(#+)"""', text[i:])
            if hash_m:
                raw_delim = '"""' + hash_m.group(1)
                in_str = True
                out.extend(" " * len(hash_m.group(0)))
                i += len(hash_m.group(0))
                continue
            in_str = True
            out.append(" ")
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def type_bounds(lines: list[str], start: int) -> int:
    """Index of the closing brace line of the type whose `{` opens at/after `start`."""
    depth = 0
    seen = False
    for j in range(start, len(lines)):
        depth += lines[j].count("{") - lines[j].count("}")
        if "{" in lines[j]:
            seen = True
        if seen and depth <= 0:
            return j
    return len(lines) - 1


def init_bounds(lines: list[str], start: int, limit: int) -> int:
    """Closing brace line of the init body, or `start` when there is no body.

    A multi-line signature puts the opening `{` many lines below `init(` —
    `AuthManager.init(keychain:clientFactory:...)` spans eight lines before one.
    Scanning from the `init(` line therefore saw an empty body and reported every
    property as uninitialized. Walk to the `{` first, then brace-match.
    """
    open_line = None
    for j in range(start, limit + 1):
        if "{" in lines[j]:
            open_line = j
            break
        if ")" in lines[j] and "->" not in lines[j] and j > start:
            # signature closed without a body (e.g. `init?()` in a protocol)
            if lines[j].rstrip().endswith(")"):
                return start
    if open_line is None:
        return start
    depth = 0
    seen = False
    for j in range(open_line, limit + 1):
        depth += lines[j].count("{") - lines[j].count("}")
        if "{" in lines[j]:
            seen = True
        if seen and depth <= 0:
            return j
    return start


def check_file(path: Path) -> list[str]:
    clean = strip_noise(path.read_text(encoding="utf-8", errors="replace"))
    lines = clean.splitlines()
    problems: list[str] = []

    for i, line in enumerate(lines):
        m = TYPE_RE.match(line)
        if not m:
            continue
        indent = len(m.group("indent"))
        end = type_bounds(lines, i)

        # A nested type's init must not be checked against this type's
        # properties: `Coordinator.init` writes `_text = text` for its own
        # @Binding, which says nothing about the enclosing view's members.
        nested = [
            k for k in range(i + 1, end + 1)
            if TYPE_RE.match(lines[k])
            and len(TYPE_RE.match(lines[k]).group("indent")) > indent
        ]

        def in_nested(line_index: int) -> bool:
            for k in nested:
                if k < line_index:
                    n_end = type_bounds(lines, k)
                    if line_index <= n_end:
                        return True
            return False

        stored: dict[str, tuple[int, str, bool]] = {}
        inits: list[int] = []
        for j in range(i + 1, end + 1):
            ln = lines[j]
            if not ln.strip():
                continue
            cur_indent = len(ln) - len(ln.lstrip())
            if cur_indent <= indent:
                continue
            if in_nested(j):
                continue
            if INIT_RE.match(ln):
                inits.append(j)
                continue
            pm = PROP_RE.match(ln)
            if not pm or len(pm.group("indent")) != indent + 4:
                continue
            if " static " in f" {ln} " or re.search(r"\bstatic\b|\bclass\b(?=\s+var)", ln):
                continue
            name = pm.group("name")
            kind = pm.group("kind")
            tail = pm.group("tail")
            ptype = pm.group("type").strip()

            # A tuple or closure type may span several lines:
            #     private var reconnectTask: (
            #         id: UUID, ...
            #     )?
            # The `)?` that marks it optional sits on the closing line, so join
            # the declaration until brackets balance before deciding.
            if tail not in ("=", "{") and (ptype.count("(") > ptype.count(")")
                                           or ptype.count("[") > ptype.count("]")):
                joined = ptype
                k = j + 1
                while k <= end and (joined.count("(") > joined.count(")")
                                    or joined.count("[") > joined.count("]")):
                    joined += " " + lines[k].strip()
                    k += 1
                ptype = joined
                if ptype.rstrip().endswith("?") or ptype.rstrip().endswith("="):
                    continue  # optional (implicitly nil) or defaulted
                stored[f"{name}@multi"] = (j + 1, ptype, kind == "var")
                continue

            if tail == "=":
                continue  # default value on the declaration
            if tail == "{":
                continue  # computed property
            if kind == "var" and ptype.endswith("?"):
                continue  # optional var is implicitly nil
            if kind == "var" and ptype.startswith("["):
                # a `var x: [T]` without a default is still required; keep it
                pass
            stored[name] = (j + 1, ptype, kind == "var")

        if not stored or not inits:
            continue

        for j in inits:
            body_end = init_bounds(lines, j, end)
            body = lines[j : body_end + 1]
            assigned = set()
            for bl in body:
                stripped = bl.strip()
                # `guard let x = ...`, `if let x = ...`, `for (a, b) in ...`,
                # `while let x = ...` introduce locals, not property writes.
                if re.match(r"^(guard|if|else if|for|while|switch|case|return)\b", stripped):
                    continue
                # `let x = ...` / `var x = ...` at statement level is a local
                if re.match(r"^(let|var)\s+\w+\s*=", stripped):
                    continue
                for name in ASSIGN_RE.findall(bl):
                    if name in stored:
                        assigned.add(name)
            if DELEGATE_RE.search("\n".join(body)):
                continue
            if not assigned:
                continue  # stub / interface-only init
            for name, (decl_line, ptype, _is_optional_var) in stored.items():
                if name not in assigned:
                    problems.append(
                        f"{path.name}:{j + 1} init does not initialize "
                        f"'{name}' ({ptype}) declared at :{decl_line}"
                    )
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
    files = [f for f in out.split("\n") if f.strip()]
    # include the working tree, so the gate is honest before a commit too
    dirty = subprocess.run(
        ["git", "status", "--porcelain", "--", "*.swift"],
        cwd=ROOT, capture_output=True, text=True,
    ).stdout
    for row in dirty.split("\n"):
        rel = row[3:].strip()
        if rel and rel not in files:
            files.append(rel)
    return files


def main() -> int:
    files = changed_swift()
    if not files:
        print("[10/10] initializer completeness — no changed .swift files")
        return 0

    total: list[str] = []
    for rel in files:
        p = ROOT / rel
        if p.exists() and p.suffix == ".swift":
            total.extend(check_file(p))

    print("[10/10] initializer completeness (all stored properties set)")
    if total:
        print(f"      BLOCKER: {len(total)} uninitialized stored propert(y/ies)")
        for line in total[:20]:
            print(f"        {line}")
        print("      A merge added a stored property without updating every init.")
        print("      Either assign it in the init (nil for a placeholder) or give")
        print("      the declaration a default value.")
        return 1
    print(f"      ok  {len(files)} changed .swift file(s), all inits complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
