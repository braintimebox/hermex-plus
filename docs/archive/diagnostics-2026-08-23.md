# CURRENT.md — Hermex Plus state snapshot

## Status
- Branch: main
- Last commit: 3a9498c — "docs: direct IPA link for v2.0.6"
- Latest release: v2.0.6 (2026-08-19)
- In-progress: streaming smoothness (presentation layer + scroll follow + freeze)

## Релизы этого цикла (2026-08-19)
- **v2.0.3** — scroll-to-bottom кнопка: перенос вправо-снизу + крупнее (36pt).
- **v2.0.4** — плавный стриминг-скролл: убран рэйс 50 анимаций/сек (snap без
  анимации при стриме), убран 16ms sleep на горячем пути, тёмный overscroll gap.
- **v2.0.5** — Streaming Lab A/B: 3 режима (A fade без geometry / B fade+geometry /
  C geometry без fade). `MarkdownRenderer` получил опциональный
  `forceFadeDisabled` (nil в prod, поведение не меняется). DEBUG-only.
- **v2.0.6** — фикс "yank-to-bottom": follow-интент привязан к позиции, а не к
  touch state (`shouldFollowLatestMessage` сбрасывается при уходе из нижней зоны).

## Streaming Lab A/B (незакрыто)
Цель — изолировать, что даёт плавность: glyph fade, geometry transition или
комбинацию. Три режима в Settings → Streaming Lab:
- A = current Hermes (fade, без анимации высоты)
- B = fade + smooth geometry (ease-out 0.12s)
- C = no fade + smooth geometry
Ожидает решения Oleksandr, какой режим ощущается плавнее → какой минимальный
prod-фикс переносить (кандидат: `.animation` на росте высоты блока).

## 2. Раскрытая задача: FREEZE (основная, отдельный заход)
- **Симптом**: main-thread block 3–4s на ChatView, воспроизводится с v1.6.7 по v2.0.3.
- **Стек**: `AttributeGraph.flushTransactions` + `_ViewList_Group.edit`
  (SwiftUI пересобирает граф списка сообщений). Второй стек: `GraphHost.flushTransactions`.
- **Память в норме** (82–214MB), не утечка. Паттерн: ~30s ритм stutter.
- **Гипотеза root cause** (требует подтверждения):
  `renderID = "transcript:\(absoluteIndex)"` (ChatViewModel.swift ~5624) — позиционный,
  не messageId-stable. При структурном сдвиге списка (вставка/реконсиляция)
  ForEach редифает весь список.
  Ремарка: в стриминге append идёт в конец + hot-path O(1) сохраняет `slot.renderID`,
  так что нужна проверка, что именно в стриминге вызывает `_ViewList_Group.edit`.
- **Данные лога**: `~/.hermes/hermex-logs.jsonl`, freeze на appVersion 2.0.3
  (18:06:15 и 17:45:55 2026-08-19). Канал: HermexLogger → webhook → :8912.
- **План**: поймать freeze на актуальной сборке (v2.0.6+), подтвердить стек,
  затем отдельно решать renderID→messageId (затрагивает пагинацию/компрессию/anchor).

## Контекст (память)
- Hot-path уже оптимизирован: O(1) trailing-slot update, 3 скаляра вместо
  full snapshot (357MB драйвер устранён), SwiftData fetch off-main.
- Не чинить freeze «на скорую» в одном релизе с другими фиксами — риск регрессии
  пагинации/компрессии при смене renderID.

## Верификация (2026-08-21) — стек-трейсы из hermex-logs.jsonl

- **Black screen / freeze root cause ПОДТВЕРЖДЁН**: CoreText
  `CTLineCreateWithAttributedString` → `ResolvedStyledText.sizeThatFits/draw`
  на main thread, 1–2s. Это markdown re-layout строк сообщений (MarkdownRenderer).
  Паттерн «main thread stalled 1s» рекуррентно на каждом scene active; пик
  jank 1168ms (13 fps).
- `mach_msg2_trap → GSEventRunModal → UIApplicationMain` = idle-сэмпл watchdog,
  НЕ реальный блок (ложный сигнал, фильтровать).
- **Кнопка ↓ dead-click**: `latestTranscriptMessageID` = позиционный renderID
  последнего сообщения. После структурного сдвига (компрессия/пагинация) id
  отсутствует → `proxy.scrollTo` молча игнорируется. FIX: guard на присутствие
  renderID в displayedTranscriptMessages + fallback на always-mounted
  bottomAnchorID.

