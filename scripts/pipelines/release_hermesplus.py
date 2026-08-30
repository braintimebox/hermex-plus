#!/usr/bin/env python3
"""Hermex Plus release pipeline: codechange -> state -> build -> deliver.

One command automates the whole cycle:
  bump version, mark fixed items closed in the data-driven state, regenerate the
  snapshot, run the release gate, push (triggers build-ipa.yml), wait for the
  build, download the .ipa into ~/workspace, and print delivery links.

Usage:
  python3 scripts/pipelines/release_hermesplus.py --next 3.4.5 --close 1 7 \
      --note "sizeChangeAnchor inactive during no-streaming" [--dry-run]

  --next N      new version (default: bump patch from VERSION)
  --close ID..  item ids to mark closed (docs/hermesplus-status.yaml)
  --note TEXT   release note, put in CHANGELOG + item note (default: git msg)
  --dry-run     prepare everything, show the plan, do NOT push/build
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]              # repo root (hermex-plus)
WORKS = Path(os.environ.get("HERMEX_WORKSPACE", str(Path.home() / "workspace")))
STATUS = ROOT / "docs" / "hermesplus-status.yaml"
SNAPSHOT = ROOT / "docs" / "project-snapshot.md"
VERSION = ROOT / "VERSION"
CHANGELOG = ROOT / "CHANGELOG.md"
PBXPROJ = ROOT / "HermesMobile.xcodeproj" / "project.pbxproj"
WEBUI_BASE = os.environ.get("HERMES_WEBUI_BASE", "").rstrip("/")


def sh(cmd: list[str], check: bool = True) -> str:
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"FAILED: {cmd}\n{r.stderr[-2000:]}")
    return r.stdout.strip()


def current_version() -> str:
    return VERSION.read_text(encoding="utf-8").strip()


def bump_patch(v: str) -> str:
    maj, mi, pa = v.split(".")
    return f"{maj}.{mi}.{int(pa) + 1}"


def write_version(new_v: str) -> None:
    VERSION.write_text(new_v + "\n", encoding="utf-8")
    pbx = PBXPROJ.read_text(encoding="utf-8")
    old_v = current_version()
    PBXPROJ.write_text(
        pbx.replace(f"MARKETING_VERSION = {old_v};", f"MARKETING_VERSION = {new_v};"), encoding="utf-8"
    )


def prepend_changelog(new_v: str, note: str) -> None:
    header = f"## {new_v} — {note}\n"
    body = CHANGELOG.read_text(encoding="utf-8")
    CHANGELOG.write_text(header + "\n" + body, encoding="utf-8")


def update_status(version: str, close_ids: list[int], note: str) -> None:
    import yaml

    data = yaml.safe_load(STATUS.read_text(encoding="utf-8")) or {}
    items = data.setdefault("items", [])
    for it in items:
        if int(it.get("id", -1)) in close_ids:
            it["status"] = "closed"
            it["closed_in"] = version
            it["note"] = f"Закрыто в {version}: {note}"
    # keep closed_note in sync
    extra = [f"№{it['id']} {it['title']} ({it.get('closed_in','')})" for it in items if it.get("status") == "closed"]
    data["version"] = version
    data["closed_note"] = "Закрыто недавно: " + ", ".join(extra)
    STATUS.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")


def regenerate_snapshot() -> None:
    sh(["python3", "scripts/project_snapshot.py"], check=False)


def release_gate() -> None:
    sh(["python3", "scripts/release-check.py", "--allow-untagged"])


def git_commit_push(msg: str) -> None:
    sh(["git", "add", "-A"])
    sh(["git", "commit", "-q", "-m", msg])
    sh(["git", "push", "origin", "main"])


def wait_build() -> str:
    rid = sh(["gh", "run", "list", "--workflow=build-ipa.yml", "--branch=main",
              "--limit=1", "--json", "databaseId", "--jq", ".[0].databaseId"])
    for _ in range(26):  # ~25s * 26 ≈ 11 min
        st = sh(["gh", "run", "view", rid, "--json", "status,conclusion",
                 "--jq", r'\(.status) \(.conclusion // "")'])
        print(f"  build: {st}")
        if st.startswith("completed"):
            if not st.endswith("success"):
                sys.exit("BUILD FAILED — see: https://github.com/braintimebox/hermex-plus/actions/runs/" + rid)
            return rid
        time.sleep(25)
    sys.exit("build timed out waiting")


def download_ipa(rid: str, version: str) -> tuple[Path, str]:
    tmp = Path("/tmp") / f"hlp-{rid}"
    sh(["rm", "-rf", str(tmp)])
    tmp.mkdir(parents=True, exist_ok=True)
    sh(["gh", "run", "download", rid, "-D", str(tmp)])
    ipas = list(tmp.rglob(f"HermesPlus-{version}.ipa"))
    if not ipas:
        sys.exit("no .ipa in artifact")
    src = ipas[0]
    dst = WORKS / src.name
    dst.write_bytes(src.read_bytes())
    digest = hashlib.sha256(dst.read_bytes()).hexdigest()
    return dst, digest


def emit(dst: Path, digest: str, rid: str, version: str) -> None:
    name = dst.name
    url = f"{WEBUI_BASE}/api/file/raw?path={name}"
    print("\n=== DELIVER ===")
    print(f"  ipa : {dst}")
    print(f"  sha256 : {digest}")
    print(f"  in-app : {url}      # paste in WebUI file browser / open")
    print(f"  artifact: https://github.com/braintimebox/hermex-plus/actions/runs/{rid}")
    print(f"  version: {version}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--next", default=None)
    ap.add_argument("--close", type=int, nargs="+", default=[])
    ap.add_argument("--note", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    cur = current_version()
    nxt = a.next or bump_patch(cur)
    note = a.note or f"release {nxt}"

    print(f"current={cur} next={nxt} close={a.close} dry_run={a.dry_run}")
    if a.dry_run:
        print("PLAN: bump -> close %s -> snapshot -> gate -> push -> build -> download -> deliver" % a.close)
        return 0

    write_version(nxt)
    prepend_changelog(nxt, note)
    update_status(nxt, a.close, note)
    regenerate_snapshot()
    release_gate()
    git_commit_push(f"{nxt}: {note} (fixed #{','.join(map(str, a.close))})")

    rid = wait_build()
    dst, digest = download_ipa(rid, nxt)
    emit(dst, digest, rid, nxt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
