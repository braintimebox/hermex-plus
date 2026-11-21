#!/usr/bin/env python3
"""Partition the XCTest classes into N deterministic shards for CI.

Why a script and not a hardcoded list: the suite grows every week, and a list
maintained by hand silently stops covering new classes — the shard that used to
hold them keeps passing while the new tests never run. Here a class with no
entry in the list simply does not exist: every class is re-discovered from the
sources on each run, so a new test file lands in a shard automatically.

The assignment is greedy longest-processing-time packing over the classes sorted
by name. It is deterministic for a given set of classes and widths, but it is
NOT a hash of the name: adding one class changes the loads and can move many
others (measured: one 40-test class moved 60 of 147 classes). Shard membership
is therefore not comparable between runs — say "the suite ran red" rather than
"shard 2 was red", and never diff shard contents across two runs.

Usage:
    python3 scripts/test_shards.py --count 3 --shard 1 --format args
    python3 scripts/test_shards.py --count 3 --format table   # who goes where
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent.parent / "HermesMobileTests"
# Attributes and access modifiers may precede `class`, and the superclass is not
# always XCTestCase: `final class APIClientGitTests: APIClientTestCase` is a test
# class through a project base. The previous pattern demanded exactly
# `class Name: XCTestCase`, so 41 of the 188 test classes were invisible and the
# sharded release path ran a subset of the suite while claiming to run all of it.
DECL_PATTERN = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:(?:final|open|public|internal|fileprivate|private)\s+)*"
    r"class\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*([A-Za-z_][A-Za-z0-9_.]*))?",
    re.MULTILINE,
)
TEST_METHOD_PATTERN = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*func\s+test[A-Za-z0-9_]*\s*\(", re.MULTILINE)
RUNNER_BASE = "XCTestCase"
EXTENSION_PATTERN = re.compile(
    r"^\s*extension\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[^{]*)?\{", re.MULTILINE)
TARGET = "HermesMobileTests"


def _body_end(skeleton: str, brace: int) -> int:
    depth = 0
    for index in range(brace, len(skeleton)):
        char = skeleton[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index + 1
    return len(skeleton)


def _skeleton(text: str) -> str:
    """Same length, comments and string literals blanked.

    Brace counting needs this: a `}` inside a fixture string closed the class body
    early, so `ReviewDiffSelectionTests` looked like a class with zero test methods
    and its five cases were "unattributed" — the coverage gate's first four hits
    were all this artefact.
    """
    out = list(text)
    index, total = 0, len(text)
    while index < total:
        char = text[index]
        if char == "/" and index + 1 < total and text[index + 1] == "/":
            while index < total and text[index] != "\n":
                out[index] = " "
                index += 1
            continue
        if char == "/" and index + 1 < total and text[index + 1] == "*":
            out[index] = out[index + 1] = " "
            index += 2
            while index + 1 < total and not (text[index] == "*" and text[index + 1] == "/"):
                if text[index] != "\n":
                    out[index] = " "
                index += 1
            if index + 1 < total:
                out[index] = out[index + 1] = " "
                index += 2
            continue
        if char == '"':
            if text.startswith('"""', index):
                for offset in range(3):
                    out[index + offset] = " "
                index += 3
                while index < total and not text.startswith('"""', index):
                    if text[index] != "\n":
                        out[index] = " "
                    index += 1
                for offset in range(3):
                    if index + offset < total:
                        out[index + offset] = " "
                index += 3
                continue
            out[index] = " "
            index += 1
            while index < total:
                if text[index] == "\\" and index + 1 < total:
                    out[index] = out[index + 1] = " "
                    index += 2
                    continue
                if text[index] == '"':
                    out[index] = " "
                    index += 1
                    break
                if text[index] != "\n":
                    out[index] = " "
                index += 1
            continue
        index += 1
    return "".join(out)


def _class_bodies(text: str) -> list[tuple[str, str | None, str]]:
    """(name, superclass, body) for every class and extension in `text`.

    Extensions matter: a test class routinely spreads its cases over
    `extension ComposerChipTokenizerTests { … }` blocks, and those cases belong to
    the class's weight — `-only-testing` runs them with the class.
    """
    skeleton = _skeleton(text)
    found: list[tuple[str, str | None, str]] = []
    for match in DECL_PATTERN.finditer(skeleton):
        brace = skeleton.find("{", match.end())
        if brace == -1:
            continue
        found.append((match.group(1), match.group(2), text[brace:_body_end(skeleton, brace)]))
    for match in EXTENSION_PATTERN.finditer(skeleton):
        brace = match.end() - 1
        found.append((match.group(1), None, text[brace:_body_end(skeleton, brace)]))
    return found


