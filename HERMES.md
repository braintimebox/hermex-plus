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
| Тесты | 92 файла / 1579 `func test`. **Запускаются и являются гейтом** — `build-ipa.yml` идёт `guard → test → build`, IPA пакуется только после зелёного прогона |
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
CONVENTIONS.md         ← правила репо (почему каждая норма существует)
scripts/pipelines/release_hermesplus.py  ← релизный механизм
scripts/pipeline-precheck.py
scripts/lint-tests.py
scripts/check-doc-references.py          ← гейт 7
scripts/upstream-rehearse.py
scripts/sync-upstream  ← обновление
scripts/project_snapshot.py
docs/project-snapshot.md
docs/hermesplus-status.yaml
docs/agents/testing.md
docs/agents/upstream-sync-plan.md
ops/                   ← хост-сервисы (логи)
.githooks/pre-push
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
python3 scripts/pipelines/release_hermesplus.py status    # где мы
python3 scripts/pipelines/release_hermesplus.py check     # 6 гейтов (локально)
python3 scripts/pipelines/release_hermesplus.py sync      # план merge с upstream
python3 scripts/pipelines/release_hermesplus.py release --next 3.7.0 --note "…"
```
⚠ Без аргументов скрипт печатает help, а **не** релиз.

`git push` защищён pre-push хуком → `scripts/pipeline-precheck.py`:
```
1. release invariants   VERSION == CHANGELOG == pbxproj, тег не дубль
2. conflict markers     забытые <<<<<<< в коде
3. pbxproj registration новый .swift без регистраций
4. upstream-owned       предупреждение при правке чужого файла
5. upstream drift       разрыв с upstream измерен
6. test-lint            тесты не кодируют гонку как контракт
7. doc references       документ не ссылается на несуществующий файл
```

Гейты 6 и 7 (`scripts/lint-tests.py`, `scripts/check-doc-references.py`) —
**блокирующие**. Гейт 6 ловит механически:
- литеральный порядок запросов, где оба эндпоинта идут через `async let`
- poll-цикл, который молча истекает без `XCTFail`

Гейт 7 сканирует каждую ссылку вида `scripts/...`, `docs/...`, `.githooks/...`
в `HERMES.md`, `CONVENTIONS.md`, `AGENTS.md` и `docs/agents/*.md` и падает, если
цели нет. Он существует потому, что антипаттерн №4 из этого файла случился дважды:
`CURRENT.md`/`project-metrics.md`, затем `scripts/pipeline`/`STATUS.md`.

Правило, которое можно проверить механически — проверяется, а не описывается.
Заметка просит помнить и судить; гейт не спрашивает.

Гейт 7 покрыт юнит-тестами: `python3 scripts/tests/test_doc_references.py`
(10 кейсов — что обязан ловить и что обязан пропускать). Правишь гейт — прогони их.
Причина, по которой тесты написаны файлом, а не однострочником в shell: `printf`
в bash калечит кириллицу и эмодзи, из-за чего проверка показывала «сломано» там,
где всё работало. Сравнение строк с не-ASCII — только из файла.

Проверки 4 и 5 — **advisory**: предупреждают, но не блокируют. Раньше их вывод
терялся — итог говорил «ALL CHECKS PASSED», хотя выше было предупреждение.
Теперь advisory повторяются под вердиктом (см. `ADVISORIES` в скрипте).

**Что делать с advisory**: не игнорировать и не «починить» правкой чужого файла.
Правка upstream-owned стоит merge-конфликта на каждом будущем sync — факт
переносим в `HERMES.md` / `docs/agents/`, а не в `CONTRIBUTING.md`.

### Тесты и CI — кто что запускает

```
build-ipa.yml    push в main      guard → test → build (IPA только после тестов)
pr-ci.yml        pull_request     тот же suite, только для веток
```

**Важно:** работа идёт **напрямую в `main`**, поэтому рабочий триггер — первый.
`CONTRIBUTING.md` описывает PR-флоу и устарел (правит upstream-owned файл — нельзя).

Локальной компиляции Swift **нет** (Linux без тулчейна): гейт не ловит ошибки
типов и имён полей, их видит только CI (~11 мин). Опыт: `SessionSummary.sessionId`
vs `CachedSession.sessionID` прошёл гейт и уронил сборку.

Как писать тесты, которые не врут — `docs/agents/testing.md` (7 разобранных
случаев из этого репо, каждый с коммитом-фиксом). Читать ПЕРЕД правкой теста:
там записаны провалы, которые эта сюита реально производила — ассерт на порядок
`async let`, чтение кэша сразу после async-записи, wait-хелпер, тихо истекающий
без `XCTFail`.

Перед upstream-синком — `docs/agents/upstream-sync-plan.md`: набор конфликтов,
правило разрешения для каждого класса файлов, известные ловушки. Сначала прогнать
`python3 scripts/upstream-rehearse.py`; план написан против его вывода.

**Открытый архитектурный вопрос — `docs/agents/arch-001-extracted-state.md`:**
три вынесенных состояния (`ChatComposerState`, `ChatActionsState`, `ChatStreamState`)
— наши, у upstream их нет; решение upstream-модель-побеждает, реализация отдельной
задачей. Читать перед правками `ChatViewModel`, чтобы не поддержать второй владелец.

**Три слоя работы — `docs/agents/sync-layers.md`.** Читать, когда что-то упало:
последовательность (git, структура), сборка (Swift, только CI), pipeline
(публикация). Провал в одном слое не чинится инструментом другого — это и была
ошибка, из-за которой один потерянный `}` искали через `gh run list` пять прогонов.

⚠ УДАЛЁН: `docs/agents/domain.md` — upstream его удалил, мы приняли удаление
(решение зафиксировано в плане синка). Указатели, которые в нём жили, теперь здесь.

Установка хука (не версионируется, нужна после свежего клона):
```bash
python3 scripts/pipelines/release_hermesplus.py install
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
    status   кто мы: версия/ветка/head/pre-push/upstream drift
    check    6 гейтов локально (без push)
    sync     план merge с upstream (сколько коммитов и конфликтов)
    install  включить pre-push гейт (core.hooksPath → .githooks)
    install-server  поставить/обновить сервер логов на этой машине (см. ops/)
    release  полный цикл: bump → CHANGELOG → close items → snapshot → gate
             → push → wait CI → download IPA
             python3 scripts/pipelines/release_hermesplus.py release \
                 --next 3.7.0 --close 1 3 --note "…" [--dry-run]

    ⚠ без аргументов печатает help, а НЕ релиз (защита от случайного запуска)

scripts/pipeline-precheck.py                ← 9 гейтов (вызывается хуком И CI)
scripts/lint-tests.py                       ← гейт 6: тесты-гонки (вызывается precheck)
scripts/check-doc-references.py             ← гейт 7: ссылки на несуществующее
scripts/check-swift-structural-balance.py   ← гейт 8: баланс скобок против ОБОИХ родителей
                                              (union двух сторон конфликта теряет `}` в конце
                                               стороны; Swift показывает это лавиной
                                               несвязанных ошибок — стоило 5 прогонов CI)
scripts/check-duplicate-declarations.py     ← гейт 9: одно объявление дважды в одном типе
                                              (`invalid redeclaration of 'x'` × N = один
                                               склеенный блок; калиброван по enclosing-типу,
                                               var vs func и сигнатуре — иначе 2505 ложных)
scripts/tests/test_doc_references.py        ← юнит-тесты гейта 7 (10 кейсов, запускать после правки)
docs/agents/sync-layers.md                  ← три слоя: последовательность / сборка / pipeline
scripts/upstream-rehearse.py                ← разведка upstream-merge (рабочий репо не трогает)
    --keep  оставить клон для ручного разбора (по умолчанию клон удаляется)
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
ops/hermex-logs/watchdog.py                 ← cron-скрипт: читает JSONL, алертит на фризы
ops/hermex-logs/hermex-logs.service.template ← шаблон systemd-юнита ({{INSTALL_DIR}})
ops/README.md                               ← что это, как ставить, что уже ломалось
python3 scripts/pipelines/release_hermesplus.py install-server [--dir PATH]

    ⚠ Копии в ~/.hermes/_projects/hermex-logs/ и ~/.config/systemd/user/ — это
      УСТАНОВОЧНЫЕ ЦЕЛИ, не источник. Править в ops/, ставить командой.

    Владелец каждого артефакта после установки:
      server.py       → ~/.hermes/_projects/hermex-logs/  (install-server)
      systemd unit    → ~/.config/systemd/user/           (install-server)
      watchdog.py     → ~/.hermes/scripts/                (install-server)
      cron-джоба      → зарегистрирована в Hermes cron по ИМЕНИ файла
                        (hermex_logs_watchdog.py) — install-server её НЕ трогает.

    ⚠ Правка ops/hermex-logs/watchdog.py обновляет сторож только после
      `install-server`: cron резолвит скрипт по имени, то есть всегда берёт
      установленную копию. Забыл переустановить = сторожит старой логикой.

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
scripts/benchmark-math-formatting + scripts/benchmarks/MathFormatting.swift
                                ← замер стоимости форматирования math в стриминге
```

### GitHub Actions

```
.github/workflows/build-ipa.yml          ← сборка IPA на push в main (guard → test → build)
.github/workflows/pr-ci.yml              ← тот же suite для веток; триггер pull_request
.github/workflows/upstream-watch.yml     ← слежка hermes-webui (сервер)
.github/workflows/upstream-app-watch.yml ← слежка iOS-клиента (наш форк)
.github/workflows/internal-testflight.yml / external-testflight.yml ← TestFlight (не наш путь, нет доступа)
```

**Про ветки:** `pr-ci.yml` срабатывает только на `pull_request`. Пуш ветки без PR
не запускает **ничего** — сначала PR, потом CI. У `pr-ci.yml` есть
`cancel-in-progress: true`, у `build-ipa.yml` — нет: каждый push в `main` доводит
macOS-джобу до конца.

---

## АНТИПАТТЕРНЫ (из аудита)

Не воспроизводи эти ошибки — они уже стоили нам техдолга:

1. **Два инструмента для одной задачи.** Был `bump-version.py` + релизный
   скрипт; CHANGELOG писал человек → забывалось. Один путь:
   `scripts/pipelines/release_hermesplus.py`.
2. **Инструмент без упоминания в инструкциях = мёртвый.** `release_hermesplus.py`
   существовал и работал, но 0 упоминаний → агент о нём не знал.
3. **Правка ядра вместо нового файла.** 3420 строк разлиты по 6 чужим файлам
   → 111 конфликтов при каждом merge.
4. **Инструкции, ссылающиеся на несуществующее.** `CURRENT.md`,
   `project-metrics.md`, затем `scripts/pipeline`, `scripts/bump-version.py`,
   `STATUS.md` — агент искал и не находил. Лечится не вниманием, а гейтом 7
   (`scripts/check-doc-references.py`): ссылка на несуществующее роняет push.
5. **Три источника статуса.** Должен быть один: `docs/project-snapshot.md`.
6. **Удалил скрипт — не убрал упоминания.** `scripts/pipeline`, `bump-version.py`
   и `STATUS.md` удалены 2026-09-11, но их продолжали подавать как рабочие пути
   README-инструкции и докстринг самого гейта. Удаление = отдельная задача с
   поиском ссылок, а не `rm`.

---

## ТЕКУЩАЯ РАБОТА — план в три слоя

Полный план — `docs/hermesplus-status.yaml` (список треков) + `docs/project-snapshot.md`
(состояние из git). `STATUS.md` упразднён 2026-09-11 — не искать.

```
Слой 1 — инструкции и процесс      [готов]
  ✓ release_hermesplus.py + pipeline-precheck (9 гейтов)
  ✓ sync-upstream (merge, не rebase)
  ✓ upstream-rehearse.py (разведка конфликтов, 0 CI-минут)
  ✓ project_snapshot (статус из git)
  ✓ docs/agents/sync-layers.md (три слоя: последовательность / сборка / pipeline)
  ✓ HERMES.md (этот файл)

Слой 2 — защита                    [готов]
  ✓ тесты в CI как гейт (92 файла / 1579 тестов; guard → test → build)
  ✓ xcresult читается и печатает текст ассерта в лог при падении
  → check-swift-file-sizes в gate — НЕ сделан (лимит 500 LOC, есть файл 1254)

Слой 3 — структура кода            [НЕ НАЧАТ · только после слоя 2]
  → вынести ~3420 строк из ядра в HermesMobile/Plus/
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
