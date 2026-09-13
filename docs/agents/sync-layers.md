# Слои работы над синком — три разные сущности

Три вещи, которые легко слить в голове в одну кашу «синк/сборка/CI» и потом
пять итераций гоняться за симптомом вместо слоя. Здесь они разделены, потому что
у каждой **свой владелец, свой инструмент и свой признак готовности**.

## Коротко

| Слой | Владелец | Инструмент | Готов, когда |
|---|---|---|---|
| **1. ПОСЛЕДОВАТЕЛЬНОСТЬ** | git | `sync`, `merge`, разрешение конфликтов | 0 маркеров, структура цела |
| **2. СБОРКА** | Swift-компилятор в CI | `pr-ci` / `build-ipa` | компилируется |
| **3. PIPELINE** | `release_hermesplus.py` | `status` / `check` / `release` | версия опубликована с артефактом |

**Не путать:** слой 1 не проверяет компиляцию. Слой 2 не публикует. Слой 3 не
разрешает конфликты. Провал в одном слое **не чинится инструментом другого** —
это и была ошибка, из-за которой один потерянный `}` искали через `gh run list`.

---

## Слой 1 — ПОСЛЕДОВАТЕЛЬНОСТЬ (git)

Что это: **порядок коммитов и целостность структуры файла.** Кто-то потерял скобку
при слиянии — это сюда. Компилируется ли результат — **не сюда**.

Инструменты:
```
python3 scripts/pipelines/release_hermesplus.py sync     # дрейф + план merge
python3 scripts/upstream-rehearse.py                     # разведка конфликтов, 0 CI-минут
python3 scripts/pipeline-precheck.py                     # 8 гейтов, включая структуру
```

Признак готовности: **`pipeline-precheck` не блокирует.**

### Как разрешать конфликт — и где теряется скобка

Правило: **решение принимается по замеру, а не по стороне.** Наш блок с измеренной
причиной в комментарии — оставить; их блок с недостающей у нас структурой — взять;
независимые добавления — объединить.

**ЛОВУШКА (стоила 5 прогонов CI).** При объединении двух сторон
(`ours + их`) теряется закрывающая скобка, если она стояла **в конце стороны**:

```swift
НАШЕ:   serverID: Int? = nil          ← запятая была ПОСЛЕ этого места
ИХ:     turnDuration: Double? = nil
→       склеилось без запятой → "expected ',' separator"

НАШЕ:   Group { ... }   закрывалась ниже
ИХ:     плоский список без Group
→       Group без закрытия → 20+ ошибок "attribute 'private' ... non-local scope"
```

**Один потерянный `}` Swift показывает как лавину в несвязанных местах.** Именно
поэтому 20 ошибок в `ChatView` оказались одной скобкой, а не двадцатью дефектами.

**Чем проверять структуру (и чем НЕ надо):**

```
✅ scripts/check-swift-structural-balance.py   сканер, калиброванный на обоих родителях
❌ grep -c '}' / построчный счёт скобок        дал ложный вердикт ТРИ раза
❌ проверка «balanced at EOF» без родителей    не отличает мой дефект от унаследованного
```

Построчный счёт не работает потому, что `{` встречается в строковых литералах,
многострочных строках и комментариях, а `(` в сигнатуре функции открывает область
без скобки. Только сканер, знающий про строки/комментарии, **и сверка с каждым
родителем отдельно**, отличают «я сломал» от «оно всегда так выглядело».

---

## Слой 2 — СБОРКА (Swift, только CI)

Что это: **компилируется ли результат.** Ошибки типов, имён полей, сигнатур.

Локальной компиляции **нет** (Linux без Swift-тулчейна). Это не лечится вниманием:
`SessionSummary.sessionId` vs `CachedSession.sessionID` прошёл все локальные гейты
и уронил сборку.

**Как читать логи — через pipeline, а не `gh` руками:**

```bash
python3 scripts/pipelines/release_hermesplus.py release ...   # ждёт и верифицирует
```

Внутри — `wait_build()`, и три вещи там не случайны:

```python
OUR_REPO = "braintimebox/hermex-plus"
# gh resolves the default repo from the git remote; our remote points at
# upstream sometimes, and `gh run ...` then 404s. Always be explicit.

# `--limit=1` raced: a concurrent push could be picked up instead of ours,
# and the IPA downloaded afterwards would belong to a different commit.
rid = gh run list ... --jq '[.[] | select(.headSha | startswith("<head>"))][0].databaseId'
```

**Почему `--limit=1` — ошибка:** ты читаешь **чужой** ран и делаешь вывод о своём
коммите. Фильтр по `headSha` — единственная защита.

**ЛОВУШКА слоя 2.** Компилятор сообщает о **первом** провале, а не обо всех. Если
структура разъехалась, он печатает каскад — и каскад надо читать как **один**
дефект, а не как список. Ищи в выводе `expected '}'` / `expected ','` — это
структурные; `cannot convert` / `has no member` — это слои типов и имён.

---

## Слой 3 — PIPELINE (публикация)

Что это: **довести до артефакта.** Версия, тег, Release, IPA.

```bash
python3 scripts/pipelines/release_hermesplus.py status     # где мы
python3 scripts/pipelines/release_hermesplus.py check      # гейты без релиза
python3 scripts/pipelines/release_hermesplus.py release --next 3.7.0 --note "…"
```

`release` проходит: bump → changelog → закрытие пунктов → snapshot → гейт → push
→ **wait_build** → download IPA → ссылки.

**Признак готовности — не `releases/latest`.** Это ссылка на «что опубликовано
последним», а не на «эта версия опубликована». `verify_release()` проверяет, что
версия **реально** в Releases с артефактом:

```
verified: v3.7.0 is published with an artifact          ← успех
NOT PUBLISHED: v3.7.0 has no Release with an artifact   ← провал, ссылка на ран
```

Три места, где версия должна совпасть — гейт 1 `pipeline-precheck`:
```
VERSION  ==  CHANGELOG (верхняя секция)  ==  все MARKETING_VERSION в pbxproj
```

---

## Порядок, когда что-то упало

```
CI упал
  │
  ├─ "expected '}'" / "expected ','" / каскад "private ... non-local scope"
  │     → СЛОЙ 1. Структура. check-swift-structural-balance.py против обоих родителей
  │
  ├─ "cannot convert" / "has no member" / "extra argument"
  │     → СЛОЙ 2. Типы и имена. Сверь сигнатуру с upstream: git show upstream/master:<file>
  │
  └─ сборка зелёная, но релиза нет
        → СЛОЙ 3. verify_release: версия не долетела в Releases
```

**Главное правило:** не чинить слой 2 инструментами слоя 1. Ручной `gh run list`
вместо `wait_build` — это попытка решить слой 3 глазами.

---

## Что смотреть перед началом

```bash
python3 scripts/project_snapshot.py    # HEAD, версия, дрейф, размеры (НЕ править руками)
```
`docs/project-snapshot.md` — единственный источник правды о состоянии.
`docs/agents/upstream-sync-plan.md` — план синка (прогнать `upstream-rehearse.py` первым).