## Разделение skills/plugins «личные vs предустановленные» — БЛОКЕР (факт)

- `/api/skills` (hermes-webui routes.py `_skills_list_from_dir`) возвращает
  `{name, description, category, disabled}` — БЕЗ поля `path` и БЕЗ признака
  происхождения (external vs local).
- Сервер имеет `get_external_skills_dirs()`, но в ответ оно НЕ просачивается.
- Клиентский `SkillSummary.path` декодируется, но сервер его не шлёт → всегда nil.
- ВЫВОД: достоверное разделение не сделать ни на клиенте, ни по API. Требует
  изменения сервера (добавить `origin`/`path` в /api/skills response) ИЛИ
  клиентской эвристики по category (ненадёжно).

## Задача: «Could not connect to the server» + очередь отправки (2026-08-23)

### Диагноз (факт)
- Сервер достижим: TLS-прокси :1118 (cert LE `hermes00.duckdns.org`) живой.
  `https://…:1118/` → 302, `/api/health` → 401 (норма, нужен токен). Сеть НЕ причина.
- Ошибка «Could not connect to the server…» — `APIError.swift:169`
  (`.cannotConnectToHost` / `.networkConnectionLost`), показывается из
  `performChatSend` catch → `sendErrorMessage` + `rollbackOptimisticMessage`.
- Retry уже есть, но короткий: `startChatWithRetry` (ChatViewModel.swift:2308)
  = 3 попытки, задержки 1.5с/3с, только `isRetryableConnectionFailure`.
  `timedOut` и `networkConnectionLost` НЕ ретраятся (намеренно, idempotency).
- НЕТ механизма «сообщение в очередь». Сейчас: сеть упала → сообщение
  откатывается + красная ошибка.

### Требование (дословно)
«Пусть клиент сам подключается, а сообщение идёт в очередь».

### Решение (обновлено 2026-08-23 — ПЕРСИСТЕНТНАЯ очередь, НЕ in-memory)
1. При retryable-сбое отправки НЕ откатывать сообщение, а оставить его в
   транскрипте с бейджем «ожидает отправки» (не красная ошибка).
2. Отправку ставить в персистентную очередь на SwiftData — новый
   `@Model PendingSendMessage` (образец: `PendingScheduledMessage`). Очередь
   переживает рестарт приложения.
3. Фоновый драйвер очереди (`SendQueueDriver`) с экспоненциальным backoff
   пробивает отправку, когда связь вернулась; подхватывает невыполненное
   при старте приложения (рестарт-безопасность).
4. Красную `lastError`/alert на send-сбой убрать для retryable-случая;
   оставить только для НЕ-retryable (401/400/ванутая сессия и т.п.).

### Точки правки
- `ChatMessage.swift` — модель неизменяемая (все `let`); статус очереди НЕ
  впихивать в неё. Отдельный слой в ChatViewModel.
- `ChatViewModel.performChatSend` (:2351) — catch: вместо rollback →
  enqueue + бейдж.
- `ChatViewModel.startChatWithRetry` (:2308) — оставить как есть (короткий
  retry); долгий backoff вынести в драйвер очереди.
- `ChatView.sendDraftMessage` (:1714) — `if lastError { onAPIError }` —
  не показывать alert для retryable-ошибок.
- Новый модуль `PendingSendQueue` / драйвер с NWPathMonitor или period
  retry-тикер (решить: monitor vs тикер).

### Открытый вопрос
- Тикер vs NWPathMonitor: monitor точнее ловит сеть, но нужен ещё и таймер
  на случай, если сервер «ожил» без смены интерфейса. Кандидат — тикер с
  backoff (проще, детерминированно, без лишних разрешений).

## Задача: кнопка ↓ «увеличивается/прыгает», не доходит до низа, чёрный экран (2026-08-23)

### Симптомы (от Oleksandr)
- Кнопка ↓ при нажатии «увеличивается и прыгает», но НЕ идёт в самый низ.
- Иногда чёрный экран.
- Происходит в длинных чатах, агент при этом «даже ничего не пишет» (idle).

### Диагноз (доказанный, v2.4.2)
Три разных причины, один триггер — длинный чат:

1. **«Увеличивается/прыгает»** — это задуманный press-эффект `.chatTactile`
   (ChatTactileButtonStyle.swift:105, pressedScale 0.945–0.98 + spring). НЕ баг
   сам по себе; бросается в глаза, потому что скролл при этом не срабатывает.

