# Share Sheet — контракт совместимости форка

**Дата**: 2026-10-31
**Статус**: действующий контракт. Заменяет черновик исследования от 2026-08-10,
который описывал план (1500 символов, `hermes-agent://`, async-ретраи пейстборда),
а не фактическую реализацию.

Документ фиксирует, **почему** URL-транспорт в этом форке обязателен, **как**
он устроен сейчас и **что проверять** при каждом обновлении upstream.

---

## A. Историческая регрессия

### 3.6.0 — работало

Текст шаринга ехал внутри URL, который система передаёт содержащему приложению:

```
hermesplus://share?d=<base64url>
```

Extension: `saveToPasteboard(...)` + `openHermes(withDraft:)`.
Приложение: `handleOpenURL` → декодирование `d` → черновик в композере.

Этот путь **не требует App Group** — payload является частью URL.

### upstream-v1.6.0 — регрессия

Тег `upstream-v1.6.0` (`2eeb25651e91635ecd01850aaa50bc70af643876`,
2026-09-05). После синка Share Sheet стал полагаться только на App Group:

- `ShareViewController.saveDraftAndOpenHermes` вызывает
  `HermesShareDraft.savePendingImport(draft:attachments:in:)` через
  `containerURL(forSecurityApplicationGroupIdentifier:)`;
- открывается **пустой** `HermesShareDraft.openURL` — без параметра `d`;
- параметр `d` и кодеки (`openURL(withDraft:)` / `draftFromURL`) исчезли.

### Почему это ломает нашу схему сборки

Ветка собирает IPA с `CODE_SIGNING_ALLOWED=NO`, затем SideStore переподписывает
бесплатным Apple ID. Переподписанная extension не сохраняет App Group
entitlement (известное ограничение SideStore, см. также комментарии в
`HermesMobile/Features/Share/SharedDraftStore.swift`). Тогда:

- `containerURL(...)` возвращает путь **в своей песочнице** у каждого процесса;
- extension пишет в один контейнер, приложение читает другой;
- inbox пуст → шаринг исчезает без ошибки.

Named pasteboard не спасает: Apple scopes named boards подписывающей
идентичностью (`UIPasteboard.init(name:create:)` — «within an app or between
apps that have the same team ID»), то есть гарантии для переподписанной сборки
нет.

### Восстановление

Коммит `d3c2ecbb4c1bd3e91b70f232941ed82e11ddb15d`
(«fix(share): text shares ride in the open URL again (the 3.6.0 transport)»,
2026-10-25, входит в `release/3.9.68`) вернул URL-транспорт:

- `HermesMobile/Features/Share/SharedDraftStore.swift`:
  `maximumURLDraftBytes`, `openURL(withDraft:)`, `draftFromURL(_:)`,
  `reservationFromURL(_:)`, `ShareDeliverySource.url`;
- `HermesMobile/ContentView.swift`: `reservationFromURL` разбирается **до**
  обращения к контейнеру;
- `HermesShareExtension/ShareViewController.swift`: `fitsInline` →
  `openHermes(withDraft:)`.

**URL-транспорт для короткого текста — намеренно сохранённый механизм
совместимости форка, а не временный обход.** Его нельзя удалять при синке,
даже если upstream перешёл на App Group.

---

## B. Текущий контракт (сверено с кодом)

| Сценарий | Транспорт | Код |
|---|---|---|
| Текст ≤ 6000 байт, без вложений | URL `hermesplus://share?d=<base64url>` | `SharedDraftStore.swift:485` (`maximumURLDraftBytes`), `:488` (`openURL(withDraft:)`), `ShareViewController.swift:65-72` |
| Текст > 6000 байт или с вложениями | App Group inbox (`savePendingImport`) | `ShareViewController.swift:83-94` |
| Резерв для того же случая | named pasteboard (`saveToPasteboard`) | `SharedDraftStore.swift:174` (`sharePasteboardName`), `:182`; `ShareViewController.swift:96` |
| Последний резерв, только текст | `UIPasteboard.general` | `SharedDraftStore.swift:336` (`saveTextToGeneralPasteboard`), `ShareViewController.swift:101-104` |
| Приём URL в приложении | `handleOpenURL` → `reservationFromURL` → `draftFromURL` | `ContentView.swift:121-135`, `SharedDraftStore.swift:510,534` |

### Инварианты

1. **Порог 6000 — в байтах UTF-8, не в символах**:
   `draft.utf8.count <= maximumURLDraftBytes` (`SharedDraftStore.swift:493`).
   Это технический предел текущей реализации, **не** ограничение iOS.
2. **Payload — URL-safe base64**: `+`→`-`, `/`→`_`, padding `=` срезается и
   восстанавливается при декодировании (`:494-499`, `:519-525`).
