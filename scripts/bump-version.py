#!/usr/bin/env python3
"""Bump version in VERSION file and sync to README.md header + pbxproj MARKETING_VERSION.

NOTE: README header no longer carries a version (public file). The canonical
version lives in VERSION + CHANGELOG + pbxproj (CFBundleShortVersionString).
This script bumps VERSION and pbxproj only; CHANGELOG is edited by hand.
"""
import re

VERSION_FILE = "VERSION"
PBXPROJ_FILE = "HermesMobile.xcodeproj/project.pbxproj"

# Read current version
try:
    with open(VERSION_FILE) as f:
        current = f.read().strip()
except FileNotFoundError:
    print("VERSION file not found, creating with 1.4.0")
    current = "1.4.0"

# Parse and bump the patch segment WITH base-10 carry, so the sequence reads
# naturally: ...2.3.8 → 2.3.9 → 2.4.0 → 2.4.1. A version segment is NOT a
# decimal fraction: after x.y.9 the next release is x.y+1.0 (carry), never
# x.y.10 — "2.3.10" reads as "two-three-ten" and breaks the human mental model.
parts = [int(p) for p in current.split(".")] if "." in current else [1, 4, 0]
while len(parts) < 3:
    parts.append(0)

parts[2] += 1  # bump patch
# Carry overflowing segments toward the more significant positions.
for i in reversed(range(1, len(parts))):
    if parts[i] >= 10:
        parts[i] = 0
        parts[i - 1] += 1

new_version = ".".join(str(p) for p in parts)

# Write VERSION
with open(VERSION_FILE, "w") as f:
    f.write(new_version + "\n")

# Sync pbxproj MARKETING_VERSION (CFBundleShortVersionString — shows in app logs)
with open(PBXPROJ_FILE) as f:
    pbxproj = f.read()
pbxproj = re.sub(r"MARKETING_VERSION = [\d.]+;", f"MARKETING_VERSION = {new_version};", pbxproj)
with open(PBXPROJ_FILE, "w") as f:
    f.write(pbxproj)

print(f"v{current} → v{new_version}")
print("Files updated: VERSION, project.pbxproj (MARKETING_VERSION)")
print("REMEMBER: CHANGELOG.md by hand; README header has NO version (public).")
