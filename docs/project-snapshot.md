# Hermex Plus — snapshot (ЕДИНСТВЕННЫЙ источник правды)

> ⚡ **Как читать:** единственный файл состояния. Агент при СТАРТЕ работы запускает
> `python3 scripts/project_snapshot.py` и читает этот файл. Больше ничего не смотреть.
> Обновляется из git — не может устареть. Не править руками (правит скрипт).

## 1. Где мы сейчас (из git — свежее)
| Что | Значение |
|---|---|
| Ветка | main |
| HEAD | 9d38edb |
| Версия | 3.9.2 |
| Обновлено | 2026-09-25 |

**Последние коммиты:**
```
9d38edb composer growth policy + opaque header bar, per the sync-compatibility rule
dffaac9 the 3.7.0 sync dropped triggers and kept interfaces — restore them, and make the class fail a gate
d831007 3.9.1: the fork signs as com.braintimebox.hermexplus, so it installs beside the App Store Hermex instead of colliding with it; gate 14 pins the identifier so a merge cannot take upstream's side and restore the collision; includes 3.8.2's composer fix (no reading-mode FAB, no state that could hide the composer)
e53b852 fix(identity): the fork signs as com.braintimebox.hermexplus
dd983d5 3.9.0: Hermex Plus signs under its own bundle identifier (com.braintimebox.hermesplus), so it installs beside Hermex instead of colliding with it — first install lands as a fresh app and the server password is entered once. Also lands the release-pipeline fixes: the build watch no longer abandons a green build
ae4fc21 3.8.2: the composer never disappears — the reading-mode FAB and the state that could hide both it and the composer are gone, so tapping the chat only dismisses the keyboard; the reasoning list is computed once per frame instead of twice, and the typing indicator stops once a response's content is final
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
| Строк приложения | 110,058 | 100,045 | **-10,013** |
| Строк Chat | 38,604 | 40,290 | +1,686 |
| ChatViewModel | 6,850 | 7,496 | +646 |
| IPA | ~44 MB | 50 MB (HermesPlus-3.9.1.ipa) | +1–2 MB |
