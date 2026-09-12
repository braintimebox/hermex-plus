"""Check 9 — a declaration seen twice in the SAME type scope.

WHY THIS EXISTS
    A conflict resolved by concatenating the two sides duplicates a whole block
    of declarations whenever both sides declare the same thing. Swift then
    reports a wall of `invalid redeclaration of 'x'` — one per name, at the line
    of whichever copy came second — which reads as dozens of independent
    mistakes instead of one spliced block. Brace balance (check 8) cannot see
    it: the file is perfectly balanced with both copies present.

SCOPE IS THE WHOLE PROBLEM
    A first attempt grouped by indentation only and produced 2505 hits, almost
    all false: `let client` inside three different functions, `var id` in three
    different types, overloads with different parameter lists. A gate that noisy
    gets switched off, so it would be worse than no gate.

    This version tracks the enclosing declaration stack properly:
      - a declaration is attributed to the innermost open type/extension
      - declarations inside a function body are ignored entirely (locals are free)
      - funcs are compared by name AND parameter list, so overloads pass
      - a name repeating in a different type, or at a different nesting level,
        is legal and never reported

    That leaves exactly the shape a concatenated merge produces: the same member
    declared twice, side by side, in one type.

EXIT
    0 = no duplicate member in a changed file
    1 = BLOCKER naming the member and both lines
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

TYPE_RE = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:\w+\s+)*?(struct|class|enum|protocol|extension|actor)\s+([\w`]+)"
)
FUNC_RE = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:\w+\s+)*?(func|init|subscript)\s+([\w`]+)?"
)
PROP_RE = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:\w+\s+)*?(var|let)\s+([\w`]+)"
)
CASE_RE = re.compile(r"^\s*case\s")


def strip_noise(text: str) -> str:
    out = []
    i, n = 0, len(text)
    in_line = in_block = in_triple = in_string = False
    escaped = False
    while i < n:
        ch = text[i]
        three = text[i:i + 3]
        nxt = text[i + 1] if i + 1 < n else ""
        if ch == "\n":
            in_line = False
            out.append(ch)
            i += 1
            continue
        if in_line:
            out.append(" ")
            i += 1
            continue
        if in_block:
            if three == "*/":
                in_block = False
                out.append("  ")
                i += 3
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            continue
        if in_triple:
            if three == '"""':
                in_triple = False
                out.append("   ")
                i += 3
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            continue
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            out.append(" ")
            i += 1
            continue
        if ch == "/" and nxt == "/":
            in_line = True
            out.append("  ")
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block = True
            out.append("  ")
            i += 2
            continue
        if three == '"""':
            in_triple = True
            out.append("   ")
            i += 3
            continue
        if ch == '"':
            in_string = True
            out.append(" ")
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def param_signature(clean_lines: list[str], index: int) -> str:
    """Signature of a func declared at clean_lines[index], multi-line safe.

    A one-line-only reader missed overloads whose parameter lists span lines:
    two `transcriptMessages(from:...)` with different arguments looked alike and
    were reported as duplicates. Parameters are collected until the list closes,
    and every label/type token is kept, so differing signatures differ here too.
    """
    text = "\n".join(clean_lines[index:index + 24])
    start = text.find("(")
    if start == -1:
        return "()"
    depth = 0
    for j in range(start, len(text)):
        c = text[j]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return re.sub(r"\s+", "", text[start:j + 1])
    return re.sub(r"\s+", "", text[start:])


ENCLOSING_RE = re.compile(
    r"^(?:@\w+\s+)*(?:final |private |fileprivate |public |internal |open )*"
    r"(class|struct|enum|extension|actor|protocol)\s+([\w`]+)"
)
FUNC_HEAD_RE = re.compile(
    r"^(?:\s*)(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:(?:private|fileprivate|public|internal|static|class|nonisolated|override|"
    r"mutating|final)\s+)*(func|init|subscript)\b"
)

MEMBER_RE = re.compile(
    r"^(\s{4})(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:(?:private|fileprivate|public|internal|static|class|nonisolated|override|"
    r"mutating|final|weak|unowned|lazy|dynamic)\s+)*"
    r"(var|let|func)\s+([\w`]+)"
)


