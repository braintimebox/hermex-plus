#!/usr/bin/env python3
"""Test harness for gate 7. Written as a file because shell printf mangles
Cyrillic and emoji - which produced a false 'still broken' reading."""
import importlib.util, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DOC = ROOT / "HERMES.md"
spec = importlib.util.spec_from_file_location("cdr", ROOT / "scripts" / "check-doc-references.py")
cdr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cdr)

CASES = [
    ("dangling ref fails",          "See scripts/deleted-script.py for details.",        False),
    ("delete prose",                "We need to delete the cache, see scripts/ghost.py.", False),
    ("removed prose",               "We removed the cache, see scripts/ghost2.py.",       False),
    ("RESOLVED unrelated",          "RESOLVED the question, code in scripts/phantom.py.", False),
    ("was deleted bare",            "This file was deleted, new code in scripts/void.py.", False),
    ("has been deleted bare",       "The old helper has been deleted, see scripts/x.py.",  False),
    ("no longer exists bare",       "The helper no longer exists, see scripts/y.py.",      False),
    ("genuine ❌ note passes",      "\u274c scripts/old-tool.py \u2014 \u0423\u0414\u0410\u041b\u0401\u041d 2026-09-11.", True),
    ("genuine label passes",        "\u0423\u0414\u0410\u041b\u0401\u041d: scripts/legacy.py (2026-09-11)", True),
    ("upstream deletion note",      "\u274c docs/agents/gone.md \u2014 deleted by upstream, we accept the deletion.", True),
]

failures = 0
for name, line, should_pass in CASES:
    token = cdr.repo_paths(line)
    absent = all(cdr.is_documented_absent(line, t) for _, t in token) if token else None
    ok = (absent == should_pass) if token else False
    if not ok:
        failures += 1
    found = [t for _, t in token]
    print(f"  [{'PASS' if ok else '*** FAIL ***':12}] {name:26} tok={found} absent={absent} want={should_pass}")

print()
print("ALL CORRECT" if failures == 0 else f"{failures} FAILURES")
sys.exit(1 if failures else 0)
