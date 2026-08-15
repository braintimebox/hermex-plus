#!/usr/bin/env python3
"""Pre-push release guard for Hermex Plus.

Read-only: verifies the repo is in a consistent release state before a push.
Never mutates anything, never bumps, never commits. Exit 0 = ready to push;
exit 1 = a BLOCKER (fix before pushing); warnings are advisory.

Checks (see the hermex-plus skill, "Invariants" rule #3):
  1. VERSION exists and is a semver X.Y.Z
  2. CHANGELOG.md top section == VERSION
  3. project.pbxproj MARKETING_VERSION == VERSION (all occurrences)
  4. README.md header carries NO version (public file)
  5. git tag v<VERSION> must NOT already exist (re-issuing an already-tagged
     version is the "same version twice" bug)

Usage:
  python3 scripts/release-check.py            # from repo root
  python3 scripts/release-check.py --allow-untagged   # skip check 5 (pre-first-release)
"""

import re
import subprocess
import sys

VERSION_FILE = "VERSION"
CHANGELOG_FILE = "CHANGELOG.md"
PBXPROJ_FILE = "HermesMobile.xcodeproj/project.pbxproj"
README_FILE = "README.md"

SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")

errors = []
warnings = []


def fail(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def read(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def git_output(*args: str) -> str:
    return subprocess.run(
        ["git", *args], capture_output=True, text=True, check=False
    ).stdout.strip()


# --- 1. VERSION ---
try:
    version = read(VERSION_FILE).strip()
except FileNotFoundError:
    print(f"BLOCKER: {VERSION_FILE} not found")
    sys.exit(1)

if not SEMVER_RE.match(version):
    fail(f"{VERSION_FILE} = {version!r} is not X.Y.Z")

# --- 2. CHANGELOG top section ---
try:
    changelog = read(CHANGELOG_FILE)
    m = re.search(r"^##\s+(\d+\.\d+\.\d+)", changelog, flags=re.MULTILINE)
    top = m.group(1) if m else None
except FileNotFoundError:
    top = None
    fail(f"{CHANGELOG_FILE} not found")

if top is None:
    fail(f"{CHANGELOG_FILE} has no '## X.Y.Z' section")
elif top != version:
    fail(f"CHANGELOG top section {top} != VERSION {version} (forgot CHANGELOG entry?)")
else:
    print(f"ok  CHANGELOG top == {version}")

# --- 3. pbxproj MARKETING_VERSION ---
try:
    pbx = read(PBXPROJ_FILE)
    mv_versions = re.findall(r"MARKETING_VERSION = ([\d.]+);", pbx)
except FileNotFoundError:
    mv_versions = []
    fail(f"{PBXPROJ_FILE} not found")

if not mv_versions:
    fail(f"{PBXPROJ_FILE}: no MARKETING_VERSION found")
else:
    unique = set(mv_versions)
    if unique != {version}:
        fail(
            f"pbxproj MARKETING_VERSION {sorted(unique)} != VERSION {version} "
            f"(stale build version in logs)"
        )
    else:
        print(f"ok  MARKETING_VERSION == {version} ({len(mv_versions)} occurrences)")

# --- 4. README header has no version ---
try:
    readme = read(README_FILE)
    # The h1 line — first '# ' heading in the file.
    h1 = re.search(r"^#\s+(.+)$", readme, flags=re.MULTILINE)
    heading = h1.group(1) if h1 else ""
    if re.search(r"\bv?\d+\.\d+\.\d+\b", heading):
        fail(f"README header '{heading}' carries a version (public file must not)")
    else:
        print(f"ok  README header has no version ('{heading}')")
except FileNotFoundError:
    warn(f"{README_FILE} not found")

# --- 5. git tag v<VERSION> must not already exist ---
allow_untagged = "--allow-untagged" in sys.argv
tags = git_output("tag", "--list", f"v{version}")
if tags:
    fail(
        f"git tag v{version} already exists — re-issuing an already-tagged version. "
        f"Bump VERSION first (one release = one version)."
    )
elif not allow_untagged:
    warn(
        f"no git tag v{version} yet — remember to tag after CI green: "
        f"`git tag v{version} && git push origin v{version}`"
    )
else:
    print(f"ok  no git tag v{version} (allowed: --allow-untagged)")

# --- report ---
if warnings:
    print("\nWARNINGS:")
    for w in warnings:
        print(f"  - {w}")

if errors:
    print("\nBLOCKERS:")
    for e in errors:
        print(f"  - {e}")
    print("\nPush blocked. Fix the blockers above, then re-run.")
    sys.exit(1)

print("\nRelease state OK — ready to push.")
sys.exit(0)
