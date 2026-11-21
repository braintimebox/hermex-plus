# Hermex Plus — Telemetry and Open Issues (C. telemetry-and-open-issues.md)

**Статус:** диагностика, код не менялся.
**Источник:** `HermesMobile/HermexLogger.swift`, `HermesMobile/HermexLoggerQueue.swift` (файла нет — очередь в `TelemetryEventQueue.swift`), `HermesMobile/Persistence/CacheStore.swift`, `~/.hermes/hermex-logs.jsonl`, `docs/diagnostics-fault-tree.md`.

---

## 1. Устройство логирования (VERIFIED по коду)

**HermexLogger** (`HermexLogger.swift`):
- Все события пишутся в последовательную очередь `DispatchQueue(label: "hermex.logger", qos: .utility)` — никогда не блокирует UI.
- Перед сетевой отправкой событие записывается в `TelemetryEventQueue` (JSONL на диск). Удаляется из очереди только после подтверждения сервера (`received` в ответе).
- Кольцевой буфер последних 100 событий (`recentEvents`) прикрепляется к каждому `freeze` как `lastEvents` — контекст того, что пользователь делал до зависания.
- Повторы с экспоненциальным бэкоффом: 1 → 2 → 4 → 8 → 16 → 30 с, затем 30 с постоянно.
- 4xx (кроме 429/408) — перманентный отказ, событие карантинится на диске с причиной, очередь не блокируется.
- При возврате на передний план (`didBecomeActive`) автоматически повторяет отправку.

**TelemetryEventQueue** (`HermexLoggerQueue.swift` не существует — реализация в `HermexLogger.swift` и логи очереди вложены):
- JSONL, одна строка на событие, append в конец файла.
- Лимит 10 000 событий, одно событие до 256 KB.
- Приоритетные типы (`freeze`, `error`) вытесняются последними.
- Атомарная перезапись через temp-файл + `replaceItemAt` при подтверждении пакета.
- Идентичность события — `correlationId:seqNo` (сервер deduplicates по этому ключу).
- При перезапуске загружает очередь с диска, повторно отправляет карантинованные события один раз.

## 2. Достоверность телеметрии (VERIFIED)

| Аспект | Статус | Комментарий |
|---|---|---|
| Единицы измерения | VERIFIED | Все длительности в миллисекундах (CADisplayLink * 1000, `now() - start * 1000`) |
| Сериализация | VERIFIED | `JSONSerialization`, один объект на строку JSONL |
| Событий в JSONL | VERIFIED | 3552 строк, 3.9.67 — 2453, 3.9.68 — 1099 |
| Ошибок в выборке | VERIFIED | 1 событие `error` (3.9.67), 0 (3.9.68) |
| Дублирование | UNKNOWN | Серверная deduplication по `correlationId:seqNo` — не проверялась |
| Потеря событий | UNKNOWN | Очередь на диске снижает риск, но не устраняет (диск full, сбой записи) |

**schema мержится на верхний уровень:** в `HermexLogger.log` (строка 170) `event.merge(extras)` — ключи `extras` (`p50`, `p90`, `frameTag`, `isStreaming` и т.д.) оказываются на том же уровне, что и `type`, `ts`, `message`. Это важно при парсинге — поля не вложены.

## 3. HeavyOperationTracker (VERIFIED по коду)

**Реализация:** `HermesMobile/MainThreadWatchdog.swift` (строки 10–78).
- Отслеживает одну текущую операцию на главном потоке через `NSLock` + `(label, startTime)`.
- `begin(_:)` / `end()` работают **только на главном потоке** (`guard Thread.isMainThread else { return }`).
- `Operation` enum (строки 50–60): `transcriptFullRecompute`, `cacheWrite`, `cacheRead`, `sessionUpsert`, `sseEventProcess`, `messageDecode`, `streamBatchApply`, `markdownParse`, `transcriptApply`.
- `snapshot()` возвращает `"Label (Nms)"` или `nil`, если нет операции в полёте.

