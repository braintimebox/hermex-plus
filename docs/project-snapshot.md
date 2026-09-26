# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | eb66d81 |
| Версия | 3.9.11 |
| Обновлено | 2026-09-26 |

**Последние коммиты:**
```
eb66d81 composer: the field's height comes from the laid-out text, not from a re-measure
75c94a0 3.9.10: composer height stops oscillating: re-measure on width change, publish only on a real height change (3.9.9 closed a feedback loop through the transcript inset)
3f9aa7e composer: stop the height oscillation 3.9.9 introduced
964e06f 3.9.9: composer height unstuck: the field re-measures when its width changes, so a one-line draft no longer keeps a four-line card (telemetry showed the field pinned at its 96pt ceiling)
d86b6dc composer: the field's height can come back down when it widens
e404379 3.9.8: composer look restored: the 3.9.7 composer change is reverted, controls and plus menu are back where they were
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
| Swift-файлы приложения | 332 | 287 | -45 |
| Строк приложения | 110,058 | 100,130 | **-9,928** |
| Строк Chat | 38,604 | 40,375 | +1,771 |
| ChatViewModel | 6,850 | 7,496 | +646 |
| IPA | ~44 MB | 50 MB (HermesPlus-3.9.9.ipa) | +1–2 MB |