2. **«Не доходит до низа»** — позиционный `renderID = "transcript:\(absoluteIndex)"`
   (ChatViewModel.swift:5667-5668). В длинном чате компрессия/пагинация сдвигает
   индексы → `scrollTo` целится в позицию, которую SwiftUI ещё не измерил
   (ленивый LazyVStack), поэтому «крутится, но не доходит».
   v2.4.2 частично решил: `scrollToBottom` → `bottomAnchorID` (маркер 1pt,
   ChatTranscriptView.swift:320-322) вместо последнего сообщения. Но остаётся
   случай, когда контент ещё достраивается в момент тапа.

3. **«Чёрный экран»** — анимированный `withAnimation { proxy.scrollTo }` на
   длинной ленивой ленте заставляет пересчитать markdown-дерево хвоста
   (scheduleFollowScroll, ChatView.swift:2305-2311; комментарий в коде прямо
   признаёт чёрный экран mid-tap). Для явного тапа (isUserInitiated) ветка
   уже переведена в snap, НО для idle auto-follow (activeStreamID==nil) ветка
   `withAnimation` ещё жива.

### Лог (доказательства)
- Jank до max 1130ms / 5fps, freeze 3s рекуррентно — main-thread stall.
- Ранее подтверждённый корень: `CTLineCreateWithAttributedString` /
  `ResolvedStyledText.sizeThatFits` (markdown re-layout) на main-потоке.
- Память НЕ причина: jank-спайки воспроизводятся при mem ~95MB (после NSCache-фикса 2.3.8).

### Направление фикса (гипотеза, требует confirm по стеку в длинном чате)
- Сделать renderID стабильным по messageId, а не по absoluteIndex (риск для
  пагинации/компрессии — отдельно тестировать).
- Убрать остаточную анимированную auto-follow на idle длинном чате (чёрный экран).
- Опционально: «доходит до низа» — после tap ждать завершения layout (ScrollView
  layout done) перед scrollTo, либо не анимировать никогда на длинном транскрипте.

### ROOT CAUSE (2026-08-23, доказано по коду) — кнопка ↓ / чёрный экран / «не доходит»
Причина НЕ в chat/версии — это произведение двух затрат на ДЛИННОМ хвосте сообщения:

1. **StreamingTextFadeRenderer.draw** (StreamingTextFadeRenderer.swift:16-53) —
   на КАЖДЫЙ кадр TimelineView делает ДВА полных вложенных прохода
   `line → run → slice` по всему Text.Layout: (а) собрать orderedKeys всех срезов,
   (б) для каждой срезы store.opacity + ctx.draw(slice). Это CoreText-backed
   per-glyph re-layout+opacity каждый кадр. Чем длиннее ПОСЛЕДНИЙ блок (длинный
   абзац без \n), тем дороже кадр → main-thread stall → чёрный экран.

2. **Копирование activeMarkdown** — StreamingMarkdownBlockSplitter.computeSplit
   заканчивается `activeMarkdown: String(text[chunkStart...])` (StreamingMarkdownSupport.swift:78).
   MarkdownRenderer.body (:193-201) вызывает split НА КАЖДЫЙ проход тела
   (20-50/с токенов + каждый fade-кадр), каждый раз копируя весь хвост.

3. **Почему «ничего не печатает, а тормозит»**: TimelineView(.animation,
   paused: !fadesActive) держит кадры активными; fadesActive гаснет только через
   framePauseDelay ≈ 1.05c после последнего АПДЕЙТА контента (task(id: content)).
   Длинный хвост до-рисовывает каскад по ~29 glyph → draw гоняет кадры по всему
   Layout, скролл (кнопка ↓) не успевает за layout → «прыгает, не доходит до низа».

### Направление фикса (приоритет по отдаче)
1. (высокий) В StreamingTextFadeRenderer.draw НЕ пере-регистрировать уже
   известные срезы каждый кадр: register() уже отсеивает дубли (stamps[key]!==nil),
   но orderedKeys всё равно строится + два прохода. Сделать инкрементальный
   skip: если store больше не меняется, второй проход рисует только активную
   fade-зону (head срезов уже opacity>=1 → пропуск).
2. (высокий) Ограничить fade-зону сверху: активный блок ограничен
   StreamingTextFadeWindow.maxBlocks=10, НО в пределах последнего блока нет
   лимита на длину. Для блока > N символов (напр. 2000) fade отключить
   (fadeEnabled=false) → рендер без per-frame FadeRenderer.
3. (средний) `activeMarkdown` копируется на каждый body → кэш по (content) уже
   есть у border-scan, НО String(text[chunkStart...]) копируется всегда при
   miss. В стриме text меняется каждый токен → miss каждый токен → O(N²) по
   длине. Держать activeMarkdown как Substring/инкремент вместо re-copy.
