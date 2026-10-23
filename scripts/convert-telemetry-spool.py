#!/usr/bin/env python3
"""Convert a telemetry spool between format versions. READ-ONLY on the input.

v2 (append-only, from commit 06e9f61): one JSON line per event `{"r": {...}}`
plus one per acknowledgement `{"a": ["id", ...]}`.
v1 (rewrite-per-event, before 06e9f61): one JSON line per live event, no envelope.

The input file is never modified: the result is written to a new path you name.
That matters — the spool can hold the only copy of events that never reached the
server, so a conversion must be additive and verifiable.

Usage:
    python3 scripts/convert-telemetry-spool.py --input SPOOL --output NEW --to v1
    python3 scripts/convert-telemetry-spool.py --input SPOOL --output NEW --to v2

Exit codes: 0 ok, 2 unreadable input, 3 no live events, 4 output exists.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import sys
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_v2(path: Path):
    """Returns (live_items, stats). live_items is an ordered dict id -> record."""
    live: dict[str, dict] = {}
    stats = {"records": 0, "acks": 0, "acked_ids": 0, "corrupt": 0}
    for raw in path.read_text(errors="replace").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            line = json.loads(raw)
        except json.JSONDecodeError:
            stats["corrupt"] += 1
            continue
        if not isinstance(line, dict):
            stats["corrupt"] += 1
            continue
        if isinstance(line.get("r"), dict):
            record = line["r"]
            live[record["id"]] = record
            stats["records"] += 1
        elif isinstance(line.get("a"), list):
            stats["acks"] += 1
            for key in line["a"]:
                if live.pop(key, None) is not None:
                    stats["acked_ids"] += 1
        else:
            stats["corrupt"] += 1
    return live, stats


def read_v1(path: Path):
    live: dict[str, dict] = {}
    stats = {"records": 0, "acks": 0, "acked_ids": 0, "corrupt": 0}
    for raw in path.read_text(errors="replace").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            record = json.loads(raw)
            live[record["id"]] = record
            stats["records"] += 1
        except Exception:
            stats["corrupt"] += 1
    return live, stats


def write_v1(path: Path, live: dict[str, dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for record in live.values():
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def write_v2(path: Path, live: dict[str, dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for record in live.values():
            handle.write(json.dumps({"r": record}, ensure_ascii=False) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--to", choices=("v1", "v2"), required=True)
    args = parser.parse_args()

    source = Path(args.input)
    target = Path(args.output)
    if not source.is_file():
        print(f"input not found: {source}", file=sys.stderr)
        return 2
    if target.exists():
        print(f"refusing to overwrite {target}", file=sys.stderr)
        return 4

    before = digest(source)
    live, stats = read_v2(source) if args.to == "v1" else read_v1(source)
    if not live:
        print("no live events after replay — nothing to write", file=sys.stderr)
        return 3

    (write_v1 if args.to == "v1" else write_v2)(target, live)
    after = digest(source)
    if before != after:
        print("INPUT CHANGED during conversion — aborting", file=sys.stderr)
        return 5

    payload_bytes = sum(len(base64.b64decode(r["json"])) for r in live.values() if "json" in r)
    print(json.dumps({
        "input": str(source),
        "output": str(target),
        "input_sha256": before,
        "live_events": len(live),
        "payload_bytes": payload_bytes,
        "stats": stats,
        "input_unchanged": True,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
