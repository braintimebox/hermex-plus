#!/usr/bin/env python3
"""Hermex Plus pipeline — the ONE entrypoint for the whole release lifecycle.

WHY ONE FILE
    This used to be split across scripts/pipeline (fast ops) and
    scripts/pipelines/release_hermesplus.py (full cycle), plus a separate
    bump-version.py that silently skipped the CHANGELOG. Two tools for one job
    meant the wrong one got used. They are merged here.

COMMANDS
    status    where we are: version, branch, gate state, upstream drift
    check     run the local gates (5 checks) without releasing
    release   bump -> changelog -> close items -> snapshot -> gate -> push
              -> wait for CI -> download IPA -> print delivery links
    sync      upstream drift and merge plan
    install   install the pre-push gate (not versioned in git)

WHY THE GATE MATTERS
    `git push` is protected by scripts/pipeline-precheck.py once installed.
    The pipeline does not "remember" to check anything — the hook enforces it.

MERGE, NOT REBASE
    Upstream sync uses `merge`. `rebase` dies on the 5th of our ~376 commits,
    inside CHANGELOG bookkeeping (158 of our edits vs 3 of theirs). See
    scripts/sync-upstream.
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
HOOK = ROOT / ".git" / "hooks" / "pre-push"
WEBUI_BASE = os.environ.get("HERMES_WEBUI_BASE", "").rstrip("/")


def sh(cmd: list[str], check: bool = True) -> str:
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"FAILED: {cmd}\n{r.stderr[-2000:]}")
    return r.stdout.strip()


def git(*args: str, check: bool = True) -> str:
    return sh(["git", *args], check=check)


def current_version() -> str:
    return VERSION.read_text(encoding="utf-8").strip()


def bump_patch(v: str) -> str:
    maj, mi, pa = v.split(".")
    return f"{maj}.{mi}.{int(pa) + 1}"


def write_version(new_v: str) -> None:
    old_v = current_version()
    VERSION.write_text(new_v + "\n", encoding="utf-8")
    pbx = PBXPROJ.read_text(encoding="utf-8")
    PBXPROJ.write_text(
        pbx.replace(f"MARKETING_VERSION = {old_v};", f"MARKETING_VERSION = {new_v};"),
        encoding="utf-8",
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
    extra = [
        f"№{it['id']} {it['title']} ({it.get('closed_in','')})"
        for it in items
        if it.get("status") == "closed"
    ]
    data["version"] = version
    data["closed_note"] = "Закрыто недавно: " + ", ".join(extra)
    STATUS.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False),
                      encoding="utf-8")


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
                sys.exit("BUILD FAILED — see: https://github.com/braintimebox/"
                         "hermex-plus/actions/runs/" + rid)
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
    url = f"{WEBUI_BASE}/api/file/raw?path={name}" if WEBUI_BASE else "(set HERMES_WEBUI_BASE)"
    print("\n=== DELIVER ===")
    print(f"  ipa : {dst}")
    print(f"  sha256 : {digest}")
    print(f"  in-app : {url}")
    print(f"  release: https://github.com/braintimebox/hermex-plus/releases/latest")
    print(f"  artifact: https://github.com/braintimebox/hermex-plus/actions/runs/{rid}")
    print(f"  version: {version}")


# --- fast operations (merged from scripts/pipeline) --------------------------

HOOK_BODY = """#!/bin/sh
# Hermex Plus pipeline gate — installed by scripts/pipelines/release_hermesplus.py install
# Blocks the push when a release invariant is broken.
exec python3 "$(git rev-parse --show-toplevel)/scripts/pipeline-precheck.py"
"""


def cmd_install() -> int:
    hooks_dir = ROOT / ".git" / "hooks"
    hooks_dir.mkdir(parents=True, exist_ok=True)
    HOOK.write_text(HOOK_BODY)
    HOOK.chmod(0o755)
    print(f"installed pre-push gate → {HOOK.relative_to(ROOT)}")
    print("every `git push` now runs scripts/pipeline-precheck.py")
    print()
    print("note: .git/hooks is not versioned. Re-run after a fresh clone.")
    return 0


def cmd_check() -> int:
    r = subprocess.run([sys.executable, str(ROOT / "scripts" / "pipeline-precheck.py")],
                       cwd=ROOT, capture_output=True, text=True)
    print(r.stdout.rstrip())
    return r.returncode


def cmd_status() -> int:
    print("=" * 66)
    print("HERMEX PLUS — PIPELINE STATUS")
    print("=" * 66)
    print(f"version   {current_version()}")
    print(f"branch    {git('branch', '--show-current')}")
    print(f"head      {git('log', '--oneline', '-1')}")
    print(f"pre-push  {'installed' if HOOK.exists() else 'NOT INSTALLED  ← run: … install'}")

    su = ROOT / "scripts" / "sync-upstream"
    if su.exists():
        r = subprocess.run([sys.executable, str(su), "--status"],
                           cwd=ROOT, capture_output=True, text=True)
        for line in r.stdout.strip().splitlines():
            print(line)

    dirty = [l for l in git("status", "--porcelain").splitlines() if l.strip()]
    print(f"worktree  {len(dirty)} changed path(s)")
    for l in dirty:
        print(f"          {l}")
    return 0


def cmd_sync() -> int:
    su = ROOT / "scripts" / "sync-upstream"
    if not su.exists():
        print("scripts/sync-upstream missing")
        return 1
    r = subprocess.run([sys.executable, str(su), "--plan"],
                       cwd=ROOT, capture_output=True, text=True)
    print(r.stdout.rstrip())
    return r.returncode


def cmd_release(next_v: str | None, close_ids: list[int], note: str,
                dry_run: bool) -> int:
    cur = current_version()
    nxt = next_v or bump_patch(cur)
    note = note or f"release {nxt}"

    print(f"current={cur} next={nxt} close={close_ids} dry_run={dry_run}")
    if dry_run:
        print("PLAN: bump -> changelog -> close %s -> snapshot -> gate -> push "
              "-> build -> download -> deliver" % close_ids)
        return 0

    write_version(nxt)
    prepend_changelog(nxt, note)
    update_status(nxt, close_ids, note)
    regenerate_snapshot()
    release_gate()
    where = ",".join(map(str, close_ids))
    git_commit_push(f"{nxt}: {note}" + (f" (fixed #{where})" if where else ""))

    rid = wait_build()
    dst, digest = download_ipa(rid, nxt)
    emit(dst, digest, rid, nxt)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Hermex Plus pipeline — the single release entrypoint")
    sub = ap.add_subparsers(dest="cmd")

    sub.add_parser("install", help="install the pre-push gate")
    sub.add_parser("check", help="run the local gates")
    sub.add_parser("status", help="pipeline + upstream status")
    sub.add_parser("sync", help="upstream drift and merge plan")

    p = sub.add_parser("release", help="full release cycle")
    p.add_argument("--next", default=None, help="new version (default: bump patch)")
    p.add_argument("--close", type=int, nargs="+", default=[],
                   help="item ids to mark closed in status.yaml")
    p.add_argument("--note", default="")
    p.add_argument("--dry-run", action="store_true")

    # No subcommand → behave like the old script (release with flags).
    if len(sys.argv) > 1 and sys.argv[1] in {"install", "check", "status", "sync"}:
        a = ap.parse_args()
    elif len(sys.argv) > 1 and sys.argv[1] == "release":
        a = ap.parse_args()
    else:
        a = ap.parse_args(["release"] + sys.argv[1:])

    if a.cmd == "install":
        return cmd_install()
    if a.cmd == "check":
        return cmd_check()
    if a.cmd == "status":
        return cmd_status()
    if a.cmd == "sync":
        return cmd_sync()
    if a.cmd == "release":
        return cmd_release(a.next, a.close, a.note, a.dry_run)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