4. (отдельно) renderID позиционный → messageId (риск пагинации/компрессии).

### ФИКС применён (2026-08-23) — троттлинг re-render длинного стрима (АКТУАЛЬНЫЙ)
- Файл: `MarkdownRenderer.swift` (`StreamingMarkdownRenderer`).
- БЫЛО: `.task(id: content) { displayedContent = content }` — немедленный re-parse
  ВСЕГО markdown на каждый word-tick → O(n²) re-layout через CoreText на главном
  потоке → чёрный экран / stall при длинном ответе (VERIFIED 2026-08-21, стек
  CTLineCreateWithAttributedString). Комментарий в коде ошибочно утверждал, что
  per-token re-parse «не bottleneck».
- СТАЛО: `.onChange(of: content)` → `scheduleContentCommit` с 16ms debounce
  (coalescing на «не чаще кадра»), всегда коммитит последний текст. Убирает
  quadratic re-render, сохраняет continuous reveal (fade уже каденсируется word-drain).
- Первый кадр НЕ ломается: `_displayedContent = State(initialValue: content)`.

### НЕРЕШЁННОЕ (2026-08-23) — фриз на длинном ГОТОВОМ сообщении (скриншот «Размышления»)
- Oleksandr: «на этом моменте тоже подвисает приложение» + скриншот = ЧАТ с
  готовым длинным сообщением (предыдущий ответ агента, куча инлайн-кода).
  Это НЕ reasoning-меню, НЕ стриминг — сообщение уже отрисовано.
- Мой фикс 2.4.3 покрывает ТОЛЬКО стриминг (StreamingMarkdownRenderer).
  ГОТОВОЕ сообщение идёт через `ChatMarkdownView` → `Markdown(content)` —
  полный layout одним махом при монтировании, БЕЗ моего debounce.
- ФАКТ ПО ЛОГУ: в hermex-logs.jsonl **0 событий с appVersion=2.4.3**.
  Последние freeze/stutter — 2.4.2 (старая сборка). То есть 2.4.3 ещё НЕ
  стоит на устройстве → диагностировать фриз на 2.4.3 невозможно.
- Среди 2.4.2-событий НЕТ ни одного WORK-кадра CoreText/MarkdownUI — только
  idle (mach_msg2_trap) и аллокации (swift_allocObject, mem 232/133). Источник
  для подготовленного сообщения может быть НЕ рендер текста, а alloc/скролл.
- РЕШЕНИЕ (осознанный стоп): НЕ чинить вслепую четвёртый раз. Нужен WORK-стек
  с версии 2.4.3 после воспроизведённого фриза (канал телеметрии работает).

### ОТКАЧЕНО (не лечило причину — паллиатив)
- `StreamingTextFade.swift` cap `maxFadeableBlockCharacterCount = 4000` —
  откачен (`git checkout`). Маскировал симптом на длинных блоках, но НЕ убирал
  O(n²) re-parse. Причина лечения — троттлинг выше, а не cap на fade.
- Ошибки по пути (дисциплина): сперва поставил cap → откатил; затем кривой
  троттлинг с `.task(id:)` + `do{}` (не троттлил, а спавнил task) → заменил
  на корректный `.onChange` + debounce. Итог — ТОЛЬКО MarkdownRenderer.
- ⚠️ Риск: hot-path стриминга → обязателен `xcodebuild` CI green; отдельно
  проверять fade-регрессию (первый кадр ок по State(initialValue)).

## Три бага (Oleksandr, 2026-08-23) — диагностика по коду

### БАГ 1: Отложенное сообщение — смена чата не работает («не сохраняет выбор, пишет в новый чат или вообще не пишет»)
- `ScheduleMessageSheet` (ChatView.swift:2917): `attachToChat` init = `chatTitle != nil` = TRUE при открытии из чата.
- Секция выбора чата (строки 2968-2998) видна ТОЛЬКО `if !attachToChat`. Пока тумблер «Attach» включён — выбора НЕТ.
- `target` (строки 3071-3083): `if attachToChat { return .currentChat }` — **игнорирует выбор** пока тумблер включён.
- РЕАЛЬНЫЙ БАГ: юзер выбирает existing-чат в пикере, но тумблер «Attach» остаётся включён → `target` = `.currentChat` → пишет в текущий/новый чат. Либо секция выбора скрыта за тумблером.
- Доп. риск: `SessionSummary.id` (Session.swift:145-152) возвращает СИНТЕТИКУ `session-title-timestamp`, когда `sessionId` пуст. `SessionListItem(id: sessionId ?? id)`. Если у реальной сессии нет sessionId → синтетика → `startChat` не находит сессию → ошибка/новая.

