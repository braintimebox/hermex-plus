# Hermes Plus — Reliable Message & Stream Pipeline (архитектурный контракт)

Статус: **RESEARCH & EXPERIMENT PLAN / НЕ РЕАЛИЗОВАНО**. Ни одной строки продукта не изменено.
Уровни достоверности: **FACT** (код/логи), **MEASURED** (измерено), **HYPOTHESIS**, **NOT VERIFIED**,
**ACCEPTANCE CRITERION** (цель, которая станет результатом только после верификации).

> Эпистемическая дисциплина: документ не утверждает результат там, где есть только гипотеза.
> Каждая оптимизация ниже обязана пройти A/B-эксперимент до того, как попадёт в «сделано».

---

## 0. Два конвейера — один UX (основная архитектура)

```
                   HERMES PLUS
                        │
          ┌─────────────┴─────────────┐
          ↓                           ↓
   MESSAGE PIPELINE            STREAM PIPELINE
   (Э1 — Э6)                   (Э7 + Э9)
          │                           │
   не потерять состояние        плавно показать поток
          │                           │
   ownership                   stream buffer
   durable state               cadence / batching
   outbox / state machine      incremental render
   retry / reconciliation      frame budget (8,33 мс при 120 Hz)
   sent                        fallback boundary (4000 симв.)
          │                           │
          └─────────────┬─────────────┘
                        ↓
                ОДИН UX-ПРИНЦИП
               не тратить внимание
```

**Контракт между конвейерами (граница ответственности):**

- *Message Pipeline* гарантирует состояние и доставку, но **не управляет** частотой UI-рендеринга.
- *Stream Pipeline* отображает состояние и поток, но **не владеет** надёжностью и persistence сообщения.

Реализации остаются независимыми — именно для того, чтобы каждую можно было измерить и
исправить отдельно, не теряя причинность.

---

## 1. Критерий, по которому всё оценивается

```
тормоза                → внимание уходит на ожидание
уведомления            → внимание уходит на то, чего не просили
потеря введённого текста → внимание тратится дважды (написать + восстановить)
итог                   → то, ради чего приложение существует, не происходит
```

Принцип: **внимание — дефицитный ресурс.** Если для работы системы пользователь обязан
что-то помнить или контролировать — система спроектирована неверно.

---

## 2. GATE 0 — достижима ли гарантия доставки без серверного idempotency

Вопрос, решаемый ДО state machine: клиент не может математически гарантировать
duplicates = 0, если не в состоянии доказать серверу «это тот же самый запрос».

### 2.1 FACT — что найдено на сервере (`/home/openclaw/hermes-webui/`)

| факт | место | следствие |
|---|---|---|
Сервер присваивает **стабильные message id** | `api/streaming.py:_assign_stable_message_ids`, `api/gateway_chat.py:1193` | у сообщения есть серверная идентичность |
Идентичность = `id` или `message_id` | `api/models.py:8073/8149` (`_message_identity`) | сверка возможна по id |
**Dedup при слиянии состояния по `message_id`** | `api/models.py:8892–8934` («authoritative — skip if…») | дубликат **детектируем и отбрасывается** сервером при merge |
Dedup-идентичность стрима | `api/models.py:8187` (`_message_identity` в `api/streaming.py`) | история стрима тоже дедуплицируется |
Сервер отслеживает активный стрим сессии | `session.active_stream_id` (`hermes-webui/server.py:503`, `api/streaming.py:11670`) | понятие «у сессии уже есть стрим» существует |
Новый `/api/chat/start` отклоняется при активном стриме | `api/streaming.py:11670`; клиент читает `activeStreamId` из 409 (`APIError.swift:106–109`) | **409 — не «неизвестность», а структурированный конфликт**: в теле есть id активного стрима |
Клиентского ключа в чат-пути **нет** | `idempotency_key` встречается только в `api/kanban_bridge.py:358` | chat-эндпоинт **не принимает** клиентский ключ |
Паттерн ключа в проекте уже есть | `APIClient+Kanban.swift:407`, `Models/Kanban.swift:69` | ключ реализован для Kanban, но не для чата |

### 2.2 Вердикт GATE 0

