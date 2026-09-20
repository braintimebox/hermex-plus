# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | ae4fc21 |
| Версия | 3.9.0 |
| Обновлено | 2026-09-20 |

**Последние коммиты:**
```
ae4fc21 3.8.2: the composer never disappears — the reading-mode FAB and the state that could hide both it and the composer are gone, so tapping the chat only dismisses the keyboard; the reasoning list is computed once per frame instead of twice, and the typing indicator stops once a response's content is final
e13ee5f gate 13: a change to upstream's code must say that it is ours
2cb74d6 fix(pipeline): size the build watch for the job it waits on
8312b43 3.8.1: attachments are read off the main actor (an iCloud file no longer freezes the composer) and a refused attachment names its reason; the composer offers None to turn reasoning off
b1317d1 fix(composer): read attached files off the main actor, and name a refusal
07d09a6 feat(composer): offer None to turn reasoning off
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
| Swift-файлы приложения | 317 | 286 | -31 |
| Строк приложения | 101,540 | 99,901 | **-1,639** |
| Строк Chat | 36,076 | 40,146 | +4,070 |
| ChatViewModel | 6,650 | 7,496 | +846 |
| IPA | ~44 MB | 50 MB (HermesPlus-3.8.1.ipa) | +1–2 MB |