### БАГ 2: Pin для длинных сообщений не работает (+ нет Save)
- `ChatMessageActions` (ChatMessageActions.swift): и Save (стр. 93-97) и Pin (стр. 99-105) есть в контекст-меню. Save НЕ отсутствует — он есть.
- `.contextMenu` приложен к `bubble` (ChatTranscriptView.swift:710-711), `actionContext` создаётся БЕЗ фильтра по длине (ChatViewModel.swift:1712) → меню доступно для всех.
- ГИПОТЕЗА: для длинных сообщений с code-блоком горизонтальный `ScrollView` внутри `MarkdownRenderer` ПЕРЕХВАТЫВАЕТ long-press → contextMenu/меню не вызывается. Значит Pin/Save недоступны. Это то самое «меню не появляется на длинном», о чём думал ранее.
- Уточнить: показывается ли контекст-меню на длинном сообщении вообще, или не показывается?

### БАГ 3: Аватарка не восстанавливается после переустановки
- ПРИЧИНА ИЗВЕСТНА (из памяти, v2.0.12): аватар в Keychain (`ServerAccount.avatarImageData`), UI читает через `@AppStorage`-зеркало (`sessionIdentity.avatarImageData`).
- re-isntall: Keychain выживает, UserDefaults (зеркало) стирается. Гиф-фикс был — ресинк зеркала на каждом `activate` (НЕ только при смене активного). НО при полной переустановке через SideStore re-sign Keychain может тоже теряться.
- ПОЛНЫЙ фикс: серверная синхронизация аватара (хранить на бэкенде, загружать при старте) — отдельная серверная задача.

## План
1. Баг 1: авто-выключать `attachToChat` при выборе existing в пикере + исправить синтетику `sessionId` (использовать `sessionId ?? id` правильно у `SessionSummary`).
2. Баг 2: проверить перехват long-press горизонтальным ScrollView в длинных сообщениях; добавить `.contentShape`/жест на весь пузырь если нужно.
3. Баг 3: серверная синхронизация аватара (отдельная задача).

## ФИКС 2.4.4 (2026-08-23) — баги 1 и 2
- Баг 1 (смена чата отложенного): авто-выключаю `attachToChat` при выборе
  existing-чата (ChatView.swift, .sheet showSessionPicker closure).
  Раньше тумблер оставался on → `target` = .currentChat → игнорировал выбор.
- Баг 2 (pin двойного назначения): onPin = pin+save (создаёт SavedMessage),
  onUnpin = unpin+unsave (удаляет SavedMessage). Сохранение — точечное по
  messageId (savedKey = serverURL|saved|messageId). Guard от дубля в saveMessage
  (UNIQUE savedKey в SwiftData молча дропает второй insert).
- Баг 3 (аватар после переустановки): НЕ фиксил в 2.4.4 — серверная задача
  (синхронизация аватара на бэкенде). Отложено, требует согласования.

## ПОЛНЫЙ СПИСОК БАГОВ (актуализирован 2026-08-23, не терять)
1. Отложенное → смена чата — ✅ 2.4.4
2. Pin длинных + Save — ✅ 2.4.4 (pin=pin+save)
3. Аватарка после переустановки — ⏸️ отложено (серверная задача)
4. ПОСЛЕДНЕЕ СООБЩЕНИЕ НЕ ЧИТАЕТСЯ — ❌ НЕ начато.
   Причина: latestTranscriptMessageID = transcriptMessages.last?.id = renderID =
   "transcript:<absoluteIndex>" (ПОЗИЦИОННЫЙ). После компрессии/пагинации последнего
   renderID нет в displayedTranscriptMessages → scrollTo игнорируется → последнее
   сообщение остаётся за кадром.
5. СКРОЛЛ ВНИЗ → фриз/чёрный — ❌ НЕ начато.
   Причина: .id(renderID) позиционный в ForEach → AttributeGraph full-diff
   (AGGraphGetValue/SetOutputValue, 31 событие за 2 дня, свежие после 2.4.3).
6. «ВЕРХ-ВНИЗ» при думании агента — ❌ НЕ начато.
   Причина: конфликт .sizeChanges defaultScrollAnchor=.bottom (ChatScrollPolicy:38)
   ↔ прикладной follow (proxy.scrollTo bottomAnchorID). Оба гонят к низу → автоколебание.
   Усиливается 2.4.3-троттлингом (текст раз в кадр → .sizeChanges на каждый layout).

