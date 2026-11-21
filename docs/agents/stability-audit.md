# Hermex Plus — Stability Audit (A. stability-audit.md)

**Статус:** диагностический этап завершён, код не менялся, репозиторий не троган.
**Источник:** telemetry `~/.hermes/hermex-logs.jsonl` (3552 строки), исходный код `/tmp/hermex-3965`, Git-история, `docs/diagnostics-fault-tree.md`, `docs/reliable-message-pipeline.md`.

---

## 1. Исходное состояние (VERIFIED)

| Параметр | Значение |
|---|---|
| Репозиторий | `/tmp/hermex-3965` |
| Ветка | `ipa/3.9.68-sharefix` |
| HEAD | `d6384ac9e346c2be1d3cc861bddb33b54ab92322` |
| `main` | `4e4aabdcacc26f913e246a1f088ee4514a72f1e9` |
| HEAD в `main` | **НЕ влита** (`git merge-base --is-ancestor` → NO) |
| Рабочая директория | чистая |
| Файл VERSION | `3.9.68` |
| Телеметрия | `~/.hermes/hermex-logs.jsonl`, 3552 строки |
| События 3.9.67 | 2453 |
| События 3.9.68 | 1099 |

`docs/project-snapshot.md` зафиксирован на версии `3.9.47` / HEAD `903a0b5` — **устарел** (не соответствует текущей ветке и телеметрии). Использовать как источник нельзя.

**Кодовые артефакты производительности:**
- `HermesMobile/Config/FrameTimeMonitor.swift` — CADisplayLink, кадры, jank, гистограмма
- `HermesMobile/Config/PhaseTelemetry.swift` — фазы Stream/Transcript/Markdown/Cache/Session
- `HermesMobile/Config/HitchMeter.swift` — hitch-метр (только в DEBUG, `--hitch-meter`)
- `HermesMobile/MainThreadWatchdog.swift` — freeze/stutter watchdog, HeavyOperationTracker, стек через Mach thread_get_state
- `HermesMobile/HermexLogger.swift` — доставка событий на сервер с очередью на диск
- `HermesMobile/Persistence/CacheStore.swift` — две serial `.utility` очереди (сообщения, сессии), вне main thread

---

## 2. Основные результаты

| Вопрос | Результат | Статус |
|---|---|---|
| `frames p50 = 16669 мс` из предыдущего отчёта | **Ошибка анализа** — такого значения нет в логах. Реальные `frames.durationMs`: 8.3–720.4 мс (3.9.67), 8.3–304.4 мс (3.9.68) | VERIFIED (опровержение) |
| Приложение работает на 60 Гц границе | p50 ≈ 16.7 мс = ровно один кадр 60 Гц, нет запаса на 120 Гц | VERIFIED |
| Есть кадры >50 мс | Да: до 1403.6 мс (3.9.67), до 3442.8 мс (3.9.68) | VERIFIED |
| Jank коррелирует со скроллом+стримингом | 3.9.67: 43/50 scrollOwner=user, 23/50 isStreaming; 3.9.68: 7/18 scroll, 4/18 stream | CORRELATION |
| Ошибка sessions load failed | 1 событие 3.9.67, 0 в 3.9.68 | VERIFIED (событие), UNKNOWN (причина) |
| heavyOp пустой в freeze | Да, в большинстве событий | VERIFIED (факт), HYPOTHESIS (причина) |
| Share Sheet сломан при SideStore re-sign | Да, исправление в ветке, не в main | VERIFIED |

## 3. Подтверждённые проблемы

| ID | Проблема | Версии | Доказательство |
|---|---|---|---|
| D-1 | Кадры до 3.4 сек при нормальном p50 | 3.9.67, 3.9.68 | `frames.maxMs` 1403.6 / 3442.8 мс |
| D-2 | p50 на границе 60 Гц (16.7 мс) | 3.9.67, 3.9.68 | `frames.durationMs` p50 |
| D-3 | `sessions load failed` (-1015) | 3.9.67 | 1 событие JSONL |
| D-4 | Share Sheet ломается при SideStore re-sign | 3.9.67 | Код + аудит, исправление в ветке |
| D-5 | Диагностика слепа: `heavyOp=""` в freeze | 3.9.67, 3.9.68 | Код трекера + логи |

## 4. Гипотезы (требуют экспериментов)

| ID | Гипотеза | Обоснование |
|---|---|---|
| H-1 | Follow-scroll соревнуется за кадр во время стриминга | Корреляция jank + scrollOwner=user + isStreaming |
| H-2 | Полный пересчёт layout текста O(N) на каждый коммит | streamCommit с accumMax до 459 символов и frameMax до 50 мс |
| H-3 | Тяжёлый 초기 layout доминирует в начале стрима | streamAgeMs не коррелировал явно с frameMaxMs (не проверено) |
| H-4 | Деградация совпадает с фоновыми операциями | Cache Read p50 до 208.4 мс, Cache Write до 1440.3 мс |

## 5. Ограничения исследования

- Нет доступа к macOS/Xcode/физическому устройству — профилирование Instruments невозможно.
- Телеметрия не содержит `displayHz` — нельзя судить о 120 Гц режиме.
- Выборка 3.9.68 в 2.3× меньше 3.9.67 — нельзя утверждать об улучшении стабильности только на основе fewer событий.
- `docs/project-snapshot.md` устарел (3.9.47 vs текущая 3.9.68).

## 6. Нерешённые вопросы

1. Какая именно операция блокирует main thread во время кадров >50 мс?
2. Почему `heavyOp` пустой в большинстве freeze — нет инструментации или операция завершилась раньше?
3. Что вызывает `sessions load failed` и как приложение ведёт себя после?
4. Какая реальная частота дисплея устройства, на котором снята телеметрия?
5. Подтверждается ли исправление Share Sheet на реальном устройстве после SideStore re-sign?

---

**Следующие шаги:** см. `stability-roadmap.md`. Код не изменялся, коммиты не созданы, `main` не троган.