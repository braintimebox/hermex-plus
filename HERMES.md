# HERMES.md — рабочие правила Hermex Plus

Этот файл читается Hermes-агентом **первым** (приоритет 1, перекрывает
`AGENTS.md` и `CLAUDE.md`). Upstream его не знает → **не конфликтует при
обновлении upstream**. Написан для форка `braintimebox/hermex-plus`.

Если ты агент — начни с раздела «ЧТО ДЕЛАТЬ ПЕРВЫМ ДЕЛОМ».

---

## ЧТО ДЕЛАТЬ ПЕРВЫМ ДЕЛОМ

```bash
python3 scripts/project_snapshot.py     # статус из git — не может устареть
# затем прочитать: docs/project-snapshot.md
```

Это даёт: ветку, HEAD, версию, открытые задачи, размеры. **Без этого не начинай.**

---

## ГДЕ МЫ

| Что | Значение |
|---|---|
| Upstream | `uzairansaruzi/hermex` — **только чтение**, никогда не пишем |
| Наш репозиторий | `braintimebox/hermex-plus` |
| Ветка | `main` — **push напрямую**, без ветвей и PR |
| Сборка | GitHub Actions (`build-ipa.yml`) — **Xcode локально НЕТ** |
| Тесты | 92 файла. **Сейчас не запускаются** (известно, см. «План») |
| Доставка | GitHub Release → `/releases/latest` (не TestFlight, нет доступа) |
| API источник | `PROJECT_SPEC.md` + свой сервер. **Не выдумывать эндпоинты** |
| Версия | `VERSION` (semver) · `CHANGELOG.md` · `project.pbxproj` |

---

## ГДЕ РАБОТАТЬ (приоритет зон)

Правило: **новый код → новый файл в нашей зоне.** Тогда конфликтов при merge
не бывает вообще. Проверено на реальном merge с upstream (103 коммита).

### Зона 1 — НАШЕ, работай свободно

Конфликтов не бывает: upstream этих файлов не знает.

```
HERMES.md              ← этот файл
STATUS.md              ← план и состояние
scripts/pipeline*      ← релизный механизм
scripts/sync-upstream  ← обновление
scripts/project_snapshot.py
docs/project-snapshot.md
HermesMobile/MainThreadWatchdog.swift
HermesMobile/HermexLogger.swift
HermesMobile/Features/Chat/QuoteReplyBanner.swift
HermesMobile/Features/Chat/SavedMessagesView.swift
HermesMobile/Features/Chat/ScheduledMessagesView.swift
HermesMobile/Features/Chat/SessionPickerForForward.swift
HermesMobile/Models/PendingScheduledMessage.swift
HermesMobile/Models/SavedMessage.swift
```

### Зона 2 — ЯДРО UPSTREAM, знай цену

Эти файлы upstream тоже правит. **Каждая наша строка здесь = конфликт при
следующем merge.** Цифры — реальные, из merge 103 коммитов upstream:

| Файл | Наших строк | Даёт конфликтов |
|---|---|---|
| `Features/Chat/ChatView.swift` | +1379 | **26 блоков** |
| `Features/Chat/ChatTranscriptSupportingViews.swift` | +299 | 21 |
| `Features/Chat/ChatViewModel.swift` | +1090 | 17 |
| `Features/Chat/ChatTranscriptView.swift` | +465 | 16 |
| `Features/Chat/ChatScrollPolicy.swift` | +66 | 3 |
| `Features/Chat/ChatStreamCoordinator.swift` | +121 | 3 |
| `Features/Chat/MarkdownRenderer.swift` | — | 5 |
| `Features/SessionList/SessionListView.swift` | +313 | 5 |
| `Models/*`, `Networking/*`, `Persistence/*` | — | по 1–3 |
| `HermesMobile.xcodeproj/project.pbxproj` | — | **10** |

**Всего в ядре: ~3420 наших строк → 111 конфликтов из 140.**

Если правки в ядре неизбежны:
1. Держи их **минимальными**
2. Помечай `// MARK: - Plus`
3. Помни: merge = конфликт ровно здесь

### Зона 3 — НЕ ТРОГАТЬ (upstream-документация)

Правка = конфликт без пользы. Перекрывается через `HERMES.md`.

```
AGENTS.md · CLAUDE.md · CONTEXT.md · TESTFLIGHT.md
DEVELOPMENT.md · CONTRACT_TESTS.md · PROJECT_INTENT.md · CONTRIBUTING.md
docs/agents/* (частично upstream)
```