## ЕДИНЫЙ КОРЕНЬ 4+5+6 — ПОЗИЦИОННЫЙ renderID
- ВСЕ ТРИ бага = позиционный renderID ("transcript:<index>") вместо messageId.
- Правильный подход (рефакторинг): стабилизировать .id() по messageId, renderID
  оставить как внутренний scroll-механизм. 2 файла, 18 вхождений (изолировано).
- ⚠️ ПРАВИЛО (CURRENT.md old): renderID→messageId НЕ смешивать с другими фиксами
  в одном релизе — риск регрессии пагинации/компрессии/anchor. Отдельный заход.

## БАГ 6 (верх-вниз при думании агента) — диагноз по коду, ПОДТВЕРЖДЁН
- Симптом: пока агент думает, чат плавно водит вверх-вниз ~полстраницы, зациклено.
- 3 источника скролл-следования при стриминге, срабатывают одновременно:
  1. `.sizeChanges` defaultScrollAnchor = .bottom (ChatScrollPolicy:38) — СИСТЕМНЫЙ,
     срабатывает на каждый layout-проход, анимируется системой.
  2. `onChange(messages.count)` → onScrollToLatestContent (ChatTranscriptView:193-200).
  3. `onChange(streamingScrollTrigger)` → onScrollToLatestContent (ChatTranscriptView:202-205),
     тикает через 16мс (streamingScrollCoalescingDelayNanoseconds) — РЕТАРГЕТ.
- При стриминге 2 и 3 snap (анимация подавлена), НО `.sizeChanges` (1) анимируется
  системно на каждый layout. Троттлинг 2.4.3 (текст раз в кадр) → каждый layout
  дёргает `.sizeChanges` → автоколебание «верх-вниз».
- ПРИЧИНА — тройное следование, главный «плавный» компонент = `.sizeChanges`.
- ФИКС-КАНДИДАТЫ:
  (а) убрать `.sizeChanges` при стриминге (оставить прикладной snap-follow) —
      рискованно (памятка: .sizeChanges резервировать для стриминга);
  (б) убрать дублирующий `onChange(streamingScrollTrigger)` — но он нужен для
      роста текста внутри одного сообщения (count не меняется);
  (в) объединить 2+3 в один вызов — но оба snap, не источник анимации.
- НАИБОЛЕЕ ВЕРОЯТНЫЙ источник «плавности» = `.sizeChanges` (1). Правильный фикс:
  не давать `.sizeChanges` конкурировать с прикладным follow — оставить его только
  когда прикладной follow не активен. Требует аккуратного разграничения.

## БАГ 3 аватарка после переустановки — ТОЧНЫЙ диагноз
- `ServerAccount.avatarImageData` хранится в Keychain-блобе (декодируется, стр. 95).
- UI аватар читает из `@AppStorage(sessionIdentity.avatarImageData)` (SessionListView:75,719),
  которое стирается при переустановке.
- Код (ServerAccount:200-204) утверждает «Keychain survives, UserDefaults wiped»,
  и `activate` (стр.195-220) для существующего existing ресинкает зеркало из Keychain.
- НО: если после переустановки Keychain-сервер засеивается заново (makeSeededAccount,
  стр.341: avatarImageData = identityDefaults.data(...) — ИЗ ПУСТЫХ defaults после ре-isntall),
  то аватар теряется в засеве. Это зависит от того, переживает ли Keychain ре-sign:
  - Если сервер восстанавливается без ввода URL → Keychain жив → activate находит existing
    → ресинк → аватар ДОЛЖЕН восстановиться. Значит либо ресинк не отрабатывает, либо
    Keychain-аватар пуст из-за засева.
- НАДЁЖНОЕ решение (не зависит от капризов Keychain/SideStore): СЕРВЕРНАЯ синхронизация
  аватара — хранить на бэкенде, загружать при старте. Требует эндпоинта в hermes-webui.

## ФИКС баги 4+5 (2026-08-23) — стабилизация TranscriptMessage.id по anchorID
- `TranscriptMessage.id` = `anchorID` (был `renderID` = позиционный).
- ForEach `.id(transcriptMessage.anchorID)` (ChatTranscriptView) — вместо renderID.
- `proxy.scrollTo(anchorID)` в pinned + loadOlder — согласованы с `.id(anchorID)`.
- РЕЗУЛЬТАТ: при компрессии/пагинации/reconcile строки с messageId сохраняют id →
  SwiftUI НЕ переcобирает весь список (AttributeGraph-фриз уходит). renderID остаётся
  только как compression-reference anchor (позиционный, не identity).
