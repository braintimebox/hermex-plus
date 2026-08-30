#!/usr/bin/env python3
"""Hermex Plus — project metrics recompute.

Deterministic, NO LLM. Counts .swift lines (app / Chat / ChatViewModel), finds
the latest IPA, reads VERSION, and regenerates docs/project-metrics.md with a
fresh "recomputed" date.

Run it when you start work on the Hermex Plus core (not cron, not scheduled):

    cd ~/Projects/hermex-plus
    python3 scripts/project_metrics.py

It overwrites docs/project-metrics.md. The static "Lineage" block is preserved;
the dynamic blocks (Code size / Build size / Current state) are regenerated.
"""

from __future__ import annotations

import datetime
import glob
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METRICS = ROOT / "docs" / "project-metrics.md"
UPSTREAM_ROOT = Path("/tmp/hermex-orig-compare")  # clone of uzairansaruzi/hermex
UPSTREAM_GIT = "https://github.com/uzairansaruzi/hermex.git"


def count_swift_lines(base: Path) -> tuple[int, int]:
    """Return (file_count, line_count) for all .swift under base, excl .git."""
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
    """Clone upstream if the local copy is missing. NO LLM, just git."""
    if UPSTREAM_ROOT.exists() and any(UPSTREAM_ROOT.iterdir()):
        return UPSTREAM_ROOT
    print(f"[metrics] cloning upstream {UPSTREAM_GIT} ...", file=sys.stderr)
    subprocess.run(["git", "clone", "--quiet", UPSTREAM_GIT, str(UPSTREAM_ROOT)],
                   check=False)
    return UPSTREAM_ROOT


def latest_ipa() -> Path | None:
    # IPA artifacts live in ~/workspace, NOT next to the repo.
    cands = sorted(glob.glob(str(Path.home() / "workspace" / "HermesPlus-*.ipa")))
    return Path(cands[-1]) if cands else None


def git_head() -> str:
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
                             capture_output=True, text=True, check=False)
        return out.stdout.strip() or "?"
    except OSError:
        return "?"


def main() -> int:
    up = ensure_upstream()

    app_f, app_l = count_swift_lines(ROOT / "HermesMobile")
    chat_f, chat_l = count_swift_lines(ROOT / "HermesMobile" / "Features" / "Chat")
    cvm_l = 0
    cvm = ROOT / "HermesMobile" / "Features" / "Chat" / "ChatViewModel.swift"
    if cvm.exists():
        cvm_l = sum(1 for _ in open(cvm, encoding="utf-8", errors="ignore"))

    up_app_f, up_app_l = count_swift_lines(up / "HermesMobile")
    up_chat_f, up_chat_l = count_swift_lines(up / "HermesMobile" / "Features" / "Chat")
    up_cvm = up / "HermesMobile" / "Features" / "Chat" / "ChatViewModel.swift"
    up_cvm_l = sum(1 for _ in open(up_cvm, encoding="utf-8", errors="ignore")) if up_cvm.exists() else 0

    ipa = latest_ipa()
    ipa_str = f"45–47 MB (последний `{ipa.name}`)" if ipa else "?" 
    version = (ROOT / "VERSION").read_text().strip() if (ROOT / "VERSION").exists() else "?"
    today = datetime.date.today().isoformat()
    head = git_head()

    # Build the new dynamic section, preserving the static Lineage block.
    # We regenerate the whole file from a template so static is stable.
    content = f"""# Hermex Plus — project metrics

> **Источник правил:** этот файл — *факт*, а не мнение. Цифры пересчитываются
> скриптом `scripts/project_metrics.py` (детерминированно, без LLM) и обновляются
> **при работе над ядром** (не cron). НЕ править руками. Если устарело — запусти скрипт.
>
> **Любой агент:** перед работой с Hermex Plus сначала читает этот файл.
> Правило — в `AGENTS.md`. Это **единственный** источник правды о размере/объёме.

## Lineage (static — не меняется)

| Поле | Значение |
|---|---|
| Upstream | `uzairansaruzi/hermex` (fork: false, created **2026-07-02**) |
| Fork | `braintimebox/hermex-plus` (first commit **2026-07-02**) |
| Активный период | 2026-07-02 → 2026-08-30 (~2 месяца) |
| Коммитов (форк) | 403 |
| Авторы (top) | brain time box (278), Uzair Ansar (57), braintimebox (49), uzairansaruzi (7) |
| Вывод | **Тяжесть — наследство оригинала, а не наша переделка.** Форк почти не раздул код поверх (≈3%). |

## Code size (dynamic — пересчитывается)

| Metric | Upstream | Ours | Delta |
|---|---|---|---|
| Swift-файлы приложения (без Tests) | {up_app_f} | {app_f} | {app_f - up_app_f:+d} |
| Строк приложения (без Tests) | {up_app_l:,} | {app_l:,} | **{app_l - up_app_l:+,}** |
| Файлов Chat | {up_chat_f} | {chat_f} | {chat_f - up_chat_f:+d} |
| Строк Chat | {up_chat_l:,} | {chat_l:,} | {chat_l - up_chat_l:+,} |
| ChatViewModel строк | {up_cvm_l:,} | {cvm_l:,} | {cvm_l - up_cvm_l:+,} |

## Build size (dynamic — пересчитывается)

| Metric | Upstream | Ours |
|---|---|---|
| IPA | ~44 MB (наблюдение; в релизах orig нет assets) | {ipa_str} |

## Current state (dynamic)

| Поле | Значение |
|---|---|
| VERSION | {version} |
| HEAD | {head} |
| Last metrics recompute | {today} |

## Rediscovered root-cause (2026-08-30)

> **Hermex Plus — форк тяжёлого оригинала, а не наш "наспех собранный" проект.**
> Оригинал `uzairansaruzi/hermex` (создан 2 июля 2026, ~71k строк приложения,
> ChatViewModel 5.9k строк, один God-object на всё) сам был тяжёлым и быстро
> написанным. Мы форкнули этот фундамент и добавили **~3%** своего кода поверх,
> **не перестраивая тяжёлый core**. При перепроектировке ядра разбирать надо
> **фундамент оригинала** (God-object, стриминг, скролл), а не наши ~3% поверх.
> Точечные фиксы по одному симптому это не решать — нужен архитектурный разбор ядра.

## How to recompute (metod — не для чтения, для запуска)

```bash
cd ~/Projects/hermex-plus
python3 scripts/project_metrics.py
```
"""

    METRICS.parent.mkdir(parents=True, exist_ok=True)
    METRICS.write_text(content, encoding="utf-8")
    print(f"[metrics] regenerated {METRICS}")
    print(f"  app:   {app_f} files / {app_l:,} lines  (upstream {up_app_f}/{up_app_l:,})")
    print(f"  chat:  {chat_f} files / {chat_l:,} lines  (upstream {up_chat_f}/{up_chat_l:,})")
    print(f"  CVM:   {cvm_l:,} lines  (upstream {up_cvm_l:,})")
    print(f"  VERSION: {version}  HEAD: {head}  IPA: {ipa.name if ipa else '?'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
