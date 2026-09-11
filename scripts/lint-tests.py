#!/usr/bin/env python3
"""Test-lint: catch assertions that encode a race as if it were a contract.

Run by the pre-push gate (scripts/pipeline-precheck.py) and in CI. Each rule
below corresponds to a failure that actually reached CI in this repo, not to a
style preference — see docs/agents/testing.md for the narrative and the fixing
commit for each.

Why a linter rather than a note in a document: a note asks the next person to
remember and to judge. These rules are mechanically checkable, so they are
checked. On the day testing.md was written, its author had already violated the
isolation rule in the same session, having written the rule two hours earlier.

Rules
-----
L1  Literal request-order assertion containing both endpoints that the loader
    issues with `async let`. The order is not defined, so the assertion is a race.

L2  `waitUntil`-style poll loop that falls through on timeout without failing.
    The test then continues and reports whatever state it found, which reads as a
    data bug in the code under test.

L3 (cache read after an async trigger) was written and removed: matching it needs
to know whether a `waitUntil` sits between the trigger and the read, and a regex
over multi-line Swift cannot do that reliably. It did not fire on a deliberately
injected violation, which is the only test that matters for a rule. A rule that
cannot fail is worse than no rule, because it reports the code as clean.

Exit code is 0 (clean), 1 (findings), or 2 (the linter itself could not run).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "HermesMobileTests"

# Endpoints the composer loader issues concurrently (`async let`), so their
# relative arrival order at the client is not defined.
PARALLEL_ENDPOINTS = ("/api/reasoning", "/api/workspaces")


def _test_files() -> list[Path]:
    if not TESTS.is_dir():
        return []
    return sorted(TESTS.rglob("*.swift"))


def lint_parallel_order(path: Path, text: str) -> list[str]:
    """L1 — a literal list containing both concurrent endpoints."""
    findings = []
    # XCTAssertEqual(requestPaths, [ ... ]) — capture the literal body.
    for match in re.finditer(
        r"XCTAssertEqual\(\s*(requestedPaths|requestPaths)\s*,\s*\[(.*?)\]\s*\)",
        text,
        re.S,
    ):
        body = match.group(2)
        used = [endpoint for endpoint in PARALLEL_ENDPOINTS if f'"{endpoint}"' in body]
        if len(used) == len(PARALLEL_ENDPOINTS):
            line = text[: match.start()].count("\n") + 1
            findings.append(
                f"{path.name}:{line}: request order asserts both "
                + " and ".join(used)
                + " — issued with `async let`, order is not defined. "
                "Compare Set(requestPaths) and assert only the orderings that hold."
            )
    return findings


def lint_silent_wait(path: Path, text: str) -> list[str]:
    """L2 — a poll loop with no failure on exhaustion."""
    findings = []
    for match in re.finditer(
        r"func (waitUntil\w*)\s*\([^)]*\)[^{]*\{(.*?)\n    \}",
        text,
        re.S,
    ):
        name, body = match.group(1), match.group(2)
        has_loop = re.search(r"for _ in 0\.\.<|while ", body)
        has_fail = re.search(r"XCTFail|XCTAssert", body)
        if has_loop and not has_fail:
            line = text[: match.start()].count("\n") + 1
            findings.append(
                f"{path.name}:{line}: `{name}` loops but never fails on timeout — "
                "the test continues and reports the state it found. Add XCTFail "
                "with the description of what was awaited."
            )
    return findings


RULES = (lint_parallel_order, lint_silent_wait)


def main() -> int:
    ap = argparse.ArgumentParser(description="Test-lint (race-shaped assertions)")
    ap.add_argument("--ci", action="store_true", help="terse output for CI logs")
    args = ap.parse_args()

    files = _test_files()
    if not files:
        print("test-lint: no test sources — skipped")
        return 0

    findings: list[str] = []
    for path in files:
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError as error:
            print(f"test-lint: cannot read {path}: {error}")
            return 2
        for rule in RULES:
            findings.extend(rule(path, text))

    if not findings:
        print(f"test-lint: {len(files)} file(s) clean")
        return 0

    print(f"test-lint: {len(findings)} finding(s)")
    for finding in findings:
        print(f"  {'✗' if not args.ci else '  '} {finding}")
    print()
    print("  These encode a race as a contract. See docs/agents/testing.md.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