```
Exactly-once (duplicates == 0)      — НЕДОСТИЖИМО клиентом в текущем API.
                                      Причина: /api/chat/start не принимает
                                      клиентский idempotency key.

At-least-once + reconciliation
+ duplicate detection                — ДОСТИЖИМО, примитивы существуют:
                                        • 409 + activeStreamId → конфликт однозначен
                                        • /api/chat/stream/status → серверное состояние
                                        • server-assigned stable message ids
                                        • серверный dedup по message_id
```

**Единственный путь к настоящему exactly-once** — добавить клиентский ключ в чат-путь
**на сервере** (паттерн Kanban уже готов). Это серверное изменение, вне клиентской
state machine; в клиенте его эмулировать нельзя.

**Следствие для архитектуры:** инвариант клиента формулируется честно —
**«ровно один экземпляр сообщения в конечном состоянии; при неопределённости — reconciliation,
а не слепой повтор»**. Инвариант `duplicates == 0` на уровне транспорта **не заявляется**.

---

## 3. Что есть сейчас (FACT)

| слой | механизм | файлы |
|---|---|---|
Идентичность | `ChatMessage.messageId` (серверный, стабильный), `sessionID`, `sessionKey` | `ChatMessage.swift`, `ChatDraftStore.swift` |
Черновик | durable: `setContent`/`clearDraft`/`resolveSubmission`/`moveDraft`/`restoreAbandonedNewChatDraft`/`discardDraft` + debounce | `ChatDraftStore.swift` |
Share→черновик | 4 транспорта | `SharedDraftStore.swift` |
Persistence | раздельные serial-очереди `writeQueue` (сообщения) и `sessionWriteQueue` (сессии) | `CacheStore.swift` |
Отложенная отправка | durable-механизм отложенных сообщений (зародыш очереди) | `PendingScheduledMessage.swift`, `ScheduledMessagesView.swift` |
Стрим | `ChatStreamCoordinator`, `activeStreamID`; восстановление — **одна** функция `restoreActiveStreamSnapshotIfAvailable` | `ChatStreamCoordinator.swift`, `ChatViewModel.swift` |
Ошибки | `APIError.isRetryable`, `isIdempotent`-концепт (`.timedOut`/`.networkConnectionLost` **исключены**), 409/404-разбор | `APIError.swift:61,106–122` |
Повторы | `HermesRetryBackoff`, 5 попыток, 1+2+4+8 с | `ChatViewModel.swift` |
Уведомления | `appendLocalNoticeMessage`/`pinLocalNoticeMessage` → **в ленту**, тот же канал, что карточка `goal` | `ChatViewModel.swift:4578/4582` |
Рендер | стрим — `LightStreamingRenderer` (O(1)); >4000 — `PlainMarkdownFallbackView` c `.fixedSize`; settled — `ChatMarkdownView` | `MarkdownRenderer.swift:152/1235/410` |

**Чего нет (grep):** `PendingMessage`/`queuedMessage`/`outbox` как тип, `sendState`/`MessageDeliveryState`,
`retryAttempt`, reconciliation сообщений, durable-очередь после kill, защита от дублей.

---

## 4. Группировка по корню

**Один корень — владение текстом.** Черновик, share-доставка, воскресающий текст, попадание не в
тот чат — один дефект: **у текста нет стабильного владельца (messageID + sessionID) от появления до
подтверждённой отправки.**
- `FACT (3.9.36)`: `restoreAbandonedNewChatDraft` — **0 срабатываний** → гипотеза о переносе
  `session → newChat` в проверенном прогоне **не подтвердилась**;
- `FACT (3.9.36)`: `setContent` вызывается **дважды на одно изменение** (647 записей) — кандидат на
  «текст возвращается»: второй writer пишет устаревшее значение;
- `FACT`: `clearDraft` = `setContent(.empty)` — запись обнуляется, а не удаляется.

**Один корень — один канал шума.** `appendLocalNoticeMessage` обслуживает и сетевые ошибки, и `goal`.

**Один корень — нет очереди.** Сбой становится видимым событием, потому что отправке некуда «встать».

**Независимо:** App Group вырезается при переподписи бесплатным ID (`FACT`: 186/186 отказов share);
`NotificationService.swift:758–763` без App Group не уведомляет; `aps-environment` бесплатному ID недоступен.

---

## 5. Архитектура

### 5.1 Разделение

