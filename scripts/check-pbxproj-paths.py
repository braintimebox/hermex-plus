#!/usr/bin/env python3
"""Check that every .swift file reference in project.pbxproj resolves to a file on disk.

Xcode resolves a PBXFileReference relative to the group that owns it, and a group
carries its own `path`. Registering `Auth/AppLock.swift` inside a group whose path
is already `Auth` produces `Auth/Auth/AppLock.swift`, which Xcode reports only at
build time as "Build input file cannot be found" — after the CI machine has booted
and compiled everything else.

This check runs the same resolution locally, in about a second, so a bad path is
caught before a build is dispatched.

Usage: python3 scripts/check-pbxproj-paths.py [--project <path>]
Exit code 1 when any reference does not resolve.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

GROUP_RE = re.compile(
    r"([0-9A-F]{24}) /\* ([^*/]+) \*/ = \{\s*isa = PBXGroup;\s*children = \(([^)]*)\);([^}]*)\}",
    re.S,
)
FILEREF_RE = re.compile(
    r"([0-9A-F]{24}) /\* ([\w.+ -]+\.swift) \*/ = \{isa = PBXFileReference;[^}]*path = ([^;]+);"
)
PATH_RE = re.compile(r"path = ([^;]+);")


def parse_groups(text: str) -> dict[str, dict]:
    groups: dict[str, dict] = {}
    for match in GROUP_RE.finditer(text):
        gid, name, children, tail = match.groups()
        path_match = PATH_RE.search(tail)
        groups[gid] = {
            "name": name.strip(),
            "path": path_match.group(1).strip('"') if path_match else None,
            "children": children,
        }
    return groups


def group_dirs(groups: dict[str, dict]) -> dict[str, Path]:
    parents: dict[str, str] = {}
    for gid, group in groups.items():
        for other_id, other in groups.items():
            if gid in other["children"]:
                parents[gid] = other_id

    resolved: dict[str, Path] = {}

    def resolve(gid: str, seen: frozenset[str] = frozenset()) -> Path:
        if gid in resolved:
            return resolved[gid]
        if gid in seen:
            return Path(".")
        group = groups[gid]
        parent = parents.get(gid)
        base = resolve(parent, seen | {gid}) if parent else Path(".")
        directory = base / group["path"].strip('"') if group["path"] else base
        resolved[gid] = directory
        return directory

    for gid in groups:
        resolve(gid)
    return resolved


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="HermesMobile.xcodeproj/project.pbxproj")
    parser.add_argument("--root", default=".")
    args = parser.parse_args()

    project = Path(args.project)
    root = Path(args.root).resolve()
    if not project.exists():
        print(f"project not found: {project}", file=sys.stderr)
        return 2

    text = project.read_text()
    groups = parse_groups(text)
    dirs = group_dirs(groups)

    owners = {
        fref: gid for gid, group in groups.items() for fref in re.findall(r"([0-9A-F]{24})", group["children"])
    }

    checked = 0
    missing: list[tuple[str, str]] = []
    for match in FILEREF_RE.finditer(text):
        fref, name, path = match.groups()
        owner = owners.get(fref)
        if owner is None:
            missing.append((name, "<no group>"))
            continue
        resolved = dirs[owner] / path.strip('"')
        checked += 1
        if not (root / resolved).exists():
            missing.append((name, str(resolved)))

    print(f"checked {checked} file reference(s)")
    if missing:
        print(f"UNRESOLVED {len(missing)}:")
        for name, resolved in missing:
            print(f"  {name} -> {resolved}")
        return 1
    print("every reference resolves to a file on disk")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