### Зона 4 — ОТСУТСТВУЕТ, не искать

Инструкции upstream ссылаются на файлы, которых нет:

```
CURRENT.md                    ← не существует (gitignored, у upstream локальный)
docs/project-metrics.md       ← не существует
scripts/project_metrics.py    ← не существует
```

**Не пытайся их найти или создать.** Статус живёт в `docs/project-snapshot.md`.

---

## ИНВАРИАНТЫ (не нарушать)

1. **push в `main` напрямую** — без ветвей, без PR, без issue-процесса
2. **Один релиз = одна версия.** Тег `vX.Y.Z` не переиспользуется. Гейт проверит
3. **Upstream — только чтение.** Никогда не пушить в `uzairansaruzi/hermex`
4. **Ядро правим осознанно** — см. Зону 2, знай цену конфликта
5. **API не выдумывать.** Источник — `PROJECT_SPEC.md` или свой сервер
6. **Tolerant decoding** — опциональные поля в `Codable`, не падать на новых
7. **Деструктивные команды** (`rm -rf`, `push --force`) — предложить, не выполнять

---

## МЕХАНИЗМ РЕЛИЗА

```bash
python3 scripts/pipeline status              # где мы
python3 scripts/pipeline check               # 5 гейтов (локально)
python3 scripts/pipeline release --note "…"  # bump + CHANGELOG + гейты
python3 scripts/pipeline sync                # план merge с upstream
```

`git push` защищён pre-push хуком → `scripts/pipeline-precheck.py`:
```
1. release invariants   VERSION == CHANGELOG == pbxproj, тег не дубль
2. conflict markers     забытые <<<<<<< в коде
3. pbxproj registration новый .swift без регистраций
4. upstream-owned       предупреждение при правке чужого файла
5. upstream drift       разрыв с upstream измерен
```

Установка хука (не версионируется, нужна после свежего клона):
```bash
python3 scripts/pipeline install
```

Ручной релиз (полный цикл с ожиданием сборки и скачиванием IPA):
```bash
python3 scripts/pipelines/release_hermesplus.py --next 3.7.0 --close 1 3 --note "…"
```

---

## ИНСТРУМЕНТЫ — РЕЕСТР (проверь здесь ПЕРЕД созданием нового)

**ПРАВИЛО: прежде чем писать новый скрипт — посмотри этот список.**
Если задача уже покрыта — используй существующее. Если создал новый —
**немедленно добавь его сюда**, иначе он станет мёртвым грузом.

### Релиз и версия

```
scripts/pipelines/release_hermesplus.py    ← ЕДИНСТВЕННЫЙ релизный вход
    статус   кто мы: версия/ветка/head/pre-push/upstream drift
    check    5 гейтов локально (без push)
    sync     план merge с upstream (сколько коммитов и конфликтов)
    install  включить pre-push гейт (core.hooksPath → .githooks)
    install-server  поставить/обновить сервер логов на этой машине (см. ops/)
    release  полный цикл: bump → CHANGELOG → close items → snapshot → gate
             → push → wait CI → download IPA
             python3 scripts/pipelines/release_hermesplus.py release \
                 --next 3.7.0 --close 1 3 --note "…" [--dry-run]

    ⚠ без аргументов печатает help, а НЕ релиз (защита от случайного запуска)

scripts/pipeline-precheck.py                ← 5 гейтов (вызывается хуком И CI)
scripts/release-check.py                    ← 5 инвариантов (вызывается precheck)
.githooks/pre-push                          ← В РЕПОЗИТОРИИ (не в .git/hooks!)
scripts/sync-upstream                       ← merge с upstream (--apply/--record-base)

❌ scripts/pipeline — УДАЛЁН 2026-09-11. Слит в release_hermesplus.py (был дубль
   логики: bump/CHANGELOG/gate в двух файлах → расхождение поведения).
❌ scripts/bump-version.py — УДАЛЁН 2026-09-11. Был дубль: бампал VERSION+pbxproj,
   CHANGELOG оставлял человеку → версия уходила без записи. Замена: release.
```

### Хост-сервисы (ops/)

```
ops/hermex-logs/server.py                   ← ИСТОЧНИК сервера логов (порт 8912)
ops/hermex-logs/hermex-logs.service.template ← шаблон systemd-юнита ({{INSTALL_DIR}})
ops/README.md                               ← что это, как ставить, что уже ломалось
python3 scripts/pipelines/release_hermesplus.py install-server [--dir PATH]

    ⚠ Копии в ~/.hermes/_projects/hermex-logs/ и ~/.config/systemd/user/ — это
      УСТАНОВОЧНЫЕ ЦЕЛИ, не источник. Править в ops/, ставить командой.

### Статус

```
docs/project-snapshot.md                   ← ЕДИНСТВЕННЫЙ источник статуса
    генерируется scripts/project_snapshot.py из git → устареть не может
    читать при старте работы, не править руками

