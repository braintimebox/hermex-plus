#!/usr/bin/env python3
"""Controls for gate 9 — duplicate declarations in one type scope.

The gate infers structure from line patterns, so every structural rule needs a
positive and a negative control of its own. Written as a file because the gate has
already produced three false verdicts in one release: shard layout ignoring
`@MainActor`, coverage ignoring nested directories, and duplicates ignoring
`protocol` + its `extension` default implementations (sixteen blockers in one file).

Run: python3 scripts/tests/test_duplicate_declarations.py
Exit: 0 all controls behave, 1 otherwise.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
FIXTURES = ROOT / "scripts" / "tests" / "fixtures"

spec = importlib.util.spec_from_file_location(
    "cdd", ROOT / "scripts" / "check-duplicate-declarations.py"
)
assert spec is not None and spec.loader is not None, "gate 9 script is missing"
cdd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cdd)

CASES = [
    (
        "protocol requirement + default implementation is one contract, not a duplicate",
        "dup_protocol_extension_default.swift",
        0,
    ),
    (
        "two implementations of one member in one type is a duplicate",
        "dup_two_implementations.swift",
        1,
    ),
]


def main() -> int:
    failures = 0
    for label, name, expected in CASES:
        path = FIXTURES / name
        if not path.exists():
            print(f"  FAIL  {label}: fixture missing ({name})")
            failures += 1
            continue
        found = cdd.find_duplicates(path)
        ok = len(found) == expected
        print(f"  {'ok  ' if ok else 'FAIL'}  {label}: {len(found)} report(s), expected {expected}")
        if not ok:
            for line in found:
                print(f"          {line}")
            failures += 1

    # The real file that exposed the defect: sixteen requirements have defaults.
    kanban = ROOT / "HermesMobile" / "Networking" / "APIClient+Kanban.swift"
    if kanban.exists():
        found = cdd.find_duplicates(kanban)
        ok = not found
        print(f"  {'ok  ' if ok else 'FAIL'}  KanbanDataClient defaults are not duplicates: "
              f"{len(found)} report(s)")
        if not ok:
            for line in found[:3]:
                print(f"          {line}")
            failures += 1

    # Guard the cross-scope rule that shares enclosing_types(): a type and a type it
    # owns declaring the same property must still be reported.
    print("  ---- cross-scope rule still runs: "
          f"{len(cdd.cross_scope_duplicates(kanban)) if kanban.exists() else 'n/a'} report(s)")

    print(f"  controls: {len(CASES) + (1 if kanban.exists() else 0)}, failures: {failures}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