**Почему `heavyOp=""` в большинстве freeze-событий:**
1. Операция могла завершиться до того, как watchdog зафиксировал фриз (таймер пингует каждую секунду, порог фриза 3 секунды).
2. Блокировка произошла на коде, который не обёрнут в `HeavyOperationTracker.begin/end` — трекер покрывает только инструментированные пути.
3. Фоновые записи (CacheStore на `.utility` очереди) intentionally не попадают в трекер (комментарий строки 15–24): фоновая работа видна через свои фазы (`Cache Write`), а не через heavyOp.

**Ограничение:** трекер не может показать, что делал основной поток, если операция не была instrumentation-точкой. Для воспроизводимых фризов контекста может не хватать.

## 4. sessions load failed (VERIFIED по логам)

| Параметр | Значение |
|---|---|
| Версия | 3.9.67 |
| Событий | 1 |
| Сообщение | `sessions load failed` |
| Экран | `SessionList` |
| Категория | `network.url.-1015` |
| В 3.9.68 | 0 событий |

**Код ошибки `-1015`** — `NSURLErrorNetworkConnectionLost` (соединение потеряно) или `NSURLErrorCannotConnectToHost`. Не подтверждено исходником — нужно искать место генерации в коде.

**Гипотеза:** при открытии списка сессий приложение пытается загрузить состояние с сервера, сеть недоступна, UI застревает в состоянии загрузки без механизма восстановления. **Не подтверждено** — место генерации события не найдено в просмотренном коде.

## 5. Share Sheet (VERIFIED по коду и CI)

| Аспект | Статус |
|---|---|
| Исправление | Ветка `ipa/3.9.68-sharefix`, коммит `d6384ac9e346c2be1d3cc861bddb33b54ab92322` |
| В main | **НЕ влита** |
| CI | Пройден (run `41207859638`, все джобы success, Publish skipped) |
| IPA | Собран, `/home/openclaw/workspace/HermesPlus-3.9.68.ipa`, 49 892 487 B, sha256 `32462b783ebda66fcb29bf59958ff37ad07538da904d9642b4ddb98b9ed93748` |
| Тестирование на устройстве | Не проведено (переподпись SideStore не тестирована) |

Исправление восстановляет URL-транспорт `hermesplus://share?d=<base64url>` для текста до 6000 байт (не требует App Group, survives re-signing), заменяет `Bool` на `ShareDeliveryOutcome`/`ShareOpenOutcome` (не ложно отчитывает об успехе), добавляет fallback через 일반 pasteboard.

## 6. Реестр незакрытых проблем

| ID | Проблема | Версия | Доказательства | Степень уверенности |
|---|---|---|---|---|
| O-1 | `sessions load failed` (network -1015) | 3.9.67 | 1 событие в JSONL | VERIFIED (событие есть), UNKNOWN (причина) |
| O-2 | `heavyOp=""` в freeze/jank | 3.9.67, 3.9.68 | Логи, код трекера | VERIFIED (поле пустое), HYPOTHESIS (причина) |
| O-3 | Кадры >50 мс, включая до 3442.8 мс | 3.9.67, 3.9.68 | `frames.maxMs` | VERIFIED |
| O-4 | p50 ≈ 16.7 мс (границе 60 Гц) | 3.9.67, 3.9.68 | `frames.durationMs` | VERIFIED |
| O-5 | Share Sheet ломается при SideStore re-sign | 3.9.67 | Код, аудит | VERIFIED (причина кода), исправлено в ветке |
| O-6 | Нет данных о реальной частоте дисплея | 3.9.67, 3.9.68 | Отсутствие `displayHz` в событиях | VERIFIED (поле отсутствует) |

## 7. Минимальные изменения схемы (если потребуются)

Только если диагностика покажет недостаточность контекста:
- `display_mode` или `displayHz` — реальная частота обновления экрана (для интерпретации кадров).
- `render_path` — какой рендеринг активен (light/fallback/full), чтобы коррелировать с кадрами.
- `operation_in_flight` — расширение `heavyOp` на SSE, Cache, Decode пути.

Не вносить без подтверждения необходимости экспериментами.