def enclosing_types(clean_lines):
    """Map each line to (innermost enclosing type, brace depth, in_func_body).

    Depth matters as much as the type: a `let data` local inside one function is
    not a member of the type, and two functions each having one is not a
    duplicate. Tracking the offset at which a `func` body opens lets those be
    skipped, while members declared directly in the type are still compared.
    """
    open_types: list[tuple[str, int]] = []
    depth = 0
    func_body_depth: int | None = None
    info: dict[int, tuple[str, bool]] = {}

    for lineno, line in enumerate(clean_lines, start=1):
        m = ENCLOSING_RE.match(line)
        if m and not line.lstrip().startswith("case "):
            open_types.append((m.group(2).strip("`"), depth))
        in_body = func_body_depth is not None and depth >= func_body_depth
        info[lineno] = (open_types[-1][0] if open_types else "<file>", in_body)

        opens = line.count("{")
        closes = line.count("}")
        if opens and FUNC_HEAD_RE.match(line) and func_body_depth is None:
            func_body_depth = depth + 1
        depth += opens - closes
        if func_body_depth is not None and depth < func_body_depth:
            func_body_depth = None
        while open_types and depth <= open_types[-1][1]:
            open_types.pop()

    return info


def find_duplicates(path: Path) -> list[str]:
    clean = strip_noise(path.read_text(encoding="utf-8", errors="replace"))
    lines = clean.splitlines()
    owner = enclosing_types(lines)

    seen: dict[tuple[str, str, str], int] = {}
    report: list[str] = []

    for lineno, line in enumerate(lines, start=1):
        m = MEMBER_RE.match(line)
        if not m:
            continue
        indent, kind, name = m.group(1), m.group(2), m.group(3).strip("`")
        scope, in_body = owner.get(lineno, ("<file>", False))
        if in_body:
            continue  # a local inside a function body is not a type member
        is_static = " static " in f" {line} " or "class " in line.split("func")[0]
        scope = f"{scope}{' (static)' if is_static and kind == 'func' else ''}"

        # A property and a static func of the same name are different decls;
        # funcs differing only by parameter list are overloads, which is legal.
        if kind == "func":
            sig = param_signature(lines, lineno - 1)
            key = (scope, "func", name + sig)
            label = f"func {name}{sig}"
        else:
            key = (scope, kind, name)
            label = f"{kind} {name}"

        if key in seen:
            report.append(
                f"{path.name}:{lineno} duplicates :{seen[key]} — {label} in {scope}"
            )
        else:
            seen[key] = lineno
    return report


def changed_swift() -> list[str]:
    files: set[str] = set()
    for args in (["--name-only", "HEAD"], ["--name-only", "--cached"]):
        out = subprocess.run(["git", "diff", *args], cwd=ROOT,
                             capture_output=True, text=True, check=False).stdout
        files |= {f for f in out.split("\n") if f.endswith(".swift")}
    if not files:
        base = subprocess.run(["git", "merge-base", "HEAD", "upstream/master"],
                              cwd=ROOT, capture_output=True, text=True, check=False).stdout.strip()
        if base:
            out = subprocess.run(["git", "diff", "--name-only", f"{base}...HEAD"],
                                 cwd=ROOT, capture_output=True, text=True, check=False).stdout
            files |= {f for f in out.split("\n") if f.endswith(".swift")}
    return sorted(files)


def main() -> int:
    print("[9/9] duplicate declarations in the same type scope")
    files = changed_swift()
    if not files:
        print("      no changed .swift files — nothing to compare")
        return 0

    total: list[str] = []
    for rel in files:
        p = ROOT / rel
        if p.exists():
            total.extend(find_duplicates(p))

    if total:
        print(f"      BLOCKER: {len(total)} duplicated declaration(s) in one type")
        for line in total[:20]:
            print(f"        {line}")
        if len(total) > 20:
            print(f"        … and {len(total) - 20} more")
        print("      A union that pasted both sides leaves the same member twice.")
        print("      Keep one model — usually upstream's, since it is the one still")
        print("      evolving — then check nothing referenced the other copy.")
        return 1

    print(f"      ok  {len(files)} changed .swift file(s), no duplicate members")
    return 0


if __name__ == "__main__":
    sys.exit(main())
