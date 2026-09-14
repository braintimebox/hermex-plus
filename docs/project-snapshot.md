# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | b1317d1 |
| Версия | 3.8.1 |
| Обновлено | 2026-09-14 |

**Последние коммиты:**
```
b1317d1 fix(composer): read attached files off the main actor, and name a refusal
07d09a6 feat(composer): offer None to turn reasoning off
a5e306f fix(pipeline): the wait loop handed jq a doubled backslash
fc7bc81 3.8.0: the session list self-recovers from any load failure, and the failure is now logged
1135277 fix(sessions): every load failure self-recovers, and the failure is logged
4abab50 Merge pull request #1 from braintimebox/sync/upstream-1.6.0
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
| Swift-файлы приложения | 193 | 286 | +93 |
| Строк приложения | 71,094 | 99,962 | **+28,868** |
| Строк Chat | 27,421 | 40,207 | +12,786 |
| ChatViewModel | 5,952 | 7,494 | +1,542 |
| IPA | ~44 MB | 50 MB (HermesPlus-3.8.0.ipa) | +1–2 MB |