3. **Схема и host совпадают у отправителя и получателя**: оба target'а берут
   `HERMES_URL_SCHEME` из своего Info.plist, значение задаётся один раз —
   `APP_URL_SCHEME_NAME = hermesplus` (`Config/Shared.xcconfig:35`), host —
   `share` (`SharedDraftStore.swift:141`).
4. **Вложения никогда не выдаются за доставленные текстом**:
   `ShareDeliveryOutcome.textOnlyGeneralPasteboard.carriedFullPayload == false`,
   сообщение прямо говорит, что файлы не приложены.
5. **Нет подтверждения — нет сообщения об успехе**:
   `ShareOpenOutcome.confirmed` требует результата `extensionContext.open`;
   fallback-пути возвращают только `.dispatchedOnly`; `.unavailable` не
   открывает приложение и не рапортует успех (`ShareViewController.swift:117-120`,
   `:172-188`).
6. **App Group конфигурация согласована**: `APP_GROUP_IDENTIFIER` один на оба
   target'а (`Config/Shared.xcconfig:25`), entitlements
   `HermesMobile/Resources/HermesMobile.entitlements` и
   `HermesShareExtension/Resources/HermesShareExtension.entitlements` ссылаются
   на одну переменную.

---

## C. Правила при обновлении upstream

Обязательный чеклист для агента (дублируется кратко в навыке `hermex-plus`):

1. Найти изменения upstream, затрагивающие Share Sheet:
   `git log --oneline <base>..upstream-<new> -- HermesShareExtension/ HermesMobile/Features/Share/ HermesMobile/ContentView.swift`.
2. Сравнить `ShareViewController.swift` и `SharedDraftStore.swift` до и после.
3. Проверить, что `hermesplus://share` и параметр `d` живы, а формат base64url
   не изменился.
4. Проверить приём и декодирование URL в основном приложении (`handleOpenURL` →
   `reservationFromURL`).
5. Проверить `APP_GROUP_IDENTIFIER` и оба `.entitlements`.
6. Проверить длинный текст и вложения (контейнер + pasteboard).
7. Прогнать `SharedDraftStoreTests` на macOS/Xcode, если он доступен.
8. **Не удалять URL-транспорт только потому, что upstream перешёл на App Group.**
9. Если upstream меняет механизм доставки — сначала доказать, что новый механизм
   работает в **нашей** схеме сборки и переподписи (unsigned IPA + SideStore).
10. Не считать статический анализ эквивалентом сборки или device-теста.

---

## D. Регрессионные тесты

`HermesMobileTests/SharedDraftStoreTests.swift`, секции
«3.9.68 regression: …». Покрыто:

| Сценарий | Тест |
|---|---|
| короткий текст едет в URL | `testURLDraftAtLimitIsCarriedInline` |
| пустой текст | `testEmptyDraftIsNotInlined` |
| Unicode / многобайтовый UTF-8 | `testURLDraftLimitMeasuresBytesNotCharacters` |
| граница 6000 байт | `testURLDraftAtLimitIsCarriedInline` (ровно 6000) |
| больше 6000 байт | `testURLDraftOverLimitIsNotInlined` |
| URL-safe формат payload | `testURLDraftPayloadIsURLSafeBase64` |
| приоритет транспортов | `testDeliveryOutcomePrefersContainerThenPasteboardThenGeneral` |
| вложения не выдаются за доставленные | `testOnlyFullPayloadOutcomesCountAsCarried`, `testTextOnlyFallbackWarnsAboutAttachments` |
| недоступность App Group / пустой результат | `testUnavailableDeliveryNeverReportsSuccess` |
| неудачное открытие приложения | `testUnconfirmedOpenIsNotReportedAsSuccess` |
| повторная доставка после ошибки | `testStrandedReservedItemIsRecoveredToPending`, `testReleasedReservationCanBeReservedAgain` |

Сценарии, которым нужен device, тестами **не** покрыты: реальное открытие
приложения из Share Sheet, поведение named/general pasteboard после переподписи,
работа App Group в установленной сборке.

---

## E. Уровни доказательства

Держать три уровня раздельно и не повышать без проверки:

| Уровень | Что значит | Текущее состояние |
|---|---|---|
| **Static** | код и конфигурация согласованы (чтение, диффы, гейты) | подтверждено для контракта §B |
| **Build/Test** | проект скомпилирован, тесты выполнены | **не подтверждено** — в Linux-окружении нет Xcode |
| **Device** | установленная сборка проверена в реальном Share Sheet | **не подтверждено** |

Правило: заявление «исправлено» требует уровня Build/Test минимум; «работает у
пользователя» — уровня Device.