```
СОСТОЯНИЕ — что система знает (сеть, очередь, повторы, черновики, стрим)
СИГНАЛ    — что обязан увидеть пользователь
ПРАВИЛО: сигнал возникает только если требуется решение. Остальное не навязывается.
```

### 5.2 State machine

```
draft ──send──► staged ──attempt──► sending ──2xx/EOF──► sent ──► удалить текст
                 │                    │
                 │                    ├─ -1001/-1005 ──► retryable ──backoff──► sending
                 │                    │
                 │                    └─ 409/steer.refused ──► needsReconcile
                 │                                                 │ сверка (не повтор!)
                 │                                                 ▼
                 └─ перезапуск приложения ──► продолжает с этого же места
                                                                  sent | failed(terminal,
                                                                  текст СОХРАНЁН, один сигнал)
```

Инварианты: `sent` — единственный путь к удалению текста; `failed` **никогда** не удаляет текст;
каждый переход durable; `idempotencyKey` создаётся в `staged` (локально) и живёт до `sent`.

### 5.3 Persistence

| данные | где | правило |
|---|---|---|
staged/retrying | durable-очередь по `sessionID` | пишется **до** первой попытки |
черновик | `ChatDraftStore`, ключ `session/<host>/<id>` | **один** writer (устраняет двойной `setContent`) |
outbox | **отдельная** область | не через общие очереди (иначе повтор регрессии `e45aa2b`) |
stream | snapshot по `streamID` | переживает обрыв и перезапуск |
кэш | `writeQueue` / `sessionWriteQueue` | **как сейчас (3.9.38) — сохранить** |

### 5.4 Retry / reconciliation

| класс | retryable | политика | обоснование |
|---|---|---|---|
`-1001` timeout | **да** | backoff 1+2+4+8, до 5 | `MEASURED`: 7 сбоев |
`-1005` connection lost | **да** | то же | `MEASURED`: 4 сбоя; **дефект классификации** (помечен как timeout) |
`409` | **нет** | `needsReconcile` → привязка к `activeStreamId` | тело несёт id активного стрима — состояние известно |
`steer.refused` | **нет** | `needsReconcile` | отправка поверх активного стрима |
2xx / EOF | — | `sent` | терминально |

### 5.5 Границы

```
UI        показывает состояние (точка/строка); в ленту — только переписка
NETWORK   одна точка входа; наружу только через state machine
CACHE     три независимые области: messages | sessions | outbox
RENDER    стрим — LightStreamingRenderer; >4000 — fallback (кандидат Э7); settled — ChatMarkdownView
          Splitters — НЕ ТРОГАТЬ (dead code с 3.4.0, 0 call sites)
NOTICES   транзиентное → статус-строка; требует решения → один сигнал ≤3 с, НЕ в ленте
```

---

## 6. Измеряемые критерии успеха

```
1. потерянный текст          = 0 за N циклов (kill в staged/sending)
2. дубликаты                 = 0 наблюдаемых; при неопределённости — reconciliation, не повтор
3. сигналов на действие      = 1 (только требующее решения)
4. видимая задержка отправки  = 0 (сообщение появляется локально мгновенно)
5. открытие чата             < 100 мс (MEASURED: Session Open 916 мс, main)
6. доля времени в fallback   измерена (сейчас 0 сэмплов — не срабатывал)
7. уведомления для «прошло само» = 0
```

---

## 7. Performance roadmap — rendering-ветка (строгий порядок)

**Правило:** до 3.9.40 ничего не оптимизируется. Каждый шаг — instrumentation-only,
одна переменная на сборку, baseline каждого шага переиспользуется следующим.

```
3.9.40  Frame Histogram            ← СДЕЛАНО (собрано, ждёт установки и данных)
        все кадры, p50–p99, бакеты, контексты idle/scroll/stream/scroll+stream/app_update
   ↓
3.9.41  Incremental Render
        гипотеза: при streaming перерисовывается ТОЛЬКО новый фрагмент, или система
        заставляет заново раскладывать/рендерить большой объём уже готового текста
        сравнение: incremental vs full re-render, стоимость от накопленной длины
   ↓
3.9.42  Fallback Render
        отдельно: Frame Time fallback-ветки, layout/render passes, короткий vs длинный контент
   ↓
3.9.43  .fixedSize A/B
        один и тот же контент, .fixedSize ON/OFF → histogram + render/layout метрики
        только здесь проверяется, является ли .fixedSize источником стоимости
   ↓
3.9.44  ProMotion A/B
        что реально даёт CADisableMinimumFrameDurationOnPhone: cadence, frame time,
        hitching — а не предположение, что 120 Hz решит проблему сам по себе
```

