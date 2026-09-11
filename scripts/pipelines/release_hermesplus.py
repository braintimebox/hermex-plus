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

SAFETY
    Releasing is never implicit. `release` requires an explicit subcommand or
    an explicit --next/--close/--note flag. A bare invocation (no arguments)
    prints help and exits — it does NOT release.

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
GITHOOKS_DIR = ".githooks"
HOOK_REL = f"{GITHOOKS_DIR}/pre-push"
WEBUI_BASE = os.environ.get("HERMES_WEBUI_BASE", "").rstrip("/")

# gh resolves the default repo from the git remote; our remote points at
# upstream sometimes, and `gh run ...` then 404s. Always be explicit.
OUR_REPO = "braintimebox/hermex-plus"


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
    """Write the version to every place that has to agree, in one shot.

    MARKETING_VERSION is the human-facing version (3.6.2). CURRENT_PROJECT_VERSION
    is the build number iOS compares when installing over an existing app — it must
    move forward on every release or the update can be rejected as "same build".
    Upstream's own AGENTS.md says a unique YYYYMMDDHHMM value each time; this script
    previously left it pinned at 1 forever, which is the defect this fixes.
    """
    import datetime as _dt

    old_v = current_version()
    VERSION.write_text(new_v + "\n", encoding="utf-8")

    build_no = _dt.datetime.now().strftime("%Y%m%d%H%M")
    pbx = PBXPROJ.read_text(encoding="utf-8")

    before_marketing = pbx.count(f"MARKETING_VERSION = {old_v};")
    pbx = pbx.replace(f"MARKETING_VERSION = {old_v};", f"MARKETING_VERSION = {new_v};")

    # Every CURRENT_PROJECT_VERSION line is rewritten to the same new build number,
    # preserving indentation and the trailing semicolon.
    before_build = len(re.findall(r"CURRENT_PROJECT_VERSION = \d+;", pbx))
    pbx = re.sub(r"CURRENT_PROJECT_VERSION = \d+;",
                 f"CURRENT_PROJECT_VERSION = {build_no};", pbx)

    PBXPROJ.write_text(pbx, encoding="utf-8")

    if before_marketing == 0:
        print(f"  ⚠ MARKETING_VERSION {old_v} not found in pbxproj — nothing replaced")
    if before_build == 0:
        print("  ⚠ CURRENT_PROJECT_VERSION not found in pbxproj — nothing replaced")
    print(f"  version {old_v} → {new_v} · build number → {build_no}"
          f" ({before_build} target(s))")


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
    """Stage only what a release is allowed to change, then push.

    `git add -A` used to stage every untracked file in the tree — that is how an
    unrelated file (HERMES.md) ended up inside a release commit by accident. A
    release touches a known, fixed set of paths, so stage exactly those.
    """
    tracked = [
        "VERSION",
        "CHANGELOG.md",
        "README.md",
        "docs/project-snapshot.md",
        "docs/hermesplus-status.yaml",
        "HermesMobile.xcodeproj/project.pbxproj",
    ]
    existing = [p for p in tracked if (ROOT / p).exists()]
    sh(["git", "add", "--"] + existing)
    # New/changed files under scripts/ and .github/ are part of the tooling and
    # must travel with the release, but only tracked-and-modified ones: -u never
    # picks up untracked junk.
    sh(["git", "add", "-u", "--", "scripts", ".github"])
    print(f"  staged: {' '.join(existing)} + scripts/ + .github/")
    sh(["git", "commit", "-q", "-m", msg])
    sh(["git", "push", "origin", "main"])


def wait_build() -> str:
    rid = sh(["gh", "run", "list", "--repo", OUR_REPO, "--workflow=build-ipa.yml",
              "--branch=main", "--limit=1", "--json", "databaseId",
              "--jq", ".[0].databaseId"])
    for _ in range(26):  # ~25s * 26 ≈ 11 min
        st = sh(["gh", "run", "view", rid, "--repo", OUR_REPO,
                 "--json", "status,conclusion",
                 "--jq", r'\(.status) \(.conclusion // "")'])
        print(f"  build: {st}")
        if st.startswith("completed"):
            if not st.endswith("success"):
                sys.exit(f"BUILD FAILED — see: https://github.com/{OUR_REPO}"
                         f"/actions/runs/{rid}")
            return rid
        time.sleep(25)
    sys.exit("build timed out waiting")


def download_ipa(rid: str, version: str) -> tuple[Path, str]:
    tmp = Path("/tmp") / f"hlp-{rid}"
    sh(["rm", "-rf", str(tmp)])
    tmp.mkdir(parents=True, exist_ok=True)
    sh(["gh", "run", "download", rid, "--repo", OUR_REPO, "-D", str(tmp)])
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
    """Point git at the versioned hook directory.

    The hook lives at .githooks/pre-push inside the repository, so it travels
    with the repo (clone, move, reinstall). Writing into .git/hooks instead keeps
    the gate outside version control, where it silently disappears on a fresh
    clone — the push protection is then gone and nothing says so.
    """
    hook = ROOT / HOOK_REL
    if not hook.exists():
        print(f"✗ {HOOK_REL} missing from the repository — cannot install")
        return 1
    hook.chmod(0o755)
    sh(["git", "config", "core.hooksPath", GITHOOKS_DIR])
    print(f"hook path  → core.hooksPath = {GITHOOKS_DIR}")
    print(f"gate       → {HOOK_REL} (versioned, travels with the repo)")
    print("every `git push` now runs scripts/pipeline-precheck.py")
    print()
    print("note: core.hooksPath is local git config — run this once per clone.")
    return 0


