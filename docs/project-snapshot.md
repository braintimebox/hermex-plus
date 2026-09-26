# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | d86b6dc |
| Версия | 3.9.9 |
| Обновлено | 2026-09-26 |

**Последние коммиты:**
```
d86b6dc composer: the field's height can come back down when it widens
e404379 3.9.8: composer look restored: the 3.9.7 composer change is reverted, controls and plus menu are back where they were
9ad0844 revert 3.9.7's composer change — it looked wrong and missed the point
15f885c 3.9.7: composer is one line at rest like Telegram: the 44pt control row now waits for content instead of appearing on focus, so the transcript keeps that height until you type
f42ce2e composer: one line at rest — the control row waits for content, like Telegram
34ec586 3.9.6: multi-line drafts stay inside the composer card: the ceiling moved onto the text frame and the container admits its padding, so text scrolls inside instead of drawing over the border
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
| Строк приложения | 110,058 | 100,108 | **-9,950** |
| Строк Chat | 38,604 | 40,353 | +1,749 |
| ChatViewModel | 6,850 | 7,496 | +646 |
| IPA | ~44 MB | 50 MB (HermesPlus-3.9.8.ipa) | +1–2 MB |
