#!/usr/bin/env python3
"""Bump version in VERSION file and sync to README.md header."""
import re, sys

VERSION_FILE = "VERSION"
README_FILE = "README.md"

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

# Update README header
with open(README_FILE) as f:
    readme = f.read()

readme = re.sub(
    r"# Hermes Plus v[\d.]+",
    f"# Hermes Plus v{new_version}",
    readme
)
readme = re.sub(
    r"## 🚀 Why Hermes Plus v[\d.]+",
    f"## 🚀 Why Hermes Plus v{new_version}",
    readme
)

with open(README_FILE, "w") as f:
    f.write(readme)

print(f"v{current} → v{new_version}")
print(f"Files updated: VERSION, README.md")
