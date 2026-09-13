# ARCH-001 — три вынесенных состояния: наш слой против upstream

**Статус:** решение принято, реализация — отдельная задача
**Дата:** 2026-09-12
**Контекст:** синк upstream 1.6.0, ветка `sync/upstream-1.6.0` (3.7.0)

## Что обнаружено

`ChatViewModel` после слияния содержит **две несовместимые архитектуры одного
состояния**. Это не «наш код vs их код» в смысле качества — это два владельца
одного и того же, и именно поэтому CI показывает каскады.

| Класс | В нашем `main` | В `upstream/master` | В MERGED |
|---|---|---|---|
| `ChatComposerState` | есть | **нет** | есть |
| `ChatActionsState` | есть | **нет** | есть |
| `ChatStreamState` | есть | **нет** | есть |

```
MERGED references:  composer. × 34   actions. × 28   stream. × 2
```

## В чём конфликт

Мы вынесли состояние в отдельные `@Observable` классы и **проксировали** его
через `ChatViewModel`:

```swift
// НАШЕ (main)
final class ChatComposerState { var modelCatalogGroups: [ModelCatalogGroup] = [] }

final class ChatViewModel {
    let composer = ChatComposerState()
    var modelCatalogGroups: [ModelCatalogGroup] {
        get { composer.modelCatalogGroups }
        set { composer.modelCatalogGroups = newValue }
    }
}
```

Upstream держит то же состояние **напрямую в `ChatViewModel`**:

```swift
// ИХ (upstream/master:354)
final class ChatViewModel {
    private(set) var modelCatalogGroups: [ModelCatalogGroup] = []
}
```

Слияние оставило **оба**, поэтому:
- `ambiguous use of 'modelCatalogGroups'` — два кандидата на одном call site
- `invalid redeclaration` — те же имена дважды

## Какие ошибки CI это производило

Классификация всех падений на этой ветке:

```
STRUCTURE (brace)      8+9+8   → закрыто гейтом 8
DUPLICATE decl         45+14   → закрыто гейтом 9
AMBIGUOUS dup field    24+3    → гейт 9, вторая проверка (cross-scope)
MISSING comma          2       → гейт 9 покрывает паттерн
TYPE / UNKNOWN name    ~5      → только компилятор
REGULAR "OTHER"        ~1250   → это КАСКАД от первых, не отдельные дефекты
```

Один дефект печатается как 20–400 строк. Проверка 8 и 9 убирают первый и
второй класс до пуша.

## Решение

**Upstream-модель побеждает.** Обоснование фактами, а не предпочтением:

1. **Upstream активно развивает именно эту модель.** 105 коммитов с момента
   форка меняли поля на `ChatViewModel` напрямую; наш вынос — состояние,
   замороженное на 3.6.1, к которому не возвращались.
2. **Наши классы не имеют аналога у них.** Их нельзя «взять к себе» — только
   выбросить или поддерживать форком навсегда.
3. **Форк-компенсация — тот же конфликт на уровне репо.** Оставить наш слой
   значит на каждом будущем синке заново сшивать два владельца. Это ровно то,
   от чего мы уходим в этом синке.

**Что это означает практически:**

```
УДАЛИТЬ (наши)          ChatComposerState, ChatActionsState, ChatStreamState
СОХРАНИТЬ (их)          все stored-поля на ChatViewModel
ПЕРЕПИСАТЬ (наши места) все `composer.x` / `actions.x` / `stream.x` → `x`
                        ~64 ссылки (34 + 28 + 2)
```

## Почему это НЕ сделано в этом синке

Размер: **64 правки в god-object на 7.5k строк**, из которых ни одну нельзя
проверить локально (Swift-тулчейна нет). Вслепую это даст новую волну каскадов,
и мы потратим ещё N прогонов CI, не имея базы для сравнения.

Правильный порядок: **сначала зелёный 3.7.0 на слитом виде** — чтобы (а) получить
рабочую точку отката, (б) увидеть, что ещё ломается по типам, когда дубликаты
убраны. Затем отдельная задача ARCH-001 с проверяемым шагом на каждом этапе.

## Что сейчас сделано вместо этого

Из MERGED удалены **дубликаты одного имени внутри одного типа** — те, что давали
`invalid redeclaration` без изменения архитектуры:

- `streamingAssistantMessageID`, `liveToolCalls`, `liveReasoningText`,
  `streamingScrollTrigger`, `toolCallAnchorMessageID`, `reasoningAnchorMessageID`,
  `cacheFirstReconcileScrollToken`, `responseCompletionHapticTrigger`,
  `responseCompletionNeedsTranscriptRefresh` — прокси-блок `// MARK: Stream
  delegates` удалён, остался их stored
- первый прокси approval/clarification через `pendingActionCoordinator` удалён
  (второй, через `actions`, — рабочий)
- `errorMessage` / `sendErrorMessage` / `messageActionErrorMessage` /
  `cacheErrorMessage` / `lastError` — наш stored удалён, их прокси оставлен
- `supportedReasoningEfforts` / `supportsReasoningEffort` — наш stored удалён
- 11 полей composer-состояния — наш stored удалён

## Проверка, которая это ловит

`scripts/check-duplicate-declarations.py`, гейт 9 `pipeline-precheck.py`:

- **внутри одного типа** — дубликат имени (property/func различаются, перегрузки
  проходят по сигнатуре)
- **на типе и на типе, которым он владеет** (`let composer = ChatComposerState()`
  рядом с `var composer`) — это и есть `ambiguous use of 'x'`

Калибровка обязательна: первая версия по отступу дала 2505 ложных, вторая по
«имя в >1 типе» — 53 ложных (`id` в шести независимых структурах). Только
критерий «владеет этим типом» даёт 35 настоящих.
