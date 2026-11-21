#!/usr/bin/env python3
"""Синхронизация VERSION из единого источника Config/Version.xcconfig.

Зачем: версия раньше жила в трёх местах — VERSION (читает CI), 16 копий
MARKETING_VERSION и 8 копий CURRENT_PROJECT_VERSION. Теперь источник один:
Config/Version.xcconfig. Этот скрипт только зеркалит APP_VERSION в VERSION,
чтобы CI и старые скрипты продолжали работать без изменений.

Использование:
    python3 scripts/sync-version.py            # записать VERSION из xcconfig
    python3 scripts/sync-version.py --check    # только проверить, exit 1 при расхождении
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION_XCCONFIG = ROOT / "Config" / "Version.xcconfig"
VERSION_FILE = ROOT / "VERSION"

SEMVER = re.compile(r"^\d+\.\d+\.\d+$")


def read_xcconfig(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or "=" not in stripped:
            continue
        key, _, value = stripped.partition("=")
        values[key.strip()] = value.strip().strip('"')
    return values


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="не писать, только сверить")
    args = ap.parse_args()

    cfg = read_xcconfig(VERSION_XCCONFIG)
    version = cfg.get("APP_VERSION", "")
    build = cfg.get("APP_BUILD", "")

    problems: list[str] = []
    if not SEMVER.match(version):
        problems.append(f"APP_VERSION {version!r} is not MAJOR.MINOR.PATCH")
    if not build.isdigit():
        problems.append(f"APP_BUILD {build!r} is not numeric")
    if problems:
        for p in problems:
            print(f"ERROR: {p}", file=sys.stderr)
        return 1

    mirror = VERSION_FILE.read_text(encoding="utf-8").strip() if VERSION_FILE.exists() else ""

    if args.check:
        if mirror != version:
            print(f"ERROR: VERSION is {mirror!r} but Config/Version.xcconfig says {version!r}",
                  file=sys.stderr)
            return 1
        print(f"ok version={version} build={build}")
        return 0

    if mirror != version:
        VERSION_FILE.write_text(version + "\n", encoding="utf-8")
        print(f"VERSION updated: {mirror or '<none>'} -> {version}")
    else:
        print(f"VERSION already at {version}")
    print(f"version={version} build={build}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