def _scan(test_dir: Path) -> tuple[dict[str, str | None], dict[str, list[tuple[str, str | None, str]]]]:
    if not test_dir.is_dir():
        raise SystemExit(f"BLOCKER: test directory not found: {test_dir}")
    declarations: dict[str, str | None] = {}
    per_file: dict[str, list[tuple[str, str | None, str]]] = {}
    # Recursive on purpose: a nested test file is still a test file, and a
    # non-recursive glob would leave it outside both the shards and the coverage
    # check that is supposed to notice exactly this. Nothing lives in a
    # subdirectory today; the check is written so that adding one cannot hide.
    for path in sorted(test_dir.rglob("*.swift")):
        key = path.relative_to(test_dir).as_posix()
        bodies = _class_bodies(path.read_text(errors="replace"))
        for name, superclass, _body in bodies:
            # Only real declarations carry the superclass; an extension's `None`
            # must not shadow it when the two live in different files.
            if superclass is not None:
                declarations.setdefault(name, superclass)
        per_file[key] = bodies
    return declarations, per_file


def test_classes(declarations: dict[str, str | None]) -> set[str]:
    """Classes that XCTest can run: XCTestCase and anything deriving from it."""
    known = {RUNNER_BASE}
    changed = True
    while changed:
        changed = False
        for name, superclass in declarations.items():
            if superclass in known and name not in known:
                known.add(name)
                changed = True
    return {name for name, superclass in declarations.items() if superclass in known}


def discover(test_dir: Path = TESTS_DIR) -> dict[str, int]:
    """Map test class name -> number of `func test…` methods in its body.

    The weight matters: classes differ by two orders of magnitude (a 2-case
    singleton vs a 60-case view-model suite). Balancing by class count gives
    three shards of 48/46/49 that still finish minutes apart; balancing by case
    count is what makes the shards actually overlap in wall clock.
    """
    declarations, per_file = _scan(test_dir)
    classes = test_classes(declarations)
    if not classes:
        raise SystemExit(f"BLOCKER: no XCTestCase classes found under {test_dir}")
    weights = {name: 0 for name in classes}
    for bodies in per_file.values():
        for name, _superclass, body in bodies:
            if name in weights:
                weights[name] += len(TEST_METHOD_PATTERN.findall(body))
    return weights


def coverage_problems(test_dir: Path = TESTS_DIR) -> list[str]:
    """Every `func test…` in the tree must sit in a class the shards know about.

    Without this, a discovery hole is silent: the shard looks green because the
    cases it never received did not run. The gate is the reason the hole above
    cannot come back unnoticed.
    """
    declarations, per_file = _scan(test_dir)
    classes = test_classes(declarations)
    problems: list[str] = []
    scanned = len(per_file)
    present = sum(1 for _ in test_dir.rglob("*.swift"))
    if scanned != present:
        problems.append(f"scanned {scanned} file(s) but found {present} under {test_dir}")
    for path in sorted(test_dir.rglob("*.swift")):
        key = path.relative_to(test_dir).as_posix()
        text = TEST_METHOD_PATTERN.findall(path.read_text(errors="replace"))
        attributed = sum(
            len(TEST_METHOD_PATTERN.findall(body))
            for name, _superclass, body in per_file.get(key, [])
            if name in classes
        )
        if len(text) != attributed:
            problems.append(f"{key}: {len(text)} test methods, {attributed} inside discovered classes")
    return problems


def assign(weights: dict[str, int], count: int) -> list[list[str]]:
    """Greedy longest-processing-time packing over name-sorted classes.

    Deterministic for one set of classes, but not stable against additions: a new
    class shifts the loads and every later name may land in a different shard.
    Name order is what makes two runs on the SAME tree agree, nothing more.
    """
    buckets: list[list[str]] = [[] for _ in range(count)]
    loads = [0] * count
    for name in sorted(weights):
        target = min(range(count), key=lambda i: (loads[i], i))
        buckets[target].append(name)
        loads[target] += weights[name]
    return buckets


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=3, help="number of shards (default 3)")
    ap.add_argument("--shard", type=int, default=1, help="1-based shard index")
    ap.add_argument("--format", choices=("args", "table"), default="args")
    args = ap.parse_args()

    if args.count < 1:
        raise SystemExit("BLOCKER: --count must be >= 1")
    if not 1 <= args.shard <= args.count:
        raise SystemExit(f"BLOCKER: --shard must be within 1..{args.count}")

    weights = discover()
    # Fail closed: a discovery hole looks exactly like a green shard. The check is
    # cheap (one pass over the test sources) and it is the only thing standing
    # between "the suite ran" and "the shard received what discovery found".
    problems = coverage_problems()
    if problems:
        print("BLOCKER: test methods outside the classes the shards are built from:", file=sys.stderr)
        for line in problems[:10]:
            print(f"  {line}", file=sys.stderr)
        if len(problems) > 10:
            print(f"  … and {len(problems) - 10} more file(s)", file=sys.stderr)
        raise SystemExit(1)
    buckets = assign(weights, args.count)

    if args.format == "table":
        for i, bucket in enumerate(buckets, 1):
            cases = sum(weights[n] for n in bucket)
            print(f"shard {i}/{args.count}: {len(bucket)} classes, {cases} cases")
            for name in bucket:
                print(f"  {name} ({weights[name]})")
        print(f"total: {len(weights)} classes, {sum(weights.values())} cases")
        return 0

    # args: one -only-testing flag per class, space separated for the shell.
    print(" ".join(f"-only-testing:{TARGET}/{name}" for name in sorted(buckets[args.shard - 1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
