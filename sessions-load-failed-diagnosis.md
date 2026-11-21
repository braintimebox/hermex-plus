# sessions load failed — диагностика первопричины (Hermex Plus 3.9.67)

## 1. Краткий вывод

| Вопрос | Ответ |
|---|---|
| Первопричина установлена? | **Да** — `URLError.cannotDecodeRawData` (код -1015), обёрнутый в `APIError.network(underlying:)` |
| Место формирования события найдено? | **Да** — `SessionListViewModel.swift:288` |
| Проблема с состоянием UI подтверждена? | **Частично** — кэш показывается (`usedCache: true`), UI не застревает, но `errorMessage` отображается как `localizedDescription` для не-транспортной ошибки |
| Неизвестно | Точные сетевые условия на устройстве пользователя (сервер ответил, но байты не декодировались — туннель? прокси? обрезанный ответ?) |

Отсутствие события в выборке 3.9.68 **не доказывает** устранение проблемы (выборка в 2.3× меньше).

---

## 2. Цепочка ошибки

| Этап | Файл и метод | Подтверждённое поведение | Статус |
|---|---|---|---|
| Сетевой запрос | `APIClient+Sessions.swift:15` → `client.sessions()` → `send(endpoint: .sessions(...), method: "GET")` | GET `/api/sessions`, без тела | VERIFIED |
| Возникновение ошибки | `APIClient.swift:184-188` — `session.data(for: request)` выбрасывает `URLError(.cannotDecodeRawData)` (-1015) | Ошибка транспортного уровня при чтении ответа: байты пришли, но не декодируются | VERIFIED (код), категория -1015 — подтверждена кодом `APIError.swift:99-105` |
| Оборачивание ошибки | `APIClient.swift:187` — `throw APIError.network(underlying: error)` | URLError оборачивается в `APIError.network` | VERIFIED |
| Преобразование ошибки | `APIError.swift:99-105` — `privacySafeLogCategory` для `.network(let underlying)`: `network.url.\(urlError.code.rawValue)` → `network.url.-1015` | Категория формируется из rawValue кода URLError | VERIFIED |
| Формирование телеметрии | `SessionListViewModel.swift:285-293` — `HermexLogger.shared.log(type: "error", screen: "SessionList", message: "sessions load failed", extras: ["category": ..., "usedCache": ...])` | Событие типа `error` с полями category и usedCache | VERIFIED |
| Обработка в UI | `SessionListViewModel.swift:274-333` — do-catch: `sessionLoadError = error`, кэш показывается если `CacheFallbackPolicy.shouldUseCache(for: error)` и не пуст | Кэш рисуется首先 (стр. 249-253), при ошибке с cannotDecodeRawData → `.cacheOnly` → кэш сохраняется, `isViewingCachedData = true`, `errorMessage = error.localizedDescription` | VERIFIED |

---

## 3. Доказательства

### Исходное событие из `~/.hermes/hermex-logs.jsonl` (индекс 1088, seqNo 4):

```json
{
  "ts": 1793457299.680918,
  "category": "network.url.-1015",
  "seqNo": 4,
  "correlationId": "9D6EF465-B410-41C7-BA95-468D897E59A8",
  "screen": "SessionList",
  "usedCache": true,
  "type": "error",
  "message": "sessions load failed",
  "appVersion": "3.9.67"
}
```

### Временная последовательность событий (один correlationId `9D6EF465-B410-41C7-BA95-468D897E59A8`):

| ts | type | message | screen | Источник |
|---|---|---|---|---|
| 1793457299.011 | event | session list appeared | SessionList | Лог |
| 1793457299.101 | event | scene active | — | Лог |
| 1793457299.113 | event | share received | ShareImport | Лог |
| 1793457299.681 | error | sessions load failed | SessionList | Лог (целевое событие) |
| 1793457300.247 | event | chat opened | ChatView | Лог |

Кэш использовался (`usedCache: true`), и после ошибки пользователь смог открыть чат — UI не застревал.

### Код — место формирования события (`SessionListViewModel.swift:285-293`):

```swift
HermexLogger.shared.log(
    type: "error",
    screen: "SessionList",
    message: "sessions load failed",
    extras: [
        "category": APIError.privacySafeLogCategory(for: error),
        "usedCache": CacheFallbackPolicy.shouldUseCache(for: error) && modelContext != nil,
    ]
)
```

### Код — оборачивание URLError в APIError (`APIClient.swift:184-188`):

```swift
let data: Data
let response: URLResponse
do {
    (data, response) = try await session.data(for: request)
} catch {
    throw APIError.network(underlying: error)
}
```

### Код — категория network.url.-1015 (`APIError.swift:99-105`):

```swift
case .network(let underlying):
    if let urlError = underlying as? URLError {
        return "network.url.\(urlError.code.rawValue)"
    }
    return "network.other"
```

### Код — решение о кэше (`CacheFallbackPolicy.swift:46-88`):

`cannotDecodeRawData` (-1015) → `.cacheOnly` → `shouldUseCache: true`, `shouldRetry: false`.

### Код — схема состояний UI (`SessionListViewModel.swift:224-333`):