- Лечит: баг 4 (последнее не читается — scroll к последнему по стабильному id),
  баг 5 (фриз при скролле вниз — меньше AttributeGraph).
- ⚠️ Риск: сообщения без messageId → anchorID = raw:index (позиционный, как раньше).
  Полная стабилизация только для сообщений с messageId. Требует CI + проверки
  пагинации/компрессии (правило: отдельный заход).

## ФИКС 2.4.6 (2026-08-23) — под-баги отложенных сообщений (баг 1 доп.)
1. EditScheduledMessageSheet не восстанавливал целевой чат: destinationIsExistingChat
   ставился из message.sessionId в onAppear, но pickedSession оставался nil →
   save() попадал в `guard let picked` → всплывал пикер вместо сохранения
   («можно сломать привязанку, нельзя прикрепить заново»). Фикс: после loadSessions
   сопоставить message.sessionId с pickedSession.
2. Scheduled список не обновлялся после delete: deleteLocal удалял модель, но
   удаление из видимого списка messages ждало сетевой deleteScheduledFromServer
   (медленный/зависал → строка оставалась). Фикс: messages.removeAll сразу в deleteLocal.

## БАГ 3 (аватар) — требует серверного эндпоинта (hermes-webui), НЕ клиент.
- Причина: аватар device-local (Keychain+UserDefaults), оба стираются при
  переустановке через SideStore. Надёжное решение — синхронизация на бэкенде.
- Отдельный заход на hermes-webui (НЕ вмешивать в клиентский релиз).

## РЕГРЕССИЯ 2.4.5 (вероятно) — «не пускает вниз чата» (Oleksandr, 2026-08-23)
- Симптом: заходя в чат, нельзя попасть вниз — ни кнопкой ↓, ни листая.
  Появился после 2.4.5 (последний коммит, менявший identity/скролл).
- 2.4.5: `TranscriptMessage.id` = anchorID (был renderID). `.id(anchorID)` в ForEach.
- anchorID = messageId (если есть) ИЛИ "raw:loadedIndex". RISK: если два сообщения
  имеют одинаковый messageId (реально при reconnect/дубле стрима), ForEach с
  дублирующимся id → SwiftUI не может различить строки → скролл вниз ломается.
  Также loadedIndex идёт по полному messages (tool-сообщения фильтруются), поэтому
  для сообщений без messageId anchorID="raw:loadedIndex" использует индекс с
  "дырами" → риск некорректного id.
- СВЯЗЬ: баг «закрываю → ответ не вижу» + «Session Action Failed» — вероятно, тот же
  reconnect, создающий дубль messageId → ломает identity → скролл и список.
- РЕШЕНИЕ-КАНДИДАТ: identity ForEach НЕ должна зависеть от messageId (неуникален при
  reconnect). Использовать renderID (уникальный позиционный) для `.id()`, а anchorID
  оставить только для scroll-таргетов. Разделение identity(renderID) и
  target(anchorID). Требует теста: reconnect/stриминг без дублей.
- ⚠️ Это РЕГРЕСС-ГРЕЙД — вероятно, надо срочно чинить в след. версии (2.4.7).

## ФИКС 2.4.7 (2026-08-23) — регрессия «не пускает вниз» (внесена 2.4.5)
- 2.4.5 ставила identity = anchorID. anchorID НЕ уникален при дубле messageId
  (реально при stream reconnect / дубле сообщения) → ForEach не может различить
  строки → «не пускает вниз чата» (ни кнопкой, ни листая).
- ФИКС: TranscriptMessage.id = `messageId ?? renderID`:
  - messageId-first → стабильно (не пере-diff список, фикс бага 4 сохранён);
  - renderID-fallback → уникально всегда (нет дубля, регрессия убрана).
- `.id(transcriptMessage.id)` в ForEach + scrollTo(row.id) в pinned +
  scrollTo(identity) в loadOlder — ВСЕ согласованы на этот id.
- НЕ затоптал 2.4.6 (edit-scheduled цел). Рабочий diff = 2 файла identity.

## ИТОГ по «все три бага» (актуально)
- Баг 1 (отложенное→смена чата) — ✅ 2.4.4
- Баг 2 (Pin длинных = pin+save) — ✅ 2.4.4
- Баг 4+5 (последнее не читается + фриз скролла) — ✅ 2.4.5 identity
  BUT 2.4.5 внесла регрессию «не пускает вниз» → 2.4.7 чинит (messageId??renderID).