# --- ops: host services (see ops/README.md) ---------------------------------

OPS_DIR = ROOT / "ops" / "hermex-logs"
SERVICE_INSTALL_DIR = Path.home() / ".hermes" / "_projects" / "hermex-logs"
SYSTEMD_USER_DIR = Path.home() / ".config" / "systemd" / "user"
SERVICE_NAME = "hermex-logs.service"


def cmd_install_server(target_dir: Path | None = None) -> int:
    """Install or update the logs endpoint on this host.

    Source of truth is ops/hermex-logs/ in this repository. The running copy
    under ~/.hermes and the unit under ~/.config/systemd/user are install
    targets — an earlier revision of this service existed only as those two
    files, in one copy, untracked, and nobody noticed when it died.
    """
    install_dir = (target_dir or SERVICE_INSTALL_DIR).expanduser()
    source = OPS_DIR / "server.py"
    template = OPS_DIR / f"{SERVICE_NAME}.template"

    for required in (source, template):
        if not required.exists():
            print(f"✗ missing {required.relative_to(ROOT)} — cannot install")
            return 1

    install_dir.mkdir(parents=True, exist_ok=True)
    script = install_dir / "server.py"
    script.write_bytes(source.read_bytes())
    print(f"server     → {script}")

    SYSTEMD_USER_DIR.mkdir(parents=True, exist_ok=True)
    unit_path = SYSTEMD_USER_DIR / SERVICE_NAME
    unit_path.write_text(
        template.read_text(encoding="utf-8").replace("{{INSTALL_DIR}}", str(install_dir)),
        encoding="utf-8",
    )
    print(f"unit       → {unit_path}")

    for cmd in (
        ["systemctl", "--user", "daemon-reload"],
        ["systemctl", "--user", "enable", SERVICE_NAME],
        ["systemctl", "--user", "restart", SERVICE_NAME],
    ):
        sh(cmd, check=False)

    time.sleep(1)
    active = sh(["systemctl", "--user", "is-active", SERVICE_NAME], check=False).strip()
    print(f"service    → {active or 'unknown'}")
    health = sh(["curl", "-s", "--max-time", "5", "http://127.0.0.1:8912/health"],
                check=False).strip()
    print(f"health     → {health or '(no response)'}")
    if active != "active":
        print("\nservice is not running — check: journalctl --user -u hermex-logs -n 50")
        return 1
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
    hook_ok = (ROOT / HOOK_REL).exists() and git("config", "core.hooksPath") == GITHOOKS_DIR
    print(f"pre-push  {'installed' if hook_ok else 'NOT INSTALLED  ← run: … install'}")

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
    sp = sub.add_parser("install-server", help="install/update the host logs endpoint")
    sp.add_argument("--dir", type=Path, default=None,
                    help="install directory (default: ~/.hermes/_projects/hermex-logs)")
    sub.add_parser("check", help="run the local gates")
    sub.add_parser("status", help="pipeline + upstream status")
    sub.add_parser("sync", help="upstream drift and merge plan")

    p = sub.add_parser("release", help="full release cycle")
    p.add_argument("--next", default=None, help="new version (default: bump patch)")
    p.add_argument("--close", type=int, nargs="+", default=[],
                   help="item ids to mark closed in status.yaml")
    p.add_argument("--note", default="")
    p.add_argument("--dry-run", action="store_true")

    # No arguments → help. Releasing is never implicit.
    if len(sys.argv) == 1:
        ap.print_help()
        print()
        print("Releasing is never implicit — use: release --next X.Y.Z --note \"…\"")
        return 0

    if sys.argv[1] == "release":
        a = ap.parse_args()
    elif sys.argv[1] in {"install", "install-server", "check", "status", "sync"}:
        a = ap.parse_args()
    elif sys.argv[1] in {"-h", "--help"}:
        a = ap.parse_args()
    else:
        # Legacy flag form: `… --next 3.7.0 --close 1 --note "x"` (no subcommand).
        a = ap.parse_args(["release"] + sys.argv[1:])

    if a.cmd == "install":
        return cmd_install()
    if a.cmd == "install-server":
        return cmd_install_server(a.dir)
    if a.cmd == "check":
        return cmd_check()
    if a.cmd == "status":
        return cmd_status()
    if a.cmd == "sync":
        return cmd_sync()
    if a.cmd == "release":
        return cmd_release(a.next, a.close, a.note, a.dry_run)
    ap.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
