# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | e45aa2b |
| Версия | 3.9.38 |
| Обновлено | 2026-10-04 |

**Последние коммиты:**
```
e45aa2b fix(cache): separate the cache-write queues — my shared serial queue blocked the completed turn
d4d13e9 3.9.37: test speed: retry backoff made injectable (HermesRetryBackoff) and zeroed in the two affected test classes, so a simulated connectivity failure no longer costs 15 s of wall clock per case. Production schedule unchanged (1+2+4+8 s); the retry loop still runs all five attempts. Expected Test 640 s to about 520 s
c3c28ad test(perf): stop paying 15 s of retry backoff per simulated connectivity failure
ded6f7f 3.9.36: diagnostics only: draft lifecycle probe (setContent/setDraft/clearDraft/resolveSubmission/moveDraft/restoreAbandonedNewChatDraft/hydrate) logging draft key + text length + didStartConversation, so the draft resurrection chain is proven from logs instead of inferred. No behaviour change
ae374e1 3.9.36: use the gate's marker form (HERMEX-FORK:) on the probe comments — the gate matches the colon, so 'HERMEX-FORK (' read as unmarked
e10666c 3.9.36: diagnostics only: draft lifecycle probe (setContent/setDraft/clearDraft/resolveSubmission/moveDraft/restoreAbandonedNewChatDraft/hydrate) logging draft key + text length + didStartConversation so the draft resurrection chain is proven from logs instead of inferred. No behaviour change: markConversationStarted wiring and .newChat semantics untouched until the runtime logs land
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
| Строк приложения | 110,058 | 101,987 | **-8,071** |
| Строк Chat | 38,604 | 40,932 | +2,328 |
| ChatViewModel | 6,850 | 7,692 | +842 |
| IPA | ~44 MB | 50 MB (HermesPlus-3.9.9.ipa) | +1–2 MB |