docs/hermesplus-status.yaml                ← хранилище ЗАДАЧ (id/priority/status)
    читает и обновляет release_hermesplus.py (--close N)
    это не «статус проекта», а список треков

❌ STATUS.md — упразднён 2026-09-11. Дублировал project-snapshot.md.
```

### Обновление upstream

```
scripts/sync-upstream                      ← merge (НЕ rebase)
    --status  разрыв, база, зона конфликтов
    --plan    что будет при merge
    --apply   выполнить merge
    --record-base  зафиксировать новую базу
```

### Прочее

```
scripts/check-swift-file-sizes  ← лимит 500 LOC на файл (найдено: ChatComposerView 1254)
scripts/upstream-watch          ← слежка за hermes-webui (сервер)
scripts/webui-json              ← JSON-запросы к серверу (нужен HERMES_WEBUI_BASE_URL)
scripts/verify_kanban_reference_server.py
```

### GitHub Actions

```
.github/workflows/build-ipa.yml          ← сборка IPA на push
.github/workflows/pr-ci.yml              ← тесты (триггер: pull_request → не срабатывает!)
.github/workflows/upstream-watch.yml     ← слежка hermes-webui
.github/workflows/upstream-app-watch.yml ← слежка iOS-клиента (не в git)
```

---

## АНТИПАТТЕРНЫ (из аудита)

Не воспроизводи эти ошибки — они уже стоили нам техдолга:

1. **Два инструмента для одной задачи.** Был `bump-version.py` + релизный
   скрипт; CHANGELOG писал человек → забывалось. Один путь: `scripts/pipeline`.
2. **Инструмент без упоминания в инструкциях = мёртвый.** `release_hermesplus.py`
   существовал и работал, но 0 упоминаний → агент о нём не знал.
3. **Правка ядра вместо нового файла.** 3420 строк разлиты по 6 чужим файлам
   → 111 конфликтов при каждом merge.
4. **Инструкции, ссылающиеся на несуществующее.** `CURRENT.md`,
   `project-metrics.md` — агент искал и не находил.
5. **Три источника статуса.** Должен быть один: `docs/project-snapshot.md`.

---

## ТЕКУЩАЯ РАБОТА — план в три слоя

Полный план и детали: **`STATUS.md`** (наш файл, upstream его не знает).

```
Слой 1 — инструкции и процесс      [почти готов]
  ✓ pipeline + precheck (5 гейтов)
  ✓ sync-upstream (merge, не rebase)
  ✓ project_snapshot (статус из git)
  ✓ HERMES.md (этот файл)
  → README.md — витрина, /releases/latest
  → build-ipa.yml — создание Release

Слой 2 — защита                    [НЕ НАЧАТ · обязателен ДО слоя 3]
  → тесты в CI (92 файла, сейчас 0 прогонов)
  → check-swift-file-sizes в gate

Слой 3 — структура кода            [НЕ НАЧАТ · только после слоя 2]
  → вынести 3420 строк из ядра в HermesMobile/Plus/
  → маркеры // MARK: - Plus в неизбежных правках ядра
```

**ПРАВИЛО: не начинать слой 3 без слоя 2.** Рефакторинг без тестов
порождает ровно тот техдолг, который мы устраняем.

---

## ОБНОВЛЕНИЕ С UPSTREAM

```bash
python3 scripts/sync-upstream --status   # разрыв, база, зона конфликтов
python3 scripts/sync-upstream --plan     # что будет при merge
```

Механика: **`merge`, не `rebase`.** Rebase падает на 5-м коммите из 376
(бухгалтерия `CHANGELOG` — 158 наших правок против 3). Merge даёт
предсказуемые 32 файла / 140 блоков, повторяемо.

База отслеживания: тег `plus/base-vX.Y.Z`. После merge — передвинуть.

---

## ЧЕГО ЗДЕСЬ НЕТ (не ищи)

- GitHub Issues / PR-процесса — мы работаем пушем в main
- Xcode, симулятора, XcodeBuildMCP — только CI
- TestFlight, App Store Connect — нет доступа
- Ветки `master` у upstream — только `origin/master` как зеркало для чтения