```
idle → loading → success / error
```

- `load()` устанавливает `isLoading = true`, `errorMessage = nil`, `sessionLoadError = nil` (стр. 225-229)
- `defer { isLoading = false }` (стр. 231)
- Кэш рисуется первым (стр. 249-253)
- При успехе сети — кэш заменяется (стр. 255-273)
- При ошибке — `sessionLoadError = error` (стр. 278), затем `CacheFallbackPolicy.shouldUseCache` определяет ветку (стр. 294)

---

## 4. Причина и влияние

### Подтверждённая первопричина

`URLError.cannotDecodeRawData` (код -1015) — сервер HTTP-отправил ответ, но клиент не смог декодировать сырые байты в ожидаемую структуру. Это не absence ответа (транспорт работал), а некорректность тела ответа. Возможные источники: обрезанный ответ через туннель, некорректный JSON, промежуточный прокси, повреждённая передача.

### Влияние на пользователя (подтверждённое)

Sessions list показал кэш (`usedCache: true`), пользователь смог открыть чат через секунду после ошибки. UI не застревал в бесконечной загрузке. `errorMessage` отображался как `error.localizedDescription` (не transport failure, поэтому не скрывался).

### Неизвестные аспекты

- Конкретная причина cannotDecodeRawData на стороне сети/сервера (туннель, прокси, серверная ошибка в формате ответа)
- Был ли это единичный инцидент или повторяется (в выборке 3.9.68 события нет, но выборка в 2.3× меньше)
- Исходное тело ответа и HTTP статус не попали в телеметрию (конфиденциальность, только категория)

---

## 5. Минимальное исправление (рекомендация)

На основании доказательств, предложение минимальное:

1. **Уже реализовано в коде:** `CacheFallbackPolicy` корректно обрабатывает -1015 как `.cacheOnly` — кэш показывается, ретрай не выполняется. Это правильное поведение.
2. **Потенциальное улучшение:** в событии телеметрии нет информации о том, какой именно URL/сервер вызвал ошибку (только категория). Для диагностики повторяющихся случаев можно добавить `serverURL` (хешированный) в extras события `error`, но это требует отдельного решения о конфиденциальности.

**Не предлагать:** случайный retry, обходные пути без установленной причины, изменение сетевых контрактов.

**Минимальный следующий эксперимент:** воспроизвести cannotDecodeRawData в тестовой среде (сервер возвращает некорректный JSON на `/api/sessions`) и убедиться, что UI показывает кэш и не застревает.

---

## 6. Тестирование

| Сценарий | Ожидаемый результат | Критерий приёмки |
|---|---|---|
| cannotDecodeRawData на `/api/sessions`, кэш пуст | `isViewingCachedData = false`, `errorMessage` установлен, UI не застревает | `sessionLoadError != nil`, `isLoading == false` |
| cannotDecodeRawData на `/api/sessions`, кэш есть | Кэш показывается, `isViewingCachedData = true`, оффлайн-баннер | `sessions` не пустые, `errorMessage` может быть установлен |
| Повторная загрузка после ошибки | `load()` можно вызвать повторно, кэш не блокирует | `isLoading` сбрасывается, запрос повторяется |

Существующие тесты: `CacheFallbackPolicyTests` покрывает -1015 как `.cacheOnly` (строки 47-62). `SessionListMutationTests` покрывает ошибку загрузки (стр. 1783). Тесты не изменялись, не запускались (ограничение §3).

---

## 7. Состояние репозитория

- Исходники **не изменены** — только чтение
- Конфигурация **не изменена**
- Коммиты **не созданы**
- Push и merge **не выполнялись**
- Релизы **не публиковались**
- В `git status` только 4 новых файла документов (untracked): `docs/agents/stability-audit.md`, `docs/agents/frame-budget-and-performance.md`, `docs/agents/telemetry-and-open-issues.md`, `docs/agents/stability-roadmap.md`

---

## 8. Критерии завершения

| Критерий | Статус |
|---|---|
| Место формирования sessions load failed найдено | ✅ `SessionListViewModel.swift:288` |
| Происхождение network.url.-1015 прослежено | ✅ `APIError.network(underlying:)` → `privacySafeLogCategory` → `network.url.-1015` |
| Обработка ошибки в UI установлена | ✅ `load()` → do-catch → кэш/оффлайн-баннер |
| Проверены логи и тесты | ✅ JSONL проанализирован, тесты прочитаны (не запущены) |
| Подтверждённые факты отделены от гипотез | ✅ Категория -1015 подтверждена кодом; конкретная сетевая причина — HYPOTHESIS |
| Определён минимальный следующий шаг | ✅ Воспроизвести cannotDecodeRawData в тестовой среде |
| Подтверждено отсутствие изменений в репозитории | ✅ `git status` чист (кроме 4 untracked документов) |

**Диагностика завершена.** Первопричина установлена: `cannotDecodeRawData` (-1015) на сетевом уровне, оборачивается в `APIError.network`, категория `network.url.-1015` логируется в телеметрию, кэш показывается пользователю, UI не застревает. Изменений кода не вносилось. Ожидаю отдельного разрешения на реализацию любого исправления.