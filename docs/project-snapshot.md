# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | 4c754a7 |
| Версия | 3.9.36 |
| Обновлено | 2026-10-04 |

**Последние коммиты:**
```
4c754a7 diag(draft): runtime probe for the draft lifecycle — proof before fix
4762ee3 3.9.35: cache: session cache writes run on a serial cache queue off the MainActor and are awaited, so ordering and read-after-write both hold while the UI never blocks on the write; cache-write telemetry split per writer. Attribution correction: the 522/1123 ms phase readings were background time — the main-thread blocker in the logs is transcriptMessages.fullRecompute (up to 1008 ms), recorded as the next step and not touched here
4401284 fix(cache): await the session cache write — read-after-write was part of the contract
138e985 3.9.35: cache: session cache writes moved off the MainActor onto a serial cache queue (ordering guaranteed by construction); cache-write telemetry split per writer. Attribution correction: the 522/1123 ms phase readings were background time — the main-thread blocker in the logs is transcriptMessages.fullRecompute (up to 1008 ms), recorded as the next step and not touched here
2aab968 3.9.35: fix the cache-write helper signature (anonymous closure argument inside a closure with explicit arguments — compile error caught by CI)
fd99dd9 3.9.35: cache: session cache writes moved off the MainActor onto a serial cache queue, so ordering is guaranteed by construction; cache-write telemetry split per writer (Cache Write / Cache Write (sessions) / Cache Write (session)). Attribution correction: the 522/1123 ms phase readings were background time — the main-thread blocker in the logs is transcriptMessages.fullRecompute (up to 1008 ms), recorded as the next step and not touched here
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
| Строк приложения | 110,058 | 101,942 | **-8,116** |
| Строк Chat | 38,604 | 40,930 | +2,326 |
| ChatViewModel | 6,850 | 7,690 | +840 |
| IPA | ~44 MB | 50 MB (HermesPlus-3.9.9.ipa) | +1–2 MB |