- Баг 3 (аватарка) — ⏸️ требует серверного эндпоинта (hermes-webui), отложен.
- Баг 6 (верх-вниз при думании) — диагноз есть, фикс не применён (нужен тест).
- Баг «Session Action Failed / закрываю→ответ не вижу» — СВЯЗАН с регрессией
  identity (reconnect дубль) → 2.4.7 тоже должен помочь. Отдельная проверка.

## БАГ 3 (аватарка после переустановки) — точный механизм, ТРЕБУЕТ СЕРВЕР
- avatarImageData хранится в Keychain-блобе ServerAccount (.servers).
- При переустановке через SideStore Keychain-блоб СТИРАЕТСЯ → аватар физически
  потерян в клиенте. makeSeededAccount читает только identityDefaults (тоже стёрты).
- Клиентский фикс НЕВОЗМОЖЕН (нет источника данных).
- Правильный фикс = СЕРВЕРНАЯ СИНХРОНИЗАЦИЯ: эндпоинт avatar в hermes-webui +
  загрузка при старте + сохранение при изменении. — ОТЛОЖЕНО в отдельный заход.
- НЕ сделать поверхностно (риск потери данных / неполный фикс).

## БАГ 6 (верх-вниз при думании) — точный механизм, ТРЕБУЕТ отдельный заход
- Причина: ChatTranscriptView:143 передаёт isStreaming = (activeStreamID != nil)
  в sizeChangeAnchor. При думании агента стрим подключён → isStreaming=true →
  .sizeChanges-анchor=.bottom активен, но текст НЕ растёт. Прикладной follow тоже
  активен → ДВА механизма на нерастущем контенте → плавное автоколебание.
- Правильный фикс: нужен сигнал "контент реально печатается" (не просто стрим
  подключён), чтобы .sizeChanges-анchor включался только при росте текста.
- Добавить такой сигнал (напр. непустой контент стримящегося сообщения) в hot-path
  стриминга — рискованно БЕЗ проверки на устройстве. — ОТЛОЖЕНО.
- НЕ править вслепую (это hot-path стриминга, регресс сломает скролл).

## ЗАВИСАНИЕ 2.5.2 — freeze 4s ChatView mem=96 стек libswiftCore
- Событие: freeze 4s, ChatView, mem=96 (не память), стек libswiftCore.dylib <redacted> +0x4c.
- lastEvents: chat opened ×2 + stutter — при открытии чата с активным стримингом.
- КОРЕНЬ: StreamingMarkdownSupport.swift:78 activeMarkdown = String(text[chunkStart...])
  — КОПИРУЕТ весь текст от chunkStart до конца при КАЖДОМ расчёте. Для длинного
  стримящегося ответа без \n (chunkStart не двигается) → O(N) String-копия на кадр
  → долгая операция в libswiftCore → freeze в открытии/стриминге.
- Это НЕ 2.4.8-баг (AttributeGraph) и НЕ 2.5.2-баг (.sizeChanges) — отдельный корень.
- ФИКС (следующий заход): кэшировать activeMarkdown / не копировать весь хвост,
  а инкрементально аппендить (Substring / StringBuilder). Проверка на длинном ответе.

## ЗАВИСАНИЯ — ТОЧНЫЙ КОРЕНЬ (2.5.2 freeze swif_bridgeObjectRetain TranscriptMessage)
- Факт: freeze 4s mem=221 ChatView, стек libswiftCore swift_bridgeObjectRetain +0x8
  <- HermesMobile TranscriptMessage copy <- SwiftUICore. Это COW-копия [TranscriptMessage].
- Hot-path стриминга УЖЕ O(1) (2.0.0 4d53e03, инкрементальный аппенд, не полная пересборка).
- НО: recomputeDisplayedTranscriptMessages() строка 305 делает
  displayedTranscriptMessages[lastIndex] = TranscriptMessage(...) — IN-PLACE МУТАЦИЯ.
  Если массив COW-разделяем (передан в ChatTranscriptView), мутация → ДЕПКОПИЯ всего
  массива [TranscriptMessage] → retain каждый элемент → freeze на каждом токене.
- Это и есть root: in-place мутация разделяемого (COW) массива. 
- ФИКС (след. заход): перед мутацией гарантировать уникальность (isKnownUniquelyReferenced
  или пересоздать с изменённым tail без COW-копии), чтобы не депкопировать каждый токен.
