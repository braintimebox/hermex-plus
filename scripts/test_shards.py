#!/usr/bin/env python3
"""Partition the XCTest classes into N deterministic shards for CI.

Why a script and not a hardcoded list: the suite grows every week, and a list
maintained by hand silently stops covering new classes — the shard that used to
hold them keeps passing while the new tests never run. Here a class with no
entry in the list simply does not exist: every class is re-discovered from the
sources on each run, so a new test file lands in a shard automatically.

The assignment is a hash of the class name, so it is stable across runs and
across machines. A test that fails in shard 2 today fails in shard 2 tomorrow;
nothing moves between shards when unrelated classes are added.

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
CLASS_PATTERN = re.compile(r"^\s*(?:final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*XCTestCase", re.MULTILINE)
TEST_METHOD_PATTERN = re.compile(r"^\s*func\s+test[A-Za-z0-9_]*\s*\(", re.MULTILINE)
ANY_METHOD_PATTERN = re.compile(r"^\s*(?:@MainActor\s*)?(?:private\s+)?func\s+", re.MULTILINE)
TARGET = "HermesMobileTests"


def discover(test_dir: Path = TESTS_DIR) -> dict[str, int]:
    """Map class name -> number of `func test…` methods in it.

    The weight matters: classes differ by two orders of magnitude (a 2-case
    singleton vs a 60-case view-model suite). Balancing by class count gives
    three shards of 48/46/49 that still finish minutes apart; balancing by case
    count is what makes the shards actually overlap in wall clock.
    """
    if not test_dir.is_dir():
        raise SystemExit(f"BLOCKER: test directory not found: {test_dir}")
    weights: dict[str, int] = {}
    for path in sorted(test_dir.glob("*.swift")):
        text = path.read_text(errors="replace")
        marks = [(m.start(), m.group(1)) for m in CLASS_PATTERN.finditer(text)]
        if not marks:
            continue
        for idx, (pos, name) in enumerate(marks):
            end = marks[idx + 1][0] if idx + 1 < len(marks) else len(text)
            body = text[pos:end]
            weights[name] = weights.get(name, 0) + len(TEST_METHOD_PATTERN.findall(body))
    if not weights:
        raise SystemExit(f"BLOCKER: no XCTestCase classes found under {test_dir}")
    return weights


def assign(weights: dict[str, int], count: int) -> list[list[str]]:
    """Greedy longest-processing-time packing over deterministically ordered names.

    Ordering by name (not by weight) keeps the assignment stable: adding a class
    can move only classes that sort after it, and only when the loads tie.
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
