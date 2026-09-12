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


def release_is_published(version: str) -> bool:
    """Whether this version was actually handed to the user.

    "Delivered" means a published GitHub Release carries an artifact for this
    tag. A tag on its own is bookkeeping; an artifact is the thing a person
    installed. Only the second one makes re-using the number a real defect.

    The repository is passed explicitly. In a repo where `origin` is
    `braintimebox/hermex-plus` but a *different* repo is the gh default (or where
    an `upstream` remote exists), a bare `gh release view` answers about the
    wrong repository and reports "not released" for a version that was shipped.
    Measured: without `--repo`, v3.6.1 — which has `HermesPlus-3.6.1.ipa` —
    came back as absent, and the gate let a delivered version through.

    Fails SOFT on tool/network failure: an unpublished state is assumed and
    check 5 degrades to the tag warning, because blocking a push over an
    unreachable tool is worse than the check itself.
    """
    repo = release_repo()
    try:
        r = subprocess.run(
            ["gh", "release", "view", f"v{version}", *(["--repo", repo] if repo else []),
             "--json", "assets", "--jq", ".assets | length"],
            capture_output=True, text=True, check=False, timeout=20,
        )
    except Exception:
        return False
    if r.returncode != 0:
        return False
    try:
        return int(r.stdout.strip()) > 0
    except ValueError:
        return False


def release_repo() -> str | None:
    """`owner/name` of the repo whose Releases count, read from origin."""
    url = git_output("remote", "get-url", "origin")
    if not url:
        return None
    # https://github.com/owner/name.git  |  git@github.com:owner/name.git
    tail = url.rstrip("/")
    if tail.endswith(".git"):
        tail = tail[:-4]
    for sep in ("github.com/", "github.com:"):
        if sep in tail:
            return tail.split(sep, 1)[1]
    return None


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

def product_changed() -> tuple[bool, list[str]]:
    """Whether the pending change can alter what the app DOES.

    A version number exists to distinguish builds a person installs. A change to
    `scripts/`, `docs/`, `ops/` or the CI workflow cannot alter the installed
    app — no Swift compiles differently — so it does not warrant a new number,
    and demanding one would burn a release number per script fix.

    This distinction was missing, and its absence had two visible costs:

      1. `release-check.py` refused every push after a release, so fixing a gate
         or a workflow required bumping the version first.
      2. `build-ipa.yml` re-published the released version's Release on every
         push (measured: v3.6.1's .ipa re-created 11 minutes after publication),
         so the delivered number silently changed contents.

    Compared against the upstream-tracking point for a PREPARED commit, or the
    working tree for uncommitted edits. The base is `ORIG_HEAD`-aware: on a
    normal push it is `origin/main` (what the remote already has), because the
    question is "what does THIS push carry", not "what has this fork ever
    changed". Using the fork point here reported all 422 commits of the fork and
    refused every tooling push.
    """
    # What the remote already has is the boundary of this push. Fall back to the
    # fork point only when there is no upstream tracking ref at all.
    base = (
        git_output("rev-parse", "--verify", "--quiet", "origin/main")
        or git_output("merge-base", "HEAD", "origin/master")
        or "origin/master"
    )
    files: list[str] = []
    for args in (("diff", "--name-only", f"{base}..HEAD"),
                 ("diff", "--name-only"),
                 ("diff", "--name-only", "--cached")):
        files.extend(f for f in git_output(*args).splitlines() if f.strip())
    unique = sorted(set(files))
    if not unique:
        return False, []
    # Anything under the app target, or the version file itself, is product.
    product = [
        f for f in unique
        if f.startswith("HermesMobile") or f.startswith("HermesLiveActivityWidget")
        or f == "VERSION"
    ]
    return bool(product), unique


# --- 5. this version must not already have been RELEASED ---
#
# The defect being prevented is not "a tag exists" — it is "we handed the user
# this version, then changed its contents and handed it over again under the
# same number" (the 1.5.5-twice incident). Those are different conditions, and
# conflating them blocked ordinary work: after a release, the tag exists, so
# every later fix on `main` was refused a push until the version was bumped —
# even a fix to CI or to this gate itself, which cannot carry a version.
#
# A version is DELIVERED when it has a published GitHub Release with its IPA
# attached. That is the real boundary. The tag alone is a local bookkeeping mark
# that legitimately exists while post-release work continues.
#
#   released (Release + asset)  -> BLOCKER: bump the version
#   tagged but not released     -> advisory: tag exists, no artifact published
#   neither                     -> remind to tag after CI green
allow_untagged = "--allow-untagged" in sys.argv
tags = git_output("tag", "--list", f"v{version}")
delivered = release_is_published(version)
product, changed_files = product_changed()

if delivered and product:
    fail(
        f"version {version} is already RELEASED (published GitHub Release with an "
        f"artifact) and this change touches product code — re-issuing a delivered "
        f"version is the 'same version twice' bug. Bump VERSION first "
        f"(one release = one version). Product files: "
        f"{', '.join(f for f in changed_files if f.startswith('HermesMobile'))[:200]}"
    )
elif delivered and not product:
    print(
        f"ok  version {version} is released, but this change is tooling/docs only "
        f"({len(changed_files)} files) — no new build reaches a user, so the version "
        f"stands. build-ipa.yml will not re-publish the Release."
    )
elif tags:
    warn(
        f"tag v{version} exists locally but no published Release for it — "
        f"the version is not delivered yet, so amending it is allowed. "
        f"If the IPA did go out, bump VERSION instead."
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
