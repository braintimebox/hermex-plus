# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | bf82d08 |
| Версия | 3.6.1 |
| Обновлено | 2026-09-11 |

**Последние коммиты:**
```
bf82d08 docs: refresh the project snapshot
84c545c ops: install the watchdog too; a dry-run path for the installer
583b6af docs: register ops/ and the new commands; add installer rules
795d743 ops: version the logs endpoint, add install-server; restore the versioned hook install
0a62dd2 ci: write the failure parser to a file, not through python3 -c
34fc3da docs: project conventions, each rule naming the failure it prevents
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

Закрыто недавно: №2 STACK-CAPTURE — стек фриза теряется при force-quit (), №7 «Верх-вниз при думании» (sizeChangeAnchor при нерастущем тексте) ()


## 3. Происхождение (одним абзацем)
> **Мы — форк тяжёлого оригинала.** Upstream `uzairansaruzi/hermex` создан 2026-07-02,
> ~71k строк приложения, God-object на 5.9k — был бы тяжел и сам. Мы добавили ~3% кода.
> **Чинить надо фундамент оригинала** (God-object, стриминг, скролл), не наши ~3%.

## 4. Размеры (когда важно)
| Метрика | Upstream | Мы | Δ |
|---|---|---|---|
| Swift-файлы приложения | 193 | 199 | +6 |
| Строк приложения | 71,094 | 74,509 | **+3,415** |
| Строк Chat | 27,421 | 30,429 | +3,008 |
| ChatViewModel | 5,952 | 6,682 | +730 |
| IPA | ~44 MB | 47 MB (HermesPlus-3.6.0.ipa) | +1–2 MB |