### 7.1 Что именно измеряет 3.9.41 (уточнение, чтобы не спорить потом)

В текущей архитектуре стрим идёт через `LightStreamingRenderer` = `Text(verbatim: content)`.
Markdown там не парсится вообще, поэтому «incremental render» для потоковой ветки означает
не парсинг, а **раскладку текста**: на каждый коммит SwiftUI раскладывает **всю накопленную
строку**, а не только новый фрагмент.

Измеримое (без Instruments):

```
на каждый коммит стрима:
  accumulatedChars   — накопленная длина текста                (счётчик)
  deltaChars         — сколько добавилось с прошлого коммита   (счётчик)
  commitIntervalMs   — интервал между коммитами                (таймер)
  frameMsAroundCommit— длительность ближайшего кадра            (из канала 3.9.40)

вывод, который это даёт:
  стоимость кадра растёт с accumulatedChars → раскладывается весь текст (O(N) per update)
  стоимость кадра не зависит от accumulatedChars → раскладка инкрементальная
```

Это единственный способ отличить «инкрементально» от «целиком заново» без Instruments.

### 7.2 Параллельные измерения (чтобы не принять побочный эффект за проблему Rendering)

```
Main Thread              → загрузка, длительные операции, блокировки, sync-работа
State / Streaming Updates→ частота обновлений, сколько UI-updates на одно stream-событие,
                            coalescing/debounce
Persistence / Operation Stall → Session Open, hydration, persistence, WAL
                            (ОТДЕЛЬНАЯ линия: их миллисекунды НЕ складываются с бюджетом кадра)
Memory                   → resident memory, рост на длинном стриме, AttributeGraph
                            (проверка, а не поиск: утечки картинок закрыты ранее)
```

Две линии производительности существуют раздельно и **никогда не суммируются**:

```
PERFORMANCE
 ├── FRAME TIME      (кадр ~19 мс)     ← layout / rendering / display
 └── OPERATION STALL (Session Open 916 мс, Cache Write 842 мс, ...)  ← отдельные операции
```

---

## 8. План по этапам

```
GATE 0  серверный API: idempotency key / message id / 409 / reconciliation   ← ЗАКРЫТ (§2)
Э1      Владение текстом: один writer черновика, ясный lifecycle, регрессии
Э2      State machine + durable outbox (staged/retryable/failed)
Э3      Retry/backoff для -1001/-1005; -1005 перестаёт называться timeout
Э4      Reconciliation для 409/steer.refused поверх activeStreamId + stream/status
Э5      Канал уведомлений: лента = только переписка
Э6      Стрим: durable-состояние, продолжение после обрыва/перезапуска
Э7      Рендер: один фикс по данным 3.9.39 (кандидат — .fixedSize в fallback)
Сервер   ЕДИНСТВЕННЫЙ путь к exactly-once: клиентский ключ в /api/chat/start
         (паттерн Kanban уже реализован) — отдельное решение, вне клиента
```

## 9. Сохранить / изменить / не трогать

| | |
|---|---|
**Сохранить** | раздельные очереди кэша (3.9.38); `HermesRetryBackoff`; `PendingScheduledMessage`; `LightStreamingRenderer` |
**Изменить** | канал уведомлений; двойной `setContent`; `clearDraft`; классификация `-1005`; разбор 409 в привязку к `activeStreamId` |
**Не трогать** | `StreamingMarkdownChunkedView` и splitters (dead code); `MainThreadWatchdog`; порог 4000 до данных |

## 10. NOT VERIFIED

```
exactly-once без серверного ключа            — НЕДОСТИЖИМО (см. §2.2), не NOT VERIFIED, а REJECTED
durable outbox после жёсткого kill            — NOT VERIFIED
тело ответа 409 / steer на нашем сервере      — частично: клиент парсит activeStreamId; полное тело не снято
fallback-рендер и .fixedSize как bottleneck   — NOT VERIFIED (0 сэмплов; нужны длинные ответы)
стоимость layout .fixedSize                   — НЕ ИЗМЕРИМА body-таймером (только корреляция с hitch/freeze)
```
