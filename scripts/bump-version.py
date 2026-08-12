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

# Parse and bump patch
parts = current.split(".")
if len(parts) == 3:
    parts[2] = str(int(parts[2]) + 1)
else:
    parts = ["1", "4", "0"]
new_version = ".".join(parts)

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
