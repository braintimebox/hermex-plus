# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | 47b2f91 |
| Версия | 3.9.35 |
| Обновлено | 2026-10-04 |

**Последние коммиты:**
```
47b2f91 perf(cache): move session cache writes off the MainActor; split cache-write telemetry
3b03aec 3.9.34: telemetry bridge: #920 phase durations (Stream Batch Apply, Transcript Apply, Markdown Parse, Cache Read/Write, Session Open) now aggregate into hermex-logs.jsonl as type=phase events with count/p50/p90/max and context (chars, mutated, messages, rows). No per-interval disk I/O; signposts and the hitch meter unchanged; the watchdog and jank events untouched
ad6df3b 3.9.34: keep the telemetry bridge in the Config group (gate 3 — group path must match the file's location)
18482d9 3.9.34: telemetry bridge: #920 phase durations (Stream Batch Apply, Transcript Apply, Markdown Parse, Cache Read/Write, Session Open) now aggregate into hermex-logs.jsonl as type=phase events with count/p50/p90/max and context (chars, mutated, messages, rows). No per-interval disk I/O; signposts and the hitch meter unchanged; the watchdog and jank events untouched
245f4f0 perf(telemetry): aggregate #920 phase durations into hermex-logs.jsonl
ed43a0d 3.9.34: mark the ported #920 files (gate 13 — provenance for sync surface)
```

## 2. Что КРИТИЧНО чинить (по приоритету — читать сверху)

1. 🔴 **FREEZE на малых чатах после отправки (любой триггер)** — **OPEN**.
   Не закрыт. 3.4.2 no-streaming и 3.4.3 якорь НЕ сняли (пользователь: 3.4.3 снова завис после отправки). Ждём стек из 3.4.4 (write-through) для точного места.
3. 🟠 **Скролл / чёрный экран** — **OPEN**.
   Частично лучше, но не всё. Несколько входов (пустой чат / после скролла / фильтры).
4. 🟡 **God-object ChatViewModel (~6.6k строк @MainActor)** — **OPEN**.
   Архитектурный риск. Расщепление = рефакторинг (EXP-4), не патч.
5. 🟡 **Сетевые таймауты/отмена** — **OPEN**.
   Часть вызовов без явного таймаута.
6. 🟡 **Аватарка не восстанавливается после переустановки** — **OPEN**.
   Требует серверного изменения (эндпоинт avatar в hermes-webui). Клиентский фикс невозможен.

_Закрыто:_ №2 STACK-CAPTURE — стек фриза теряется при force-quit, №7 «Верх-вниз при думании» (sizeChangeAnchor при нерастущем тексте)


## 3. Происхождение (одним абзацем)
> **Мы — форк тяжёлого оригинала.** Upstream `uzairansaruzi/hermex` создан 2026-07-02,
> ~71k строк приложения, God-object на 5.9k — был бы тяжел и сам. Мы добавили ~3% кода.
> **Чинить надо фундамент оригинала** (God-object, стриминг, скролл), не наши ~3%.

## 4. Размеры (когда важно)
| Метрика | Upstream | Мы | Δ |
|---|---|---|---|
| Swift-файлы приложения | 332 | 290 | -42 |
| Строк приложения | 110,058 | 101,856 | **-8,202** |
| Строк Chat | 38,604 | 40,926 | +2,322 |
| ChatViewModel | 6,850 | 7,690 | +840 |
| IPA | ~44 MB | 50 MB (HermesPlus-3.9.9.ipa) | +1–2 MB |
