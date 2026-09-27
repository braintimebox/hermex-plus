# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | da7b081 |
| Версия | 3.9.18 |
| Обновлено | 2026-09-27 |

**Последние коммиты:**
```
da7b081 composer: mic and scheduled messages leave the horizontal scroller
5de3690 3.9.17: revert: the composer is back to the 3.9.13 view — my last three changes lost the mic while typing, hid Send on an empty field and pushed the model/workspace row behind a menu. The measured field-height fix and the telemetry stay
7123c3f revert: composer back to the 3.9.13 state — my last three changes made it worse
a763dcf 3.9.16: composer: adaptive layout — the collapsed row stays the reference, the expanded state becomes two zones inside the same card (full-width field + a compact tools band), so the field gets its width back and the controls stop drifting to the middle
02aa373 composer: adaptive layout — one row collapsed, two zones expanded
870f1f0 composer: give the field its width back, align the row to the bottom
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
| Строк приложения | 110,058 | 100,316 | **-9,742** |
| Строк Chat | 38,604 | 40,497 | +1,893 |
| ChatViewModel | 6,850 | 7,534 | +684 |
| IPA | ~44 MB | 50 MB (HermesPlus-3.9.9.ipa) | +1–2 MB |
