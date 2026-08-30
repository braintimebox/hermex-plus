#!/usr/bin/env python3
"""Hermex Plus — SINGLE fresh project snapshot (deterministic, no LLM).

ONE source of truth. Run this at the START of any work session, then read
docs/project-snapshot.md. It regenerates everything from real git state so the
state can never be stale:

  - where we are   (branch / HEAD / VERSION / recent commits)  ← from git
  - what's critical to fix  (prioritized open tracks)          ← maintained block
  - project origin (fork of a heavy original)                  ← one-liner
  - sizes          (lines / IPA)                               ← counted live

Not cron. Not release-triggered. Trigger = the agent starting work.

Usage:
  cd ~/Projects/hermex-plus
  python3 scripts/project_snapshot.py
"""

from __future__ import annotations

import datetime
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT = ROOT / "docs" / "project-snapshot.md"
UPSTREAM_ROOT = Path("/tmp/hermex-orig-compare")  # clone of uzairansaruzi/hermex
UPSTREAM_GIT = "https://github.com/uzairansaruzi/hermex.git"


def git(*args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(ROOT), *args], capture_output=True, text=True, check=False
    ).stdout.strip()


def count_swift_lines(base: Path) -> tuple[int, int]:
    files = 0
    lines = 0
    if not base.exists():
        return 0, 0
    for root, _, fnames in os.walk(base):
        if ".git" in root:
            continue
        for fn in fnames:
            if not fn.endswith(".swift"):
                continue
            p = Path(root) / fn
            try:
                lines += sum(1 for _ in open(p, encoding="utf-8", errors="ignore"))
                files += 1
            except OSError:
                pass
    return files, lines


def ensure_upstream() -> Path:
    if UPSTREAM_ROOT.exists() and any(UPSTREAM_ROOT.iterdir()):
        return UPSTREAM_ROOT
    subprocess.run(["git", "clone", "--quiet", UPSTREAM_GIT, str(UPSTREAM_ROOT)],
                   check=False)
    return UPSTREAM_ROOT


def latest_ipa_size() -> str:
    cands = sorted(glob_ipas())
    if not cands:
        return "?"
    sz = os.path.getsize(cands[-1]) / 1e6
    return f"{sz:.0f} MB ({Path(cands[-1]).name})"


def glob_ipas() -> list[str]:
    import glob
    return sorted(glob.glob(str(Path.home() / "workspace" / "HermesPlus-*.ipa")))


def critical_tracks() -> str:
    """What to fix next — priority ordered. Agent should update this block at the
    end of each work session (mark what closed, add what surfaced)."""
    return """## 2. Что КРИТИЧНО чинить (по приоритету — читать сверху)

1. 🔴 **FREEZE на малых чатах** (N<100) — главная боль, НЕ закрыт.
   Медиана ~4с, 45× ≥5с; `isStreaming=False`, палец убран. Значит не стрим
   (3.4.0 закрыл) и не пагинация (3.4.1 закрыл) — это сам код чата.
2. 🔴 **STACK-CAPTURE сломан** — `stack` всегда пуст в hermex-logs.jsonl.
   Видим ЧТО фризит, но не ГДЕ. **Блокирует диагноз №1** — чинить сначала.
3. 🟠 **Скролл / чёрный экран** — частично лучше, но не всё.
   Чёрный экран имеет НЕСКОЛЬКО входов (пустой чат / после скролла / фильтры).
4. 🟡 **God-object ChatViewModel (~6.6k строк @MainActor)** — архитектурный риск.
   Расщепление = рефакторинг (EXP-4), не патч.
5. 🟡 **Сетевые таймауты/отмена** — часть вызовов без явного таймаута.

_Закрыто недавно:_ пагинация/load-older (3.4.1), Kanban SSE (3.4.1),
стрим-фриз хот-пути (3.4.0), streaming markdown cap (3.3.6), scroll yank (3.3.5)."""


def main() -> int:
    up = ensure_upstream()

    branch = git("branch", "--show-current") or "main"
    head = git("rev-parse", "--short", "HEAD") or "?"
    version = (ROOT / "VERSION").read_text().strip() if (ROOT / "VERSION").exists() else "?"
    commits = git("log", "--oneline", "-6") or "(none)"
    today = datetime.date.today().isoformat()

    app_f, app_l = count_swift_lines(ROOT / "HermesMobile")
    chat_f, chat_l = count_swift_lines(ROOT / "HermesMobile" / "Features" / "Chat")
    cvm = ROOT / "HermesMobile" / "Features" / "Chat" / "ChatViewModel.swift"
    cvm_l = sum(1 for _ in open(cvm, encoding="utf-8", errors="ignore")) if cvm.exists() else 0
    up_app_f, up_app_l = count_swift_lines(up / "HermesMobile")
    up_chat_f, up_chat_l = count_swift_lines(up / "HermesMobile" / "Features" / "Chat")
    up_cvm = up / "HermesMobile" / "Features" / "Chat" / "ChatViewModel.swift"
    up_cvm_l = sum(1 for _ in open(up_cvm, encoding="utf-8", errors="ignore")) if up_cvm.exists() else 0
    ipa = latest_ipa_size()

    body = f"""# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | {branch} |
| HEAD | {head} |
| Версия | {version} |
| Обновлено | {today} |

**Последние коммиты:**
```
{commits}
```

{critical_tracks()}

## 3. Происхождение (одним абзацем)
> **Мы — форк тяжёлого оригинала.** Upstream `uzairansaruzi/hermex` создан 2026-07-02,
> ~71k строк приложения, God-object на 5.9k — был бы тяжел и сам. Мы добавили ~3% кода.
> **Чинить надо фундамент оригинала** (God-object, стриминг, скролл), не наши ~3%.

## 4. Размеры (когда важно)
| Метрика | Upstream | Мы | Δ |
|---|---|---|---|
| Swift-файлы приложения | {up_app_f} | {app_f} | {app_f - up_app_f:+d} |
| Строк приложения | {up_app_l:,} | {app_l:,} | **{app_l - up_app_l:+,}** |
| Строк Chat | {up_chat_l:,} | {chat_l:,} | {chat_l - up_chat_l:+,} |
| ChatViewModel | {up_cvm_l:,} | {cvm_l:,} | {cvm_l - up_cvm_l:+,} |
| IPA | ~44 MB | {ipa} | +1–2 MB |
"""

    SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
    SNAPSHOT.write_text(body, encoding="utf-8")
    print(f"[snapshot] regenerated {SNAPSHOT}")
    print(f"  branch={branch} HEAD={head} VERSION={version} app={app_l:,} chat={chat_l:,} ipa={ipa}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
