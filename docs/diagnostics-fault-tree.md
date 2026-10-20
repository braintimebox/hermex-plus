# Hermex Plus — Дерево отказов (Fault Tree)

**Дата:** 2026-10-19
**Цель:** систематическая модель того, что может блокировать main thread, с метриками и методами валидации.
**Статус:** живой документ — обновляется по мере подтверждения/опровержения гипотез.

---

## 1. Подсистемы, блокирующие main thread

### 1.1 Message Decode

| Что | JSON → `TranscriptMessage` |
|---|---|
| Гипотеза | При 2000+ сообщений декодирование занимает >100ms на main thread |
| Предиктор | Время декодирования > 50ms при messageCount > 1000 |
| Инструмент | PhaseTelemetry: `Stream Batch Apply`, `Transcript Apply` |
| Статус покрытия | частично — агрегированно, без привязки к конкретному батчу |
| Валидация | Сравнить время decode для чата 50 vs 2000 сообщений |
| Подтверждено? | НЕТ |

### 1.2 COW Copy массива TranscriptMessage

| Что | In-place мутация разделяемого массива → глубокая копия |
|---|---|
| Гипотеза | `displayedTranscriptMessages[lastIndex] = TranscriptMessage(...)` при COW-разделяемом массиве → retain всех элементов |
| Предиктор | `isKnownUniquelyReferenced` = false перед мутацией |
| Инструмент | `HeavyOperationTracker` — сейчас пустой 80% freeze events |
| Статус покрытия | НЕТ — нет проверки уникальности ссылки |
| Валидация | Добавить проверку `isKnownUniquelyReferenced` перед мутацией; пересоздавать tail без копии |
| Подтверждено? | ЧАСТИЧНО — freeze ts=1792307183 имел heavyOp="transcriptMessages.fullRecompute (235ms)", но большинство freeze имеют пустой heavyOp |

### 1.3 Markdown Render (CoreText)

| Что | Пересчёт .layout длинного текста через CoreText |
|---|---|
| Гипотеза | `CTLineCreateWithAttributedString` на main thread, 1–2s для длинных ответов |
| Предиквор | p90 Markdown Parse > 100ms |
| Инструмент | PhaseTelemetry: `Markdown Parse`, `Markdown Parse (stream)`, `Markdown Parse (settled)` |
| Статус покрытия | ДА — агрегированные p50/p90/max |
| Валидация | 3.9.49 (live markdown) имела 35% frames >50ms vs 1.97% baseline; 3.9.50 откатил |
| Подтверждено? | ДА — регрессия 3.9.49 доказана watchdog |

### 1.4 StreamingTextFadeRenderer

| Что | Per-glyph draw каждый кадр через TimelineView |
|---|---|
| Гипотеза | Два вложенных прохода `line → run → slice` каждый кадр; длинный блок → дорогой кадр |
| Предиктор | frames max > 50ms при frameTag=stream + fadeActive |
| Инструмент | FrameTimeMonitor: frames histogram + streamCommit followScrolls |
| Статус покрытия | ДА — корреляция видна в логах |
| Валидация | Streaming Lab: режим A (fade) vs C (no fade) — сравнить frames |
| Подтверждено? | ЧАСТИЧНО — корреляция есть, причинность не доказана |

### 1.5 SwiftUI AttributeGraph diff

| Что | Пересоберка графа списка при смене identity |
|---|---|
| Гипотеза | Позиционный renderID (`"transcript:\(absoluteIndex)"`) → при сдвиге ForEach редифает весь список |
| Предиктор | freeze stack содержит `AttributeGraph` или `_ViewList_Group.edit` |
| Инструмент | MainThreadWatchdog stack capture (freeze events) |
| Статус покрытия | ДА — видно в freeze stack |
| Валидация | Сравнить freeze rate при 50 vs 2000 сообщений; стабилизировать renderID → messageId |
| Подтверждено? | ЧАСТИЧНО — 2 freeze stack содержат AttributeGraph |

### 1.6 CacheStore (SwiftData)

| Что | Read/Write messages и sessions |
|---|---|
| Гипотеза | Запись на main thread или блокирующий fetch |
| Предиктор | Cache Write > 50ms |
| Инструмент | PhaseTelemetry: `Cache Read`, `Cache Write`, `Cache Write (sessions)` |
| Статус покрытия | ДА — агрегированно |
| Валидация | Проверить что записи идут на serial queue off main (уже сделано в 3.9.35) |
| Подтверждено? | НЕТ |

### 1.7 SSE Processing

| Что | Обработка событий потока |
|---|---|
| Гипотеза | Обработка на main thread вместо utility queue |
| Предиктор | Время обработки > 16ms |
| Инструмент | НЕТ — нет инструмента |
| Статус покрытия | НЕТ |
| Валидация | Добавить измерение времени обработки SSE event |
| Подтверждено? | НЕТ |

---

## 2. Корреляции vs причинность

| Корреляция | Что это значит | Что проверить |
|---|---|---|
| frames max > 50ms + streamCommit followScrolls | Стриминг идёт когда кадры тормозят | Это причина или следствие? |
| freeze + messageCount > 2000 | Зависания в длинных чатах | Размер = причина или просто чаще длинные чаты открывают во время стриминга? |
| heavyOp="" в 80% freeze | Tracker не покрывает реальный путь | Чинить tracker или чинить инструментацию? |

---

## 3. Приоритеты валидации

1. **COW Copy** — добавить `isKnownUniquelyReferenced` check → если подтвердится, чинить
2. **AttributeGraph diff** — стабилизировать renderID → messageId → сравнить freeze rate
3. **Fade renderer** — Streaming Lab A/B тест (уже есть в приложении)
4. **SSE processing** — добавить измерение времени обработки

---

## 4. Чего не хватает в инструментах

| Инструмент | Что не хватает | Зачем |
|---|---|---|
| HermexLogger | correlation_id | Связать события в цепочку |
| HermexLogger | ring buffer 100+ (сейчас 20) | Сохранить контекст действий |
| MainThreadWatchder | HeavyOperationTracker для SSE, Cache, Decode | Заполнить heavyOp в freeze events |
| PhaseTelemetry | durationMs в каждом событии | Корреляция по времени |
| FrameTimeMonitor | Указать какой fade режим активен | A/B тест |
| Server | Загрузка dSYM | Символизация stack trace |
