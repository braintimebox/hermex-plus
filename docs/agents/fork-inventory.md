# Инвентаризация форка — что наше, что их

Обновлять при каждом синке upstream. Источник правды — git, но этот список
фиксирует ФИЧИ, а не файлы: файл может жить, а фича отвалиться.

## Наши фичи — у upstream НЕТ вообще

Проверять после каждого синка: файл существует И вызывается.

| Фича | Файл | Вызовов |
|---|---|---|
| Reply (цитирование) | `Features/Chat/QuoteReplyBanner.swift` | ≥3 |
| Save (сохранённые) | `Features/Chat/SavedMessagesView.swift` | ≥15 |
| Schedule (отложенные) | `Features/Chat/ScheduledMessagesView.swift` | ≥7 |
| Forward (пересылка) | `Features/Chat/SessionPickerForForward.swift` | ≥3 |
| Clarification (вопросы агента) | `Features/Chat/ClarificationRequestOverlay.swift` | ≥3 |
| Логирование | `HermexLogger.swift` | ≥7 |
| Детектор зависаний | `MainThreadWatchdog.swift` | ≥7 |
| Fade при печати | `StreamingTextFadeRenderer.swift` + `StreamingTextFade.swift` | ≥6 |
| Плавная печать (drain) | `StreamingWordDrain.swift` | ≥3 |
| Ссылки-превью | `TranscriptLinkPreview.swift` | — |
| Медиа в транскрипте | `TranscriptMediaView.swift` | — |
| Модели | `Models/SavedMessage.swift`, `Models/PendingScheduledMessage.swift` | — |
| Skills: Personal / Built-in бакеты | `Features/Skills/SkillsView.swift` (+499), `SkillsViewModel.swift` (+49) | ≥5 |
| Skills: Plugins / Hooks с живыми данными | там же (`originGroupedPlugins`) | ≥5 |
| Skills: breadcrumb в навбаре | там же (`originTitleHeader`) | ≥2 |
| Skills: поиск/фильтр, вкл/выкл | там же (`setSkill`, `togglingSkillNames`) | ≥5 |
| `origin` в модели Skills | `Models/Skills.swift` (+61) | сервер отдаёт поле, клиент делит | 
| Tasks: создание / запуск / расписание / удаление | `Features/Tasks/TasksView.swift` (+102) | ≥10 |

**Важно:** в `Features/Tasks/`, `Features/Skills/` upstream после 1.6.0 **не менял ничего**
(0 файлов). Наши правки там не конфликтуют — переносятся как есть.

## Где мы и upstream меняли одно и то же

Решение по каждому принимается отдельно. Не «чей файл», а что лечит.

| Область | Наш подход | Их подход | Решение |
|---|---|---|---|
| Скролл | `ScrollOwnershipState` (владелец .app/.user) | `FollowLatch` (событийный латч) | **их** — покрывают те же сценарии + 12 своих |
| ↓ кнопка | мгновенный сброс cooldown | `dragSettleDelay` 0.16s (ждём) | **наш** — их задержка заметна |
| Выделение текста | — | `ResponseTextSelection.swift` (#456/457) | **их** (не наше, ошибочно считалось нашим) |
| Fade при печати | есть | нет | **наш** |
| Перф транскрипта | `EquatableView`-обёртка | `ChatTranscriptMessageBlock` + `.equatable()` | **их** (полнее) |

## Наблюдения на устройстве (upstream 1.6.0)

- Tasks, Composer, Usage — заметно лучше
- Скролл — лучше
- Load older — возможно лучше
- ↓ кнопка — **с задержкой**: не срабатывает, пока скролл не остановится
  (`dragSettleDelay` 0.16s — их сознательный выбор против флик-детекта)
- Не проверено: нагрузка ТЗ в чате

## Мёртвые зоны (проверено, не исправлено)

1. Нет локального Swift-парсера — 11 текстовых гейтов пропускают файл с
   синтаксическими ошибками. CI — единственный компилятор.
2. ARCH-001: `ChatComposerState`/`ChatActionsState`/`ChatStreamState` — наши,
   у upstream нет; 35 cross-scope имён ждут разведения.
3. `wait_build()` есть в `scripts/pipelines/release_hermesplus.py`, но глядит
   на `main` и не подключён к pre-push — CI гоняется руками.
4. `AGENTS.md` требует читать `CURRENT.md`; файла нет (gitignored).
5. README не входит в контракт версии (гейт 1 проверяет VERSION/CHANGELOG/pbxproj).
