## 4.4.0 — прямое подключение к Hermes, единый вход

- **Основной клиент переведён на прямой вход Hermes.** Вместо legacy-эндпоинтов
  (`/api/auth/login`, `/api/auth/status`, `/api/auth/logout`, `/health` — их на сервере
  больше нет) приложение логинится через `POST /auth/password-login` с
  `username + пароль дашборда` и получает единую cookie-сессию, которая покрывает
  чат, профили и Kanban.
- **Discovery вместо слепого логина.** Приложение читает `GET /api/auth/providers`
  (публичный) и определяет, есть ли на сервере парольный вход; поля username/password
  показываются только когда сервер их реально требует.
- **Один набор кредов для всего.** Если для сервера уже настроены Bots/Groups
  (их `BotConnection` хранит username+пароль дашборда в Keychain), основной вход
  переиспользует эти же креды автоматически — повторный ввод не нужен.
- **Поле Username** добавлено в онбординг и в Add-server.
- **Logout** переведён на `/auth/logout`, health-проверка — на `/api/health`.

## 4.3.13 — Workspace Launcher: сетка 4 × 3 над списком чатов

- **Лаунчер 4 × 3 на экране чатов.** Двенадцать фиксированных ячеек в порядке
  чтения: занятая плитка открывает объект, пустая — это «Add», а не дырка. Сетка
  не перестраивается при добавлении, поэтому положение плиток предсказуемо.
- **Три типа объектов на одной панели:** бот (`BotProfile`), группа
  (`BotGroupRoom`) и чат (Hermes Session). Плитка показывает значок типа и
  подпись, так что тип читается без открытия.
- **Плитка — ярлык, а не объект.** Добавление не создаёт ни сессию, ни профиль
  бота, ни комнату; удаление плитки не удаляет то, на что она указывала. Один и
  тот же объект нельзя добавить дважды — в списке он помечен «Added».
- **Своя подпись у каждой плитки.** Launcher Label независима от имени объекта:
  переименование плитки не переименовывает сессию, а переименование сессии в
  обычном интерфейсе не перетирает подпись.
- **Управление:** долгое нажатие — переименовать или убрать плитку; перетаскивание
  меняет местами две плитки, ничего не теряя; всё сохраняется по серверу и
  переживает перезапуск.
- **Открытие по типу:** чат открывается существующей навигацией, бот — через
  `BotDestination` инбокса, группа — через новый вход `pendingRoom`, который
  резолвится по живой росписи соединения.

## 4.3.12 — доступ к дашборду по session-токену вместо пароля

- **Убран нерабочий вход на дашборд паролем.** `POST /dash/auth/password-login`
  принимал только пароль дашборда, а приложение знало лишь пароль WebUI — они
  различаются, поэтому `/api/profiles` и `/api/plugins/kanban` продолжали отвечать
  `401 no_cookie`. Вызов `dashboardLogin`, хранение пароля в Keychain и поле
  `username` удалены из `AuthManager`, `APIClient`, `Endpoints` и `KeychainStore`.
- **Доступ к дашборду — заголовком `X-Hermes-Session-Token`.** Сервер принимает
  статический токен `HERMES_DASHBOARD_SESSION_TOKEN` без cookie и без пароля.
  Приложение отправляет его на каждый запрос вместе с остальными пользовательскими
  заголовками, поэтому профили и Kanban открываются и после перезапуска.
- **Кнопка «Add Dashboard Session Token»** в онбординге и в Settings → Connection
  Headers добавляет готовую строку заголовка — остаётся вставить значение токена.
- **Подсказка в редакторе заголовков** теперь называет `X-Hermes-Session-Token` и
  объясняет, что он нужен для дашборда (профили, Kanban).

## 4.3.11 — профиль default и Kanban работают, вложения в отложенных

- **Приложение само логинится на дашборд.** После входа оно вызывает
  `POST /dash/auth/password-login` (`provider=basic`, `username=oleksandr`), получает
  session cookie — и `/api/profiles` с `/api/plugins/kanban` перестают отвечать
  `401 no_cookie`. Профиль больше не подменяется `administrator`, Kanban открывается.
- **Пароль хранится в Keychain** (по серверу) и используется при перезапуске для
  повторного входа в дашборд — профили и Kanban не отваливаются после перезапуска.
- **Отложенные сообщения комнат несут вложения.** `BotRoomComposerView.schedule()`
  конвертирует выбранные файлы в `ScheduledMessageAttachment` и передаёт в очередь.
- **Редактор отложенного сообщения умеет вложения:** показать, добавить, удалить;
  `setAttachments` сохраняет манифест, `syncToServer` отправляет его на сервер.

## 4.3.10 — профиль не перескакивает на administrator при открытии

- **Сессия восстанавливается только под активным профилем.** При запуске приложение
  больше не открывает последнюю сессию «вслепую»: если на сервере активен `default`,
  а последняя сессия была под `administrator`, приложение показывает список чатов
  вместо незнакомого профиля. Если токен дашборда не настроен и активный профиль
  неизвестен — тоже показывает список, а не угадывает.
- **Профиль не выдумывается.** Если `/api/profiles` недоступен, приложение не
  подставляет `administrator` — активный профиль остаётся неизвестным до успешной
  загрузки.

## 4.3.9 — Groups opens from the last saved list, and typing does not wait for the agent

- **The room list is painted from disk before the socket answers**, the same contract Chats
  has had: the previous `groups.list` snapshot is drawn at once and replaced by the live
  read. While it is a snapshot, a banner says “Showing the last saved list”.
- **A failed read no longer empties the screen.** The painted list stays and the banner
  appears; before, one failed `groups.list` replaced a usable list with nothing.
- **Skeletons no longer cover the cache.** `isLoadingRoster` treated “no bots” as “nothing
  to show”, so the Groups scope drew placeholder rows over the rooms it had just painted.
- The snapshot stores the raw `groups.list` payloads and is parsed by the same initializer
  as the wire, keyed by server and connection, so a cache cannot invent a shape the server
  does not use.
- **A streamed word no longer invalidates the screen that holds the composer.** The scroll,
  haptic and completion counters moved out of `ChatViewModel` into `ChatStreamState`, and
  the chat screen passes the object down instead of reading the values in its own body.
  Only a leaf view and the transcript observe them now. Before, every tick re-evaluated the
  whole screen — which is why typing stuttered and the keyboard lagged while the agent was
  working. Tests read the pulses through the stream state.

## 4.3.8 — the layout you set is the layout you get

- **Reorder applies immediately.** Both lists now read their order through `@AppStorage`, a
  real SwiftUI dependency; a plain `UserDefaults` read inside a function left the change
  invisible until relaunch. The dock had a second cause: it drew
  `allCases.filter(available)` and only checked membership, so the stored order was never
  drawn at all.
- **“Session list” is now “Main page rows”.**
- **Rename any entry.** A Rename section gives every dock section and every row its own
  field; an empty field restores the built-in name. Dock and row labels are separate keys,
  so “Kanban” in the dock and in the list can read differently.
- **Your own rows.** Title plus link, added and deleted on the same screen, drawn under the
  built-in rows. A row whose link does not parse stays in the editor and is not drawn: the
  list never carries a dead button.

## 4.3.7 — the dock and the main page are yours to lay out

- **Dock customisation.** Settings → Main Page → “Dock & order”: every section can be
  switched on or off and dragged into place, and that order is the dock's order. The app
  no longer decides on its own. A section whose feature is off (Bots needs Bot Mode,
  Kanban needs its section) stays listed with the reason and cannot be added until the
  feature is on — so the dock never carries a button that opens nothing.
- **Main page rows follow your order.** The utility rows above the sessions are drawn from
  a stored order plus the existing switches, and the same screen edits both. Removing a row
  turns its switch off: one source of truth, not two.
- Defaults equal the pre-4.3.7 layout, so an install that never opens the editor looks
  exactly as it did.

## 4.3.6 — New Chat belongs to the list, not to a chat

- **The floating Chat button is gone inside a conversation.** It is a list affordance: on
  the section root it starts a new chat; inside a chat the send button is the only action,
  and the floating one covered the composer's corner. It also no longer appears on the
  utility sections (Kanban, Settings), where a new chat is not the next step.

## 4.3.5 — a scheduled message carries its files

- **The chat's scheduled delivery sent the text and dropped the attachments.** The row's
  `attachmentsJSON` was written when the message was scheduled and uploaded, but the
  dispatcher carried only scalars (server, session, text, schedule key) and called
  `startChat` without `attachments`, so the files never left the device. The manifest is
  now decoded from the same one helper the model uses and passed to the send.
- Verified unchanged: an immediate chat send, the offline outbox, bot prompts (attachments
  travel as `@file:` / image references) and room sends (both immediate and scheduled) all
  already carry their attachments.

## 4.3.4 — the dock stays in every section, the button clears it, Kanban finds the dashboard

- **The dock no longer disappears in Groups/Bots.** It is drawn on every section root and
  leaves only for a conversation — a chat or a room — where its height fought the composer.
  The bot inbox now reports when a conversation is open, so the dock leaves exactly there.
- **New Chat sits above the dock by measurement, not by guess.** The dock publishes its own
  height through a preference; the button pads by that height + 16. Its old 16 pt were
  measured from the screen edge, which is why the dock clipped it.
- **Kanban asks the dashboard.** The plugin is mounted at `<host>/dash/api/plugins/kanban/*`;
  the app asked the webui root, which answers with the SPA's HTML — the decode failed and
  the screen looked dead. Kanban endpoints now carry the `dash/` mount unless the base
  address already has it.

## 4.3.3 — the FAB clears the dock, and the bot composer matches the chat

- **New Chat button no longer clipped by the dock.** The floating button was a sibling
  of a `Color` that ignores the safe area, so the ZStack stretched to the screen edge
  and the button's 16 pt were measured from there — under the dock. It is an overlay
  of the content now, whose bounds the dock's inset has already shrunk.
- **Bot and room composers sit at the chat's height.** The bot surface added 10 pt
  while the keyboard was up; the chat and the room add none. Removed, together with
  the keyboard observation that existed only for that padding.

## 4.3.2 — the dock goes where it navigates, and the default profile is first

- **One rule for the dock.** It is drawn on the Chats root and on the utility sections
  (Kanban, Settings) — the places it navigates to — and nowhere else. 4.3.1 hid it for
  *any* open destination, which left Kanban as a screen with no dock and no way back;
  it also still showed inside the bots branch, so the group and profile composers were
  as squeezed as the regular chat in 4.3.0. Both are the same rule now.
- **Default profile is the first row.** The server marks it with `is_default` but sends
  the roster in directory order, so `administrator` sat on top. Both profile pickers
  (Settings and the chat composer) sort default-first, then by name.
- **New Chat button normalised.** 20 pt trailing, 16 pt above the dock, no slide
  transition, drawn above the list — it no longer shifts when the dock appears.

## 4.3.1 — the four things 4.3 got wrong

- **Groups and Bots are different screens now.** 4.3 mapped both tabs to the same bots
  inbox; Groups opens it filtered to rooms, Bots filtered to bots, through one
  `BotInbox.Scope` instead of a second surface. Pins, sections and search follow the
  same filter, so neither tab shows the other's rows.
- **Kanban is in the dock by default and in its intended slot.** The tab was off behind
  an `@AppStorage` default of `false`, and `insert(at: tabs.count - 1)` placed it before
  Chats instead of before Settings.
- **The dock no longer follows you into a chat.** It was a bottom safe-area inset on the
  container that owns the NavigationStack, so it stayed on every pushed screen; with the
  keyboard up, dock plus composer left the transcript a single line. The dock is hidden
  whenever a destination is open.
- **The active profile is no longer forced to `administrator`.** The dashboard had been
  launched with `--open-profile administrator` and the sticky `active_profile` file held
  that name; `default` is the home profile, not the active one. The file is reset and the
  service starts without the flag.

## 4.3.0 — a dock, and five sections under it

The app had one screen with a mode switch: sessions, or the bots inbox, chosen by a
gate. Everything else — settings, tasks, kanban, saved, scheduled — was a push onto that
one stack, so "where am I" depended on how you arrived rather than on what you were
looking at.

- A dock of five sections at the bottom: Groups, Bots, Chats, Kanban, Settings. Drawn by
  the app rather than by `TabView`, because iOS on iPad puts tabs on top or in a sidebar,
  and a sidebar would have taken away the two-column master-detail the tablet has today.
- The selected section lives in the shared navigation state, so a deep link can switch
  section first and open the object second. A link that arrives while another section is
  on screen no longer navigates into a stack nobody is looking at.
- Sections that are switched off stay out of the dock: Bots behind its gate, Kanban
  behind its section flag.
- The composer keeps its own spacing above the dock; the dock is a bottom inset, not an
  overlay, so the transcript cannot scroll underneath it.

Groups is the first section that is not finished: the rooms list still lives inside the
bots inbox, and tapping Groups opens that inbox. Splitting rooms out of it is the next
change, and until it lands the section is honest about what it shows.
## 4.2.11 — chat text follows the system text size

The chat passed literal font sizes to MarkdownUI (`FontSize(16)`, `system(size: 13)`),
so the transcript ignored the iOS text size in both directions: below the default
setting it stayed at 16 pt and lost the density a smaller setting buys, above it
stayed at 16 pt and ignored accessibility.

- **`ChatTypography`.** Ported from upstream 2.2: 16 pt prose and 13 pt code at
  `.large`, resolved through `UIFontMetrics(forTextStyle: .body)` against the view's
  `dynamicTypeSize`, capped at 2.2×, and cached per size so scrolling cells never
  re-run font metrics.
- **The theme takes the size, not a literal.** `Theme.chat` receives `bodySize` and
  applies `FontSize(bodySize)`; headings and inline code were already relative
  (`FontSize(.em(...))`), so they follow the same scale.
- **Code blocks** use `ChatTypography.codeFont()` instead of a fixed 13 pt, and the
  highlighted path drops the engines' absolute fonts (Splash 13 pt, Highlightr Courier 14)
  the way upstream does, keeping bold/italic as presentation intents — otherwise a
  highlighted block stayed at the engine's size whatever the system setting was.

No layout, padding or control was touched: at the default text size every value
resolves exactly to what the app rendered before.

## 4.2.10 — one context menu for both authors

4.2.8 opened the message menu with two different mechanisms: a UIKit interaction
for user messages and a SwiftUI `.contextMenu` for assistant ones, while an
assistant reply also carried an inline text-selection interaction. The same
long press therefore did three different things depending on the author and on
whether the reply was still streaming.

- **One mechanism.** The transcript drops its SwiftUI `.contextMenu`; both
  authors go through the single `UIContextMenuInteraction` on the transcript's
  scroll view, which anchors the menu at the press point with a transparent
  1×1 preview — no bubble lift, no snapshot, no jump on a multi-screen reply.
- **One host per bubble.** `MessageBubbleView` applied two menu modifiers over
  the same frame (upstream's item list and this fork's ready-made menu), so which
  menu answered a press depended on hash order. It now resolves to a single list.
- **The long press belongs to the menu.** UIKit's own long press on the text
  interaction began a selection first, which is why an assistant reply could show
  no menu at all. That recogniser is disabled; selection stays on taps, double
  taps and the drag handles, and the explicit «Select Text» action still opens
  the full-text sheet.

Unchanged on purpose: every action and its order, Tapback (react / remove,
`isSelected`, emoji-image cache), streaming gating, VoiceOver actions, and the
Bot message menu paths.

## 4.2.9 — a room that says what it is doing, and a Send that can schedule

Two silences, both of which read as "the app did not get it".

- **The room shows each participant's turn.** `turn.started` and `turn.settled` were
  already in the room's event dictionary on the gateway; the client simply did not draw
  them, so a room looked dead for the whole turn and the answer arrived from nowhere.
  Each line now carries the author's name — "Build is working…", "Build answered",
  "Build failed: <reason>" — because a room answers with several bots at once and an
  unattributed line is one nobody can act on.
- **The header says who is working.** `groups.state` carries `member_activity`; while a
  turn runs, the header's second line names the participants instead of listing the
  roster. The host has no step history to show (`hosted_rooms.py:60-70` is a closed list
  of event kinds), so this is who and since when, not what.
- **Every participant's state is on screen.** A strip above the composer names each
  member and says what the host says about them: working (with the elapsed time and the
  tool), answered, failed, cancelled, deferred, or an outcome that is genuinely unknown.
  The last one is not shown as a failure — its actions are retry or remove, and calling it
  "failed" would misreport a turn that may have run. A live turn that has not moved for ten
  minutes is reported as "no answer", because the host still calls it running and there is
  no error to quote.
- **Scheduled room messages are actually sent.** The queue had an entrance and no exit:
  `enqueue` was wired to the composer and nothing ever called `due`, so a message sat in
  the store while the screen promised delivery. The loop now runs at app level — not inside
  the session list, which stops existing the moment the user opens a room — and sends each
  row with the `eventID` created when it was scheduled, so a retry cannot post it twice.
  A failure is recorded with its reason and the row stays visible; after five attempts, or
  on a refusal that cannot fix itself, it becomes terminal.
  Known limitation: delivery happens while the app is running. This build asks iOS for no
  background time (no `fetch` mode, no permitted `BGTaskScheduler` identifier), so a message
  whose time passed while the app was closed goes out at the next launch.
- **Send can schedule.** Long-press Send in a room opens the same menu the chat has —
  Send, Schedule Message — and Schedule Message writes through `RoomScheduleQueue` with
  the message's `eventID` and `threadID`. Before this, the calendar in the header opened a
  list nothing could add to.

## 4.2.8 — the calendar, the pins and one queue

Rooms were growing their own storage beside the chat's. Two things the chat already
does well, and a second implementation of each is how the composer and the header went
wrong in the first place.

- The trailing slot now says what the room can do: a **calendar** while nothing runs,
  the red **Stop** only when something is stoppable. A control drawn in the active
  colour is always pressable; when Stop cannot act it is absent, not greyed out.
- A **scheduled** screen lists everything waiting to go out: due time, how many attempts
  failed, the terminal reason in words, and retry or delete for each row.
- `PendingScheduledMessage` gained `eventID` and `threadID`. The first is the
  `event_id` `groups.send` deduplicates by: a retry after an uncertain result must
  carry the same id, or the message is posted into the room twice and the bots answer
  it twice. The second keeps a scheduled reply inside the thread it was written in.
  Both are optional with a default, so the existing database migrates without a new
  schema version.
- Scheduled room messages move onto that model (`sessionId = "room:<id>"`) and the
  separate JSON store goes away: one queue, one place for attempts and terminal
  failures, one "not sent" screen.
- Scheduled sends in rooms did not persist before 4.2.8 — there is nothing to migrate.
  They appear for the first time in this release, on the queue the chat already uses.
- Room pins ride on `SavedMessage`'s `isPinned`, which already survives a relaunch;
  the chat's pin persistence is scoped to `sessionId + serverURLString`, so opening a
  chat cannot clear a room's pins.

## 4.2.6 — the room header is the chat header

The room drew its own header row: a pill around the room's face, a `.bar` background
and a top safe-area inset. Three releases in, it still looked like a different app,
because it was a copy of the chat header's appearance rather than the components the
chat header is built from.

- `ChatToolbarTitleLabel` in `.principal` — the room's name over its composition, the
  same type and spacing the chat uses for the workspace line.
- `ChatToolbarActionCluster` + `ChatToolbarActionSlot` for search and Stop, so the
  icon size, weight, hit area and press state match the chat's toolbar by
  construction rather than by eye.
- Two separate `ToolbarItem`s in the trailing position, not a `ToolbarItemGroup`: the
  group is what iOS folded into its own "…" when a room name was long.
- The same `toolbarBackground` as the chat, visible.
- The composer is pinned with `spacing: 0`, as the chat does. The default inset gap
  sat on top of the composer's own padding, which read as a fat margin under a small
  composer.

## 4.2.4 — Stop says why, and the room opens without a pull

Two reports, both about a control that did nothing and gave no reason.

- **Stop is never disabled.** It was greyed out by five conditions none of which are
  visible on screen, so "it looks red and does not tap" was indistinguishable from a
  broken button. A tap that cannot stop now names the reason — nothing running,
  already stopping, waiting for the room to answer, or this sign-in not allowed.
- **A room opens on the first try.** The initial load could lose the race with a
  connection that was still being established, and the room then stayed empty until
  the user pulled to refresh. One retry covers it; a real failure keeps its message.

## 4.2.3 — a password is not rejected because of a newline

The sign-in form sent the password field verbatim, and a password pasted from a
manager or a note arrives with a trailing newline. `Basic` auth encodes it as
given, so the host answered `invalid_credentials` — indistinguishable from a wrong
password, in the app and in the server log. 277 such refusals were recorded on the
host before anyone suspected the field rather than the memory of the password.

- Line breaks are removed from the password before it is sent; spaces are kept,
  because a space can genuinely be part of a password.
- A space or tab at either end is now reported under the field instead of failing
  silently, and the password field no longer offers autocapitalisation or
  autocorrection.
- `Connect` stays disabled when the value is only a line break.

## 4.2.2 — room header you can actually use

The room put its controls in the system navigation bar, and on a phone with a
long room name iOS folded them into its own "…" that taps to nothing. Two
attempts at rearranging toolbar items changed nothing on the device, because the
collapse is the system's decision, not ours.

- **The room header is drawn by the app now**: the room's name and face on the
  left, then search and the red Stop on the right. A row we lay out cannot be
  folded away, so the controls stay where they are drawn.
- Stop stays in the header and is disabled when there is nothing to stop; it
  never disappears, so its position is predictable.
- **The app is called Hermex Plus again**, and installs under the same bundle
  identifier the 3.x line used.

### Known limitations

- **Schedule and attachments in rooms are not in this build.** Their storage,
  size limits and queue are in place, but nothing in the interface uses them
  yet, so a room composer still offers neither. They follow in the next release.
- **Changing the bundle identifier makes this a separate install.** The 4.2.x
  builds stay on the phone under their own icon, and drafts, cached history,
  favourites and keychain entries do not move across.

## 4.2.1 — room icons

- **A room can carry an icon** from a built-in set of 30 symbols in six
  categories, chosen in the room's profile and shown in the inbox row, the room
  header and search results.
- **Restore default removes the choice**, so a room you never customised looks
  exactly as it did: the faces of its first three members.
- Icons are drawn by shape alone — monochrome over a neutral container, no
  colour coding — so light and dark appearance both work without a second set.

### Known limitations

- **Room icons are local to the device.** There is no icon field in the room
  model yet, so a second device keeps showing the default faces; a synced icon
  needs a new room field and a protocol change.
- **An open room does not suppress its own notification.** The room-level
  presence that would do it is not in this build; a reply can still arrive as a
  banner while you are reading the room.

## 4.2.0 — group control leaves the composer

The first build to carry the 4.1 line. Everything between the published 4.0.6
and this release is here: the Bots composer now follows the same rules as
Sessions, and the group room no longer overloads its Send button with Stop.

### Group rooms: Stop and Search move to the top bar

The composer had one button that turned into Stop while the group worked, so the
only visible affordance for an additional instruction was the control that ends
the turn — a user who wanted to say one more thing pressed Stop. Composer and
execution control are now separate.

- **Stop is a top-bar control.** Red, visible whenever the room is working,
  blocked, stoppable or already stopping, and disabled by the same flag that
  describes whether stopping is possible — the control states its own
  availability instead of disappearing.
- **It stops the whole room**, not the selected participant, and it says
  "Stopping…" while the request is in flight so a second tap is not needed.
- **The composer sends again.** Sending an instruction while the group works no
  longer stops it: the button does what it says.
- **No silent refusals.** A second send while a command is still in flight is
  now named in the same pill every other refusal uses, instead of being dropped
  without a word.
- **Search in the room's top bar**, scoped to this room and carrying the room
  identity into the results. The query is part of the equatable request, so
  switching rooms cannot leave hits from the previous one on screen.

### The Bots composer, since the last published build

- **Voice notes** — hold to record, slide up to cancel, five-minute cap, one
  microphone session at a time; the clip lands in the same attachment draft the
  "+" picker feeds.
- **Choose model works on a bot that has none** — a bot created without a pinned
  model used to show no model control at all and refuse every change; the
  composer now offers the picker and the same sheet assigns the first model.
- **Send long-press** opens the Send / Steer / Queue menu, the way Sessions does.
- **Layout matches Sessions** — one row of controls inside the card under the
  editor, field padding 6, surface paddings 1/1, and mic and Send no longer
  scroll away with the selectors.
- **The attachment strip no longer reserves empty space**, so an empty composer
  is one line tall rather than one line plus a band.
- **One send gate** — "is there anything to send" has the same answer on both
  surfaces; the mode a send becomes stays Bots' own decision.
- **A quiet host is a state, not an endless spinner** — the chat asks the host
  where it is every 10 s, names the silence after 45 s and offers Stop there.
- **Telemetry names the surface** — `send button tapped` on the touch itself,
  `submit network send started` when the request leaves, and `surface: bots` /
  `surface: sessions` on every event.
- **An uncertain send is recoverable** — full snapshot plus "Send again" and
  "Mark as sent", instead of a bricked composer.

### Under the hood

- **One source for the version.** The release script now writes
  `Config/Version.xcconfig` and mirrors `VERSION` from it; the project references
  are unchanged, and a version bump can no longer leave the two disagreeing.
- **The test runner sees every test class.** The shard script matched only
  `class Name: XCTestCase`, so 41 of the 188 test classes never reached a shard —
  every subclass of a project base and every `@MainActor` suite among them, about
  six hundred cases. It now resolves attributes, modifiers and inheritance, scans
  test sources recursively, and fails closed when the discovered case count does
  not match the tree.

### Known limitations

- **Room icons and room presence are not in this build.** Both ship in 4.2.1:
  the built-in icon set with its picker, and the `room:<id>` presence that lets a
  notification for an open room be suppressed. Neither changes how a room behaves
  today, so nothing you can do now becomes impossible in between.
- **Group membership cannot be changed.** The gateway exposes `groups.create`
  with members and nothing else: there are no `groups.members.add` or
  `groups.members.remove` verbs, so adding or removing a participant is not
  offered in the interface rather than being simulated.
- **Push notifications need the plugin on the host.** The client already
  distinguishes reply, approval, clarify and failure and suppresses the banner
  for the chat that is open, but the `hermex-push` plugin is not installed on
  this host, so no notification is delivered at all until it is installed and
  the phone is paired. Publication of room events from the relay is unverified.
- **Three bot test suites are skipped in this build.** Nine cases in
  `BotConversationTests`, `ChatStreamCoordinatorTests` and `BotDraftTests` failed
  before this release and all nine still fail on the base commit with none of
  these changes applied. They carry a reason and a pointer to the registry in the
  repository rather than being deleted, so the debt is recorded instead of
  erased — but until it is paid, those three suites do not guard those paths.
- **The IPA is delivered as a link.** The build is larger than the 50 MB the
  cloud Bot API accepts for a document, so the release asset is published as a
  GitHub link with its `sha256` instead of an attachment.

## 4.1.4 — Bots composer: controls row back under the editor

4.1.3 shipped the controls row inside the editor's `HStack`, so the toolbar
stood to the right of the text field and squeezed it — the composer read as
deformed. Sessions keeps the row in the card's `VStack`, under the editor.

- `toolbarRow` moved out of the `HStack` into the `VStack` of `composerSurface`,
  gated by `showsToolbar`, with the Sessions insets (horizontal 8, bottom 6, top 2).
- Pill insets `.padding(.trailing/.vertical, isExpanded ? 0 : pillInset)` moved
  from the surface's `VStack` onto the editor's `HStack`, exactly where Sessions
  keeps them.
- Surface keeps the 1/1 paddings in the expanded state.
- Mic and Send/Stop pulled out of the horizontal control scroller, as Sessions
  does: a scrollable control on a phone-width row stays off-screen until the row
  is dragged, so only the selectors scroll now.

## 4.1.3 — Bots composer matches Sessions, Send long-press menu

- **Send button like Sessions:** long-press opens a context menu with
  **Send / Steer / Queue** instead of a separate modal card. Send goes straight
  out, Steer guides the running turn, Queue places the message behind the
  current one.
- **Controls row inside the card**, under the editor, so Send, Stop and mic sit
  on the same glass surface as the field instead of a separate bar underneath.
  Field padding 6, surface paddings 1/1, no opaque band — the same as Sessions.

## 4.1.2 — Bots composer laid out like Sessions

4.1.1 adopted the shared rules; the geometry still differed, and that is what reads
as "a different composer".

- **Controls row moved inside the card.** Sessions renders `toolbarRow` inside the
  glass surface (`padding(.horizontal, 8).padding(.bottom, 6).padding(.top, 2)`);
  Bots drew it as a separate row underneath, sitting on an opaque `systemBackground`
  band with negative padding and an `ignoresSafeArea` escape. That band is what made
  the Bots composer visually taller and visually detached from the field.
- **Field padding 12 → 6**, matching the value Sessions measured down from 12
  because the empty focused card read as four lines.
- **Surface paddings 2/4 → 1/1**, the same as Sessions.

Voice notes and Choose model (4.1.1 and 4.1.0) are unchanged; this release only
aligns the layout.

## 4.1.1 — the Bots composer uses the same rules as Sessions

Two of the Bots composer's own implementations were replaced by the shared ones,
and the workflow now builds `feat/**` on push instead of waiting to be started by
hand.

- **Attachment strip no longer reserves empty space.** Bots painted
  `ComposerAttachmentStripView` on every expanded state, attachments or not —
  exactly the band `ChatComposerGrowth` exists to remove (~25 pt above an empty
  field). It now asks `showsAttachmentStrip(hasAttachments:)`.
- **One send gate.** `canSend` was a private expression that combined content and
  the available mode. The content and busy half now comes from
  `ChatComposerSendGate.isDisabled(...)`, so "is there anything to send" has one
  answer on both surfaces; which mode that send becomes (send / queue / steer)
  stays Bots' own decision.
- **Pushes build.** `feat/**` added to the workflow's branches. Every run in this
  line had been a manual `workflow_dispatch`, which is why a failed build waited
  for someone to remember it.

The status pill stays: it carries reconnect, update sign-in, show request, cancel
upload, dismiss and retry — six actions the Sessions status line cannot express.

## 4.1.0 — cumulative: everything from 4.0.7 to 4.1.0

This release is the rollup the owner asked for: every fix shipped between 4.0.7
and 4.0.9, plus the two Bots gaps that were still open — a model picker that
refused to appear on a bot with no model, and a composer that could not record a
voice note.

### Bots composer catches up with Sessions

- **Voice notes.** The microphone button on the Bots composer had empty
  handlers: `isRecordingVoiceNote: false`, and no start, drag or end callback.
  Hold-to-record now works the way Sessions does — the clip is staged into the
  same attachment draft the "+" picker feeds, slides up past the threshold to
  cancel, and is capped at five minutes. A half clip is dropped when the screen
  goes away, and dictation stops first so only one microphone session is open.
- **Model picker on a bot with no model.** Creating a bot without pinning a
  model is allowed, and the host then reports an empty `model` in `model.options`.
  `BotModelCatalog.active` was nil, `mayChangeModel` required it to be non-nil,
  and `BotComposerSettings` drew its menu inside `if let active` — so a bot with
  no model showed **no model control at all** and refused every change. The one
  screen that could have fixed it was unreachable, and the user was left with a
  bot that could not answer and no way to give it a model. Now the composer
  offers **Choose model** whenever the host can accept one, and the same picker
  sheet assigns the first model.

### The silence this line is named after (4.0.9)

Sending a prompt could leave the chat spinning with no error, no reply and a
dead composer. The host had not hung: it was retrying a provider that answered
`402 Insufficient Balance`, and the client never learned how the turn ended.

- **Stall watchdog.** While a turn runs the chat asks the host where it is every
  10 s, which is enough to pick up a retained failure (`inflight.error`) and let
  the existing outcome row appear.
- **Named silence.** After 45 s with no answer the chat says so and offers
  **Stop**.
- **The submit window is covered.** `turn` now reaches `.submitting` when Send is
  tapped, the watchdog no longer disarms itself during `localOperation`, and
  `mayStop` includes `.submitting` — so the banner that names a silent host also
  carries the button that gets out of it. A request refused before dispatch
  restores `.idle` instead of stranding the composer mid-turn.

### Telemetry that fires (4.0.8)

- `send button tapped` on the touch itself, before validation: if it is missing
  from the log, the tap never reached the code.
- `submit network send started` when the request leaves the app: if it is present
  and no stream follows, the fault is on the host.
- `surface: bots` / `surface: sessions` on every event, so a stall names its
  screen instead of a synthetic session id.

### The Bots port fixes (4.0.7)

`json.loads` crash on malformed host answers; composer measured once per settle
instead of once per frame (nineteen `ComposerField` measurements in one second,
then "main thread stalled 2s"); duplicate diagnostic lines dropped within two
seconds; one answer per turn instead of several bubbles; copy while a response
streams; queue by tap instead of the upstream question card; Live Activity starts
from the delegate rather than an empty registry and notifies only on completion;
`reasoning.available` restored; `eventsRetried` counted at the retryable outcome;
the uncertain-send composer unbricked by a full snapshot plus "Send again" /
"Mark as sent".

## 4.0.9 — a quiet host is a state, not an endless spinner

Sending a prompt to a bot could leave the chat spinning forever with no error, no
reply and a composer that looked dead. The host had not hung: it was retrying a
provider that answered `402 Insufficient Balance`, and the client never learned
how the turn ended.

**Why the error never arrived.** The chat re-reads the host's snapshot only when
the host sends an event, and the host retains a failed turn's error *in that
snapshot* (`inflight.error` / `error_surface`). While a provider retries, there
are no events — so the client sat in `running`, the outcome row never rendered,
and a failure that the host was already holding stayed invisible. An endless
spinner and a frozen app look identical from the outside.

- **Stall watchdog.** While a turn runs, the chat asks the host where it is every
  10 s. That is enough to pick up a retained failure, so the existing outcome row
  appears — billing link, Retry, the provider's own words — instead of silence.
- **Named silence.** After 45 s with no answer the chat says so in plain words
  and offers **Stop**, because "still working" was a guess no longer supported by
  any evidence from the host.
- Both clear on the next snapshot and on any turn change; a resting chat starts
  no timer and spends nothing.

This does not fix the provider, the balance or the model pinning — it makes the
failure visible and actionable, which is what the app owes the user either way.

## 4.0.8 — bot telemetry that actually fires

The 2 s stall on 13.11 was captured, but the bot screen sent **zero** telemetry
events — “send tapped”, “submit start”, everything was missing from
`hermex-logs.jsonl`. If the button tap didn’t log, we couldn’t tell whether
the tap reached the code or the UI froze first.

- **`send button tapped`** now fires the instant the send button is touched,
  before any validation — if this doesn’t appear in the log, the tap never
  reached the code (UI freeze, dead button, wrong build).
- **`submit network send started`** fires when the HTTP request leaves the
  app — if this appears but no stream follows, the problem is on the host,
  not the app.
- Surface stamp `surface: bots` on every event so a stall is attributable to
  Bots vs Sessions without guessing.

## 4.0.7 — everything since 4.0.3, released

Bots fixes: `json.loads` crash on malformed host answers, composer measure once
per settle instead of once per frame (06:08:24 had nineteen ComposerField
measurements in one second, then "main thread stalled 2s"), telemetry surface
tagged `bots`/`sessions` so a stall names its surface instead of a synthetic
session id, duplicate diagnostic lines dropped within two seconds, send path
logged (tap / refused / start), one answer per turn instead of several bubbles,
copy while a response streams, queue by tap instead of the upstream question
card, Live Activity starts (host now comes from the delegate, not an empty
registry), notify only on completion, `reasoning.available` handler restored,
`eventsRetried` counted at the retryable outcome, uncertain-send composer
unbricked by a full snapshot and "Send again" / "Mark as sent".

## 4.0.6 — telemetry that can name the culprit

The 2 s stall of 13.11 carried a stack (`AttributeGraph`), a flag that the chat was
streaming, 150 messages and 68 displayed rows — and no way to tell **which** chat:
`sessionId` was synthetic and the screen field named the view class, not the surface.

- Every event now carries `surface` (bots / sessions), stamped by the composer that is
  on screen.
- Identical diagnostic lines within two seconds are dropped and counted, not shipped:
  one device log held 3 523 `ComposerField` and 3 823 draft events against 23 stalls.
- Freeze events report how many duplicates were suppressed.

## 4.0.5 — the Bots screen finally reports what it does

22 090 events on the host and **not one** carried a `Bot` screen: the ported
Bots UI shipped without telemetry, so every "the message does not send" report
had to be answered by reading code.

Three events now cover the path: the send tap (turn, connection, `maySend`,
`mayGuide`, uncertainty), a `submit refused` when the prepared action is stale,
and `submit start` with mode, turn, character and attachment counts. The next
failure is readable from `hermex-logs.jsonl` instead of guessed.

## 4.0.4 — the composer stops measuring on every frame

Device telemetry (hermex-logs.jsonl) put the freeze on record: twenty-plus
`ComposerField` measurements a second while the keyboard settled, followed by
"main thread stalled 2s" on ChatView. Every width change re-entered the
measurement, and each entry ran a synchronous `ensureLayout`.

Measurement is now coalesced into one pass 80 ms after the field settles, so an
animation frame no longer forces a text layout. Height can land one frame late;
it can no longer block the main thread.

## 4.0.3 — stability pass on the Bots port

Five things the port lost or widened, each found by a red test rather than by
reading the diff:

- **Live Activity never started.** The coordinator asked `ServerRegistry` for the
  host, which is empty outside the running app, so `start` was skipped silently.
  The host now comes from the delegate, with the registry as the fallback.
- **A failed run notified.** 3.9.74 alerted only on completion; the port widened
  the guard to every terminal state. Completion-only, as before.
- **`reasoning.available` had no handler**, so a finalized reasoning block never
  reached the transcript.
- **`eventsRetried` counted one short**: it was incremented on the next send
  instead of where the retry is decided.
- **An unconfirmed send bricked the composer.** `.uncertain` outranked every
  snapshot and no control could write again. A full snapshot now settles it, and
  the composer offers "Send again" / "Mark as sent" when the host stays silent.

Also: draft tests compared a whole `ChatDraft` against one with no `lastUsedAt`,
which the store stamps on every write.

## 4.0.2 — `@.ipa`: extension queries across the workspace

The composer's `@` panel listed one folder per query. A query whose segment is
only an extension names no folder, so `@.ipa` answered with whatever sat at the
workspace root — in practice nothing, and the file had to be found by walking
the tree a folder at a time.

- **`@.ipa`, `@*.ipa`, `@.PDF`** now walk the workspace breadth first and offer
  every file with that extension, sorted by path.
- **Bounded on purpose:** four levels deep and 120 folders per query, each
  directory listed at most once. A folder is never re-listed, so a host that
  reports a cycle cannot trap the walk, and the request count stays predictable
  on a slow host.
- **Nothing else changes:** a query naming a folder or a file keeps the old
  single-folder behaviour, and a segment with a slash is never treated as an
  extension.

## 4.0.1 — bots, brought over from the 1.9 line

Bots existed in this fork as a skeleton: 14 of upstream's 61 files, and none of
the transport they talk through. Every screen was there, nothing behind it could
connect. This release brings the feature over whole.

- **The Bots stack from v1.9.0**: 61 files, 18,016 lines, replacing the
  skeleton. Inbox, chat, rooms, creations, mentions, artifacts, history cache.
- **The transport it needs**: `Networking/Hermes` — `HermesConnection`,
  `HermesCall`, `HermesGateway`, `HermesREST`. Bots sign in to the host
  dashboard directly; WebUI stays the separate connection it always was, so the
  hybrid shape is upstream's, not a compromise of ours.
- **Push plumbing**: pairing, registrar, relay, preview, notification router.
- **Face ID app lock**: `AppLock`, `AppLockWindow` and
  `NSFaceIDUsageDescription`, off by default, app-wide.
- **Attachments in bots**: the full attachment picker and the camera controller
  behind it.

### Removed with the skeleton

- Thirteen tests in `BotPendingRequestTests` covered the skeleton's streamed
  desktop requests (`BotStreamRequest`, `streamRequest`, `mayDecline`,
  `declineDesktopTask`). The 1.9 line has no streamed-request surface, so those
  assertions could not describe it; the file's approval, clarify and credential
  coverage remains.
- `BotConnectionVersionTests` described the skeleton's tested-version note
  (`testedHermesVersion`, `untestedVersionNote`); the 1.9 line reports the
  host's version on the connection instead, so the file went with the skeleton.
- Three receipt assertions in `BotConversationTests` read `promptReceipt`,
  which the 1.9 conversation does not publish; the draft-clearing and call-count
  assertions they sat beside are kept.
- `BotChatPresentationTests` and `BotClientTests` described the skeleton's API:
  `isFocused`/`onResolveHeldMessage` on its chat screen, `mayDecline` on its
  conversation, a two-argument socket factory. That API is gone with the
  skeleton, so the tests went with it; v1.9.0's own bot tests (`BotAvatarTests`,
  `BotConversationTests`, `BotPendingRequestTests`, `BotActivityTests`) cover the
  replacement.

### What this build does and does not wire up

- **Wired:** the Bots inbox, creation, chat, rooms, mentions, artifacts and their
  dashboard transport; the chat's local Live Activities through
  `AgentLiveActivityManager`.
- **Present but not wired:** the push stack (pairing, registrar, relay, router,
  preview) compiles, but no application delegate adopts `PushAppDelegate` and no
  settings screen presents `HermexPushSectionView`. Face ID app lock
  (`AppLock`, `AppLockWindow`) compiles and `AppLock.shared.isLocked` is read by
  the composer, but nothing presents the lock window. Both arrive with a signed
  build: an unsigned IPA cannot carry `aps-environment` at all.
- **Bundle gaps still open:** `HermesAPSEnvironment` and
  `HermesKeychainAccessGroup` are read by the push code and are absent from
  `Info.plist`; `UIBackgroundModes` lists `audio` only, with no
  `remote-notification`; the ATS exception domain `100.64.0.0/10` is not a valid
  ATS key (CIDR is unsupported), and `NSAllowsLocalNetworking` is unset, so
  plain-HTTP access to a local bot host needs device verification.

### Fork adaptations, not copies

- `ChatMessage.displayMetadata` added: the Bots screens read reactions and
  delegation state from it, and the model never carried the field. Both host
  spellings (`display_metadata`, `displayMetadata`) decode.
- `BotHistoryCache.cost` rewritten with explicit loops. The chained `reduce`
  made the compiler give up on type checking and fail the target over one
  arithmetic line.
- `ChatMessageTimestampFormatter.separator(forUnixTimestamp:)` implemented
  locally; the fork's formatter only had `shortTime`.
- The attachment camera was appended to the fork's own `CameraPickerView.swift`
  rather than replacing it: the chat composer still opens that view.

### Guard against a repeat

`scripts/check-pbxproj-paths.py` resolves every registered `.swift` through its
group chain and fails when the file is not on disk. Three CI rounds were lost to
`Auth/Auth/…` and `Shared/Shared/…` paths that Xcode only reports at build time.

## 4.0.0 — cumulative line opens with measurement

4.0 is a cumulative release line: features land here one block at a time and
accumulate until the release is cut. The first block is telemetry, because a
cumulative build that mixes search, Face ID and rendering work is unmeasurable
without attribution — the 3.9.70 ProMotion regression cost two CI cycles
precisely because the change had no counter in the log.

### Telemetry

- **Share outcome is recorded.** `share received` proved only that a payload
  reached the routing switch; a staging or acknowledgement failure afterwards
  left a healthy-looking log and an empty chat. `share_staged` and
  `share_ack_failed` now bracket that path, so the funnel can be computed as
  arrived → staged → sent rather than guessed.
- **Memory has a curve, not just a death.** Physical footprint was sampled only
  at freeze time, which meant a session climbing to 1.5 GB stayed invisible
  until it died. A 30 s utility-queue sample records `memoryMB`, so growth is
  visible while it is still cheap to fix.

### Corrections to the previous audit

- `networkMs` was reported as unmeasured; it is measured and written to
  `loadMessages network` extras. The zeroed field in that event is `durationMs`,
  not the network figure.
- `mergeMs` was reported as dead; it is emitted conditionally, on
  `identityPreservingMerge slow` when the merge exceeds 50 ms.

### Inherited from the 3.9 line

Attachment picker available while the agent streams (3.9.73) and scheduled
messages keeping their attachments (3.9.74) both ship in this line unchanged.

### Identity

The 4.0 line installs beside the stable one: `com.braintimebox.hermex4`,
app group `group.com.braintimebox.hermex4`, display name "Hermex 4.0",
artefact `Hermex4-4.0.0.ipa`.

## 3.9.74 — scheduled messages keep their attachments

A scheduled message always arrived without its files. The model has carried
`attachmentsJSON`, `setAttachments` and an `init(pending:)` bridge all along, but
nothing ever filled the field: `saveScheduledMessage` built the row from the text
alone, so the composer's attachments were dropped at schedule time — before any
delivery code ran.

- **Capture at schedule time.** The composer's pending attachments are mapped
  into `ScheduledMessageAttachment` and stored on the row; the composer is then
  cleared, because those attachments now belong to the pending message and would
  otherwise be sent twice.
- **Attachment-only messages are allowed.** Scheduling a file with no text is a
  legitimate send, so the emptiness guard accepts either text or attachments.
- **Same-chat delivery restores them.** "Send Now" into the current chat hands
  the stored server-side paths back to the composer (`restorePendingAttachments`)
  before sending, so the upload is not repeated and the send carries the files.
- **Cross-chat delivery passes them to the API.** `startChat` has always accepted
  `attachments`; the scheduled path simply never used it. A small
  `toJSONValue()` mirrors `PendingAttachment`'s payload exactly.
- **Server sync includes them.** The autonomous dispatcher can only deliver what
  it was told about, so the webhook body now carries the same attachment list
  when non-empty. A host that ignores the field behaves exactly as before.

Existing rows keep `attachmentsJSON = nil` and remain text-only — no migration is
required, and none was performed.

## 3.9.73 — attachments stay available while the agent is working

Picking an attachment stalled whenever a run was in flight: the Attach menu
(File / Photos / Camera) was disabled together with the configuration controls,
because both used `isConfigurationControlDisabled`, which includes
`isWaitingForStream` (`ChatComposerView.swift`).

- **The Attach menu has its own gate now** — `isReadOnly || isUploadingAttachment`.
  Staging an attachment only fills the draft and leaves with the next send, so a
  running stream is no reason to close the picker. A second upload in flight still
  blocks another one.
- Configuration controls keep the stricter gate: changing the model, workspace or
  profile during a run is still refused.

Version bump is a single line in `Config/Version.xcconfig`; `VERSION` is
regenerated and the 16 + 8 project references follow.

Not included: scheduled messages still drop attachments at creation time
(`ChatView.swift` builds `PendingScheduledMessage` without `attachmentsJSON`).
That is a separate change and a separate build.

## 3.9.72 — one source for version, build number and identity

Version and identity were typed into many places at once, so a release could
ship a build whose About screen, IPA file name and CI artifact disagreed. This
release removes the places where that is possible.

- **`Config/Version.xcconfig` is the only place with numbers.** `APP_VERSION` and
  `APP_BUILD` live there; the project's 16 `MARKETING_VERSION` and 8
  `CURRENT_PROJECT_VERSION` entries now reference them, and `VERSION` is a
  generated mirror written by `scripts/sync-version.py`.
- **`Config/Identity.xcconfig` is the only place with identity.** Bundle id, app
  group, URL scheme, display name, product name and line. `APP_DISPLAY_NAME` left
  `project.pbxproj` (it was duplicated there), so renaming an app is one line.
- **A line is a file, not a merge.** The test line installs beside the stable one
  by changing `Identity.xcconfig` only; nothing in the project knows which line
  it is.
- **Gate 14 no longer pins one literal bundle id.** It used to require exactly
  `com.braintimebox.hermexplus`, which made a second installable line impossible:
  the test line's `...hermex4` tripped the gate and the build never ran (run
  42391831464). The invariant is now "not upstream's namespace, and the app group
  matches the bundle id".
- **Gate 18 is new:** it fails when `VERSION`, `Config/Version.xcconfig` and
  `project.pbxproj` disagree, when a numeric version literal reappears in the
  project, or when `APP_DISPLAY_NAME` is set outside the identity file.
- **`release-check.py` resolves `$(APP_VERSION)`** instead of only accepting a
  numeric literal, so the single-source form passes the release invariants.
- Gate headers no longer print a denominator: the numbers were stale (9, 13, 15,
  16, 17 coexisted) and contradicted each other in the same run.

No runtime behaviour changes: no view, model or networking code was touched.

## 3.9.71 — ProMotion request reverted: it made streaming choppier

3.9.70 asked both display links for `preferredFrameRateRange 60...120` to make a
90–120 fps target measurable. On-device telemetry from a 3.9.70 session (build
202611071504, iPhone, iOS 27.2, thermal fair, 149 events) shows the opposite of
the intent:

| scenario | 3.9.68 | 3.9.70 |
|---|---|---|
| stream, frames > 33 ms | 7.61 % | **17.37 %** |
| stream, frames > 16.7 ms | 3.07 % | **8.42 %** |
| `frameAvgMs` per stream commit | ~16–35 ms | **31–66 ms** |

An average frame of 43–66 ms during generation is 15–23 fps. The range made the
system target a rate the pipeline cannot hold, so frames arrived unevenly
instead of simply at 60 Hz. Sample is small (190 stream frames) but the direction
matches the reported symptom.

- **Range removed from both display links.** Default pacing is restored. ProMotion
  is not the path to smoothness while the frame budget is still exceeded; the
  budget has to be freed first.
- **`refreshRate` now always has a value.** 3.9.70 recorded `refreshRate: 0`
  because the window scene is not connected when the watchdog starts; it now
  falls back to the screen's maximum.

Unchanged: the keyboard focus fix (generation guard + `isFocused` recheck), jank
`heavyOp` attribution, device context, composer prev → next diagnostics. None of
them touch the streaming render path.

No FPS claim. The next step is measuring whether the revert restores 3.9.68
streaming numbers before any further work on frame pacing.

## 3.9.70 — Keyboard focus survives, and telemetry starts naming causes

Baseline measured on 3.9.68 before any change (22 557 events, 31.10–07.11):
scroll frames over 33 ms 2.52 %, scroll+stream 5.33 %, stream 7.68 %; jank
15.38 per 1000; stalls 0.44 per 1000; `transcriptMessages.fullRecompute`
69–111 ms; composer oscillation 6 cycles; share 57.7 % (received → agent
stream); draft completion 99.4 %. Of 347 jank events, 0 carried a `heavyOp`
or a stack — the most frequent symptom could not name its cause. The frame
histogram reported p50 = 16.67 ms in 96.4 % of scroll windows, so a 90–120 fps
target was unmeasurable rather than merely unmet.

- **Keyboard: a queued blur can no longer close a newer editing session.** The
  deferred focus task rechecked only `textView.isFirstResponder` before calling
  `resignFirstResponder()`, so a task scheduled before a new focus session could
  dismiss it — the reported "keyboard drops while I type". It now bumps a
  generation on every request and rechecks both the generation and `isFocused`
  (upstream 1.8.0 / 1.9.0).
- **ProMotion is requested explicitly** on both display links. `Info.plist`
  already carried `CADisableMinimumFrameDurationOnPhone`, but without
  `preferredFrameRateRange` the link stays at 60 Hz and every window reports
  16.67 ms. This makes the frame budget measurable; it does not by itself
  raise the frame rate.
- **Jank carries attribution.** Above a 100 ms frame the event now records the
  in-flight `heavyOp`, the rendered row count and the streaming/scroll context,
  so a jank spike names its cause instead of only its size. Stack capture is
  deliberately absent: `MainThreadStackCapture` reads the *main* thread's
  registers and is unsafe when called from the main thread (it crashed the test
  host with SIGSEGV). A safe capture needs a background hop plus correlation;
  that is a separate change, and per-frame stack traces are excluded by design.
- **Device context once per launch:** model, iOS version, build number, screen
  refresh rate, thermal state, low-power mode and physical memory. Freeze
  severity is not comparable across devices or thermal states without it.
- **Composer height events carry prev → next**, so the 218 ↔ 253 oscillation
  can be diagnosed rather than merely counted. Diagnostics only; no smoothing
  or delay was added to hide it.

No optimisation of the transcript or scroll path is included: neither is claimed
until it is measured. 90–120 fps is not claimed for this build.

## 3.9.68 — Diagnostics survive the network and the crash

`HermexLogger` was fire-and-forget: it removed an event from a memory array
before the POST resolved, and passed an empty completion handler to
`URLSession`. A dropped connection, a 5xx or a force-quit deleted diagnostics
permanently — including the events logged right before a hang, which are the
ones worth keeping. A separate measurement put the loss at 22.95% (12 332 of
41 397 keyed events). Three things change.

- Events are durable before they are sent. `TelemetryEventQueue` appends each
  event to `Application Support/HermexTelemetry/pending-events.jsonl` before the
  first network attempt and removes it only when the server confirms it. The
  queue is restored on launch, so a kill mid-flight loses nothing.
- The reply is actually read. `send()` now inspects the status, the body and
  `ok`, and uses the server's `received` count to decide what to remove. A 2xx
  with an unreadable body is not a confirmation. A retried batch legitimately
  answers `stored: 0` with `received: N` — the server counts duplicates — so
  only `received` is used as the ack.
- Retries are bounded and categorised. Transport errors, timeouts and 5xx back
  off 1 → 2 → 4 → 8 → 16 → 30 s, then once per 30 s; 429 honours `Retry-After`
  (clamped to 1…600 s); 413 halves the batch instead of repeating it; permanent
  4xx (400/401/403/404/…) are quarantined in place — kept on disk with the
  reason attached — so one bad event cannot block the queue.

Identity is `correlationId:seqNo`, the same key the server deduplicates on, so a
resend after a lost response cannot create a duplicate. The queue is capped at
10 000 events; overflow evicts the oldest non-priority event first and keeps
`freeze`/`error` as long as possible, counting every drop.

Not measured yet: whether delivery actually improves on a device. That needs a
build installed and a run with the network cut; no reliability claim is made
here.

## 3.9.67 — The chat stops freezing while the cache is written

- Session cache writes ran on the main thread. `CacheStore.cacheSessions` and
  `cacheSession` were `@MainActor`, while their callers already ran on
  `sessionWriteQueue` with a context created there — so every write hopped to
  main and did fetch + upsert + save + maintenance there, against a context
  owned by another queue. 3.9.64 telemetry: `Cache Write (sessions)` at 4 225 ms,
  6 999 ms, 2 638 ms, 2 043 ms, with freezes of 3 262 ms and 3 053 ms in the
  same period. Both writers are now non-isolated, like `cacheMessages` already
  was, and the fork path writes through the same queue.
- Freeze attribution was lying. `HeavyOperationTracker` kept one global label,
  so a background write overwrote the main-thread label and its `end()` cleared
  it: a 3 262 ms freeze was reported as `CacheStore.cacheMessages`, which runs
  off-main. The tracker now ignores begin/end outside the main thread;
  background work remains visible through its own phase.
- Gate 11 (duplicate call arguments) grouped all `(` before all `)`, so on
  `) ?? ModelCatalogOption(` the close removed the frame the open had pushed.
  That produced a permanent false "providerID passed twice" on
  `ModelPickerSheet.swift:881` — in code that compiles and whose suite is green.
  Parentheses are now applied in source order.

Not measured yet: whether the freezes are actually gone on device. That needs a
build installed and new telemetry; no performance claim is made here.

## 3.9.66 — Diagnostic: measure the cost of a streaming commit

(Reserved for the instrumentation branch; not part of this release.)

## 3.9.65 — A scheduled message stops retrying what can never succeed

- Scheduled delivery ignored `DeliveryFailure.retryable`. One message addressed to
  a chat the server no longer had produced **620** `POST /api/chat/start`
  requests over 68 hours, every one answered `404`. A non-retryable failure is now
  terminal on the first attempt; a retryable one stops at five attempts. The row
  stays in the list with the reason, so the user sees what was not delivered
  instead of a message that silently loops forever.
- `intervalAvgMs` counted the pause across background as a commit interval. In
  3.9.64, 27% of intervals were over 5 s, p95 was 163 570 ms and the maximum
  19.5M ms. A pause now closes the stream, and its length is reported separately
  as `intervalGapCount` / `intervalGapMaxMs` instead of being averaged in.
- `draft setContent` recorded that a write happened but never how long it took:
  3 437 events, all with `durationMs = 0`. The write itself is now measured.
- The watchdog's recovery line printed its own template
  (`main thread recovered after \(Int(frozenFor))s`) instead of the number.

On the 404 itself: the session had never been written to disk and no longer
existed on the server, so `POST /api/chat/start` had nothing to attach the
message to. The client change stops the loop; re-creating a session
automatically is deliberately **not** done, because that would silently fork the
conversation context.

`Stream Batch Apply` needed no change: it was reported as a constant 1.0 ms
because the column read was `mutated` (0/1), not the duration. Actual durations
span 0.001–123 ms.

## 3.9.64 — The device build gets the cache the test build already had

- `Package IPA` compiled all 688 Swift files on every release (6:18) because the
  device build had no DerivedData cache. It now restores products and source
  mtimes the same way `unit-build` does.
- `SourcePackages` travels inside the `test-build` artifact instead of being
  restored from a separate cache in the test job. That restore cost 101s of
  download and untar — the same order as the 108s of cloning it replaced — so
  the test job now has no package step at all.

Still open, documented rather than solved: app-hosted tests install the 83 MB
app on every run (2:49), and teardown waits 55s for background work to stop.

## 3.9.63 — A release no longer throws away its own cache

- Cache keys no longer include `project.pbxproj`. It carries `MARKETING_VERSION`,
  so every version bump produced a new key and a cold build: shipping was
  invalidating the thing that makes shipping fast. Sources and package manifests
  now define the keys; build-setting changes are left to Xcode's up-to-date check.

Carried over from the scheduled-message work:

- The schedule sheet no longer renders a "Message" block.
- Scheduled delivery records its failures and sends a stable `clientMessageId`.

## 3.9.62 — The pipeline stops paying for signatures nobody checks

CI only. The simulator does not verify code signatures, but both the test build
and the test run were signing with an ad-hoc identity, and the test run also
re-resolved the package graph that had just been restored from cache.

- `CODE_SIGNING_ALLOWED=NO` for the simulator build and the test run; the
  device build that produces the IPA is unchanged.
- `-disableAutomaticPackageResolution` in the test run.

Scheduled messages:

- The schedule sheet no longer shows a "Message" block. The text lives in the
  composer; a read-only copy still read as an empty text field and took the
  vertical space the date picker needs.
- Scheduled delivery now records its failures. It used to swallow every error in
  `catch { continue }`, so a user seeing "HTTP 501" left no trace in telemetry —
  not even the attempt.
- Scheduled delivery sends a stable `clientMessageId` (the schedule key), so a
  retry after a timeout is deduplicated by the server instead of starting a
  second turn.

Measured before the change: 131s between "resolved packages" and the first test
case (install + runner startup), 32s of package resolution, 80s of actual tests.

## 3.9.61 — A send that survives a dropped connection

Telemetry from 3.9.58 (`15:09:30`, `network.url.-1001`, `path=send`,
`retryable=false`) showed a send that never reached the server and came back to
the composer as a draft. Two defects made that the outcome:

- The send path called `startChat` directly. `startChatWithRetry` existed and had
  never been called by anything — the retry loop was dead code.
- `clientMessageId` did not exist, so a retry could not be told apart from a new
  message and the app correctly refused to retry a timeout.

Now every send carries a `clientMessageId` — the local message id, created once
when send is pressed — and the server replays the first turn for a repeated id
instead of starting a second one. With that guarantee, a timeout and a lost
connection are retried instead of ending the send.

A durable outbox takes over when the inline attempts run out: the message is
kept in app storage, retried on a timer and immediately when the network path
comes back, and the composer keeps no copy. The bubble stays in the transcript
while it waits, so a queued message does not look like it disappeared.

CI: five test shards instead of three. A shard no longer compiles — it downloads
the built products in eight seconds — so the only cost of another shard is a
runner. Measured on 3.9.60: a shard's suite is ~8 minutes, which the previous
11-minute compile had been hiding.
## 3.9.60 — One build for all shards; the picker stops inventing models

CI compiled the app four times per run: three shards each ran build-for-testing
and the Release job built its own device copy. Three runners paid for the same
688 Swift files (4.4 min on a fast one, 11 on a slow one), and the slowest set
the wall clock. A new `unit-build` job compiles once, uploads Build/Products and
the .xctestrun, and the shards run `test-without-building` against that artifact.
The cache keys also stopped using the commit sha, which had produced 22
unreachable entries (2.97 GB of a 10 GB budget) that no run could ever hit.

Model picker, two defects that made the catalog disagree with Telegram:

- The live endpoint overwrote the curated list for the active provider. Nous
  answers 424 ids, so the picker read 428 while Telegram showed 57 + 7. Live is
  now a fallback that fills an empty group, never an override.
- The composer model menu rendered the bare model name, so favourites holding
  the same id from different providers were indistinguishable. The provider now
  rides in the title.

The composer config cache is keyed on the app version. It held a catalog for 24
hours regardless of what the build did, so a shipped catalog change could look
like it never happened.
## 3.9.59 — Schedule sheet: the text comes from the composer

The schedule sheet carried its own editable "Message" box, seeded from the
composer. That duplicated the field the user had just typed into, and the box
plus its keyboard pushed the date picker to the bottom of a four-section form —
the calendar is the reason the sheet is opened at all.

The editor is gone. The composer is the only place text is written; the sheet
shows a two-line read-only preview so "what am I sending" stays answered, and
the date and time now own the space. Behaviour, destination rules and the
five-minute default are unchanged.

## 3.9.58 — Scheduled messages show their text; share reaches the chosen chat
- Scheduled list: each row leads with the message body (two lines) and keeps
  destination + date + time underneath. The row had been reduced to
  "chat · time", so every entry looked alike and reading one required opening
  Edit.
- Share sheet → existing chat: the chosen chat now receives the shared text and
  attachments. `ChatView` accepted `initialDraft`/`initialAttachments`, but the
  navigation call computed them and never passed them on — the payload was
  dropped silently.
- Share sheet: choosing a chat now consumes the pending import (same as New
  Chat and Cancel), so the destination dialog stops re-asking on every return
  to the app.

## 3.9.57 — Share via URL payload, provider shown under each model, ProMotion enabled
- Share sheet: a text share now travels inside the open URL again, exactly as 3.6.0 did. The 1.6.0 sync removed that path and left the App Group container as the only transport, but a SideStore re-sign does not reliably keep the App Group entitlement — so the extension wrote into one container, the app read another, and the share vanished silently. Neither the container nor a named pasteboard can fix that: both are App-Group scoped. Only the URL payload needs no entitlement.
- Share sheet: a share with attachments (or text over 6 KB) still uses the container, with the pasteboard as a second chance.
- Model picker: each row now prints its provider under the model name. The same id (`anthropic/claude-fable-5`, `google/gemini-4-argon`) is served by several providers, so a bare name could not tell which one a tap would select.
- Performance: added `CADisableMinimumFrameDurationOnPhone`. Without it iOS caps the app at 60 fps on a ProMotion display; telemetry shows p50 = 16.67 ms on every build from 3.9.47 to 3.9.52 and never 8.33 ms.
## 3.9.56 — Share sheet: payload mirrored onto the pasteboard again (3.6.0 → 3.7.0 regression)
- Share extension: every share is now written to BOTH the App Group container and the named pasteboard, unconditionally. The 1.6.0 sync removed the pasteboard and left the container as the only transport; a SideStore re-sign does not reliably keep the App Group entitlement, so each target got its own sandbox container, the extension's write was invisible to the app, and the share vanished with no error. The 3.9.22 fix only covered a nil containerURL(), which is not this failure mode.
- Share import: the app still prefers the container inbox and now clears the pasteboard copy once claimed, so a working container wins and nothing imports twice.
- Share banner: the "a share is waiting" hint probes both transports instead of the container only.
## 3.9.55 — Schedule default 5 minutes; CI: Xcode 26 compilation cache + simulator preboot
- Schedule sheet: default send time is now 5 minutes (was 60), matching the Telegram composer. An hour read as a bug — a user who wants an hour sets one.
- CI: Xcode 26 Compilation Caching (LLVM CAS) enabled in both macOS jobs — content-addressed, so a stale entry cannot produce a wrong build. Industry-measured gains: Wikipedia iOS −24%, Pocket Casts −36%.
- CI: simulator preboot moved to the background so its cold boot overlaps the 289s test build instead of being paid after it (measured: 203s of empty log between build end and first app log on run 40172846270).
- Network: transport failures (-1001/-1005/-1015/-1016/-1017, 408/502/503/504) now render the cached list instead of an empty screen; only idempotent reads retry — sends keep one attempt because the server has no client_message_id.
- Composer: the outgoing text is no longer written into the durable draft before the request, so rehydration cannot hand a sent message back into the field.
- Scheduled messages: one-line rows (clock, preview, chat · time) with actions behind a menu, down from ~120pt.
- Clarification card: capped at 200pt (question 90, choices 110) so the chat stays visible above the keyboard.
- Build: MainThreadWatchdog.setPerformanceContext gained its missing heavyOp parameter and CacheFallbackPolicy regained isTransportFailure — main has not compiled since 3.9.51.
## 3.9.51 — Diagnostics: correlation IDs, session tracking, query endpoint, telemetry improvements (freeze diagnostics, fault tree, server correlation)
- HermexLogger: correlationId, seqNo, action log, ring buffer 100
- MainThreadWatchdog: HeavyOperationTracker expanded (SSE, Cache, Decode, Markdown, Stream)
- PhaseTelemetry: durationMs in phase aggregates
- Server: correlation/session/seq tracking, /events query endpoint
- Fault tree: docs/diagnostics-fault-tree.md
## 3.9.50 — Markdown streaming reverted to LightEngine; X-Hermex-Request-ID; nginx timeouts 300s
- Markdown streaming reverted to LightEngine (Text(verbatim)) due to watchdog p90 regression (35% >50ms on 3.9.49); block pipeline retained for settled content.
- Added X-Hermex-Request-ID UUID header to HermexLogger POST /webhook/hermex-logs for correlation with proxy-1118 logs.
- Nginx proxy timeouts increased to 300s (proxy_read_timeout/connect_timeout) to reduce idle-timeout drops on mobile networks.
- Minor fixes: ServerCatalog refresh, project-snapshot documentation.

## 3.9.50 — Markdown streaming reverted to LightEngine; X-Hermex-Request-ID; nginx timeouts 300s
- Markdown streaming reverted to LightEngine (Text(verbatim)) due to watchdog p90 regression (35% >50ms on 3.9.49); block pipeline retained for settled content.
- Added X-Hermex-Request-ID UUID header to HermexLogger POST /webhook/hermex-logs for correlation with proxy-1118 logs.
- Nginx proxy timeouts increased to 300s (proxy_read_timeout/connect_timeout) to reduce idle-timeout drops on mobile networks.
- Minor fixes: ServerCatalog refresh, project-snapshot documentation.

## 3.9.49 — live markdown while streaming. The 3.4.0 engine rendered the growing assistant reply as plain Text(verbatim:) and switched to the full MarkdownUI rendering only when the stream settled — the whole reply was read as a wall of raw glyphs (`**bold**`, bare list markers, unpainted code fences) and the formatted version popped in at completion. The block pipeline that predates 3.4.0 (StreamingMarkdownChunkedView) is back on the live path: settled markdown blocks render fully formatted as they arrive, the still-growing active block re-renders coalesced to one scan per frame, and the glyph fade window carries over unchanged. The old O(N²) per-token re-parse that motivated the plain engine was already removed by that coalescing; the retired plain engine's regressions concern (quadratic layout) does not apply to what returns here. The >4000-character / >2000-line plain fallback for extreme content stays. Acceptance: `stream`-tagged frames >50 ms must not exceed the 3.9.47 baseline of ~1.97% on long replies — telemetry will judge

## 3.9.48 — telemetry stops lying about stream gaps and fetch retries. The stream-commit aggregator cleared its counters on stream end but not the last-commit timestamp, so the first commit of the next response measured its interval from the previous day's last commit — background time landed in intervalMaxMs, producing windows claiming 6-hour commit gaps whose own frame average was a healthy 16.7 ms (verified 125/125 anomalous windows in the 3.9.47 telemetry); the stamp is cleared on endStream now, so an interval can only be measured inside one stream. The session fetch behind every chat open reports its retry-attempt count in the `loadMessages network` line — the attempt count separates a clean fetch from one the retry ladder carried (1s/2s/4s/8s), which resolves the 51 sub-90-second pairs of load lines seen in 3.9.47 into distinct attempts instead of unexplained duplicate loads. Retry policy, backoff schedule, network behaviour and UI are untouched

## 3.9.47 — three things the user could not do: copy a whole reply, keep a pin, manage a file. Copying: a long press on an assistant reply landed in the UIKit text-selection adapter, which owns the gesture and offered only what was selected — one paragraph; "Select All" then "Copy" was the only route. The whole response is now a single menu item, placed first. Pins: the set lived in a @State array on ChatView and evaporated on the way out of the chat, so every pin had to be redone after a relaunch; the flag now rides on the SavedMessage row, which survives, and the stored text is no longer cut at 200 characters — a pin is a promise to be able to read the thing again. Files: the server has served delete/create/rename/move/create-dir all along (api/routes.py:15451-15472); the browser was read-only only because nothing wired them up. Manual file management is client work. No server change, no new dependency, and the server stays the source of truth — every mutation re-lists its directory instead of patching the tree locally

## 3.9.46 — the pinned message reads as an object again. It was a full-bleed frosted strip with no rounding, sitting directly under a nav bar that is also a light opaque surface, so it read as part of the header chrome rather than as a marker that something is pinned. It is now a card: inset 12pt from both edges, rounded, with a hairline stroke, and carrying a 3pt role-coloured accent bar on its left edge — accent blue for an assistant reply, neutral grey for the user's own message. The `You` / `Hermes` label is gone: it spent one of the card's two lines on something the transcript already states by position, so the preview now owns the full width, and the pin moved to the trailing edge where it marks the card instead of opening it. Tap-to-scroll, the pinned list, unpinning and the "+N" badge are unchanged; pinning logic, SavedMessage and the message-action menu are untouched

## 3.9.45 — approval UX and transcript density. The approval request no longer dims the whole screen: the scrim that hid the transcript is gone, so the command can be judged against the conversation that produced it. The command itself stops being a one-line horizontal scroller and becomes a wrapped block clamped to four lines with an explicit "Show full command" disclosure, so a long pipeline can actually be read before it is approved. Both approval methods now refuse to run while a response is already in flight — the buttons disable through a SwiftUI state change that lands on a later runloop tick, which left a window in which a second tap posted a duplicate decision for the same approval id; regression test included. Transcript row spacing 8 -> 6pt, roughly two extra rows of content per screen. Permission semantics, the ApprovalChoice model and the server protocol are untouched

## 3.9.44 — reliability: the active stream recovers instead of parking itself after one failed probe. A single transient failure of /api/chat/stream/status used to surface an error and leave the stream suspended for good: isConnectionSuspended stayed true, reconnectTask was cleared, and the1s refresh loop skips a suspended connection, so nothing re-armed the probe until a lifecycle event or a new send. Port of upstream PR #585 (fixes #537), adapted to the fork's shared backoff: the probe now retries inside the same single-flight task, four attempts total (upstream's budget), sleeping1s/2s/4s through HermesRetryBackoff so tests can zero the wait. A probe failure is retried only when it is transient — connectivity URLErrors, request timeouts,502/503/504 — anything else still surfaces immediately, and exhausting the budget surfaces the last error instead of hanging silently. chatStreamStatus carries an explicit10s timeout so the reconnect budget stays in seconds rather than waiting the60s session default. Backoff only re-arms the probe: it does not decide whether an earlier POST landed and never resends one. Presentational and .fixedSize work untouched
## 3.9.43 — readability: the assistant reply finally has a container. It rendered as bare text floating on the transcript background — no background, no border, no inset — so there was no boundary between one reply and the next and no contrast anchor for the eye, while the user bubble has had background/border/inset all along. The assistant row now carries the same containment (rounded background, hairline border, 14/10 inset), applied after the streaming animation modifier so the container stays static while the text grows. Composer, scrolling, markdown styles, ProMotion, persistence queues and the Message Pipeline are untouched; this is a presentation change only

## 3.9.42 — diagnostics only: fix two telemetry defects found by 3.9.41. (1) The stream-commit window is now flushed when the stream ends, so a short stream no longer loses its last window (3.9.41 emitted zero streamCommit events while six Stream Batch Apply phases proved streaming ran). (2) isStreaming is published from the stream coordinator at stream start/end instead of from messages.didSet, which never fires for in-place streaming edits — this also removes a stream-tag under-count bias in the 3.9.40 baseline. No behaviour change

## 3.9.41 — diagnostics only: stream-commit telemetry. A new `streamCommit` channel (per 2s window) records commits, accumulated/delta chars, commit interval, stream age, follow-latch state, programmatic follow-scrolls and the frame each commit landed in — enough to tell apart follow-scroll contention, full-text relayout, initial-layout dominance and coincidence with background operations. The 3.9.40 frame channel and the jank channel are untouched. No behaviour change

## 3.9.40 — diagnostics only: frame histogram. Every 2s window now logs the distribution of ALL frames (buckets <8.33 / 8.33-16.67 / 16.67-33.33 / 33.33-50 / >50 ms, percentiles p50-p99, max) with one context tag (idle / scroll / stream / scroll+stream / app_update). The existing jank event is untouched so the 3.9.36-3.9.39 baseline stays comparable. No behaviour change: no ProMotion key, no debounce, no fixedSize, no layout change. This build measures the physics of the system before any optimisation

## 3.9.39 — diagnostics only: instrumentation for the real streaming markdown path. The splitters, fade blocks and advanceFadeWindow were replaced by the plain-text live renderer in 3.4.0 and are no longer reachable; what runs per update is the rendering policy and, above 4000 characters, PlainMarkdownFallbackView — the view whose layout still carries the .fixedSize that P0 in 3.4.8 removed from LightStreamingRenderer. This build measures the policy cost once per frame, the empty/fallback/light branch share with text size, and splits markdown parse by isStreaming. Fallback is a branch counter, not a layout timer; .fixedSize layout cost is correlated against hitch/freeze, not measured here. No behaviour change

## 3.9.38 — cache: messages and sessions get separate serial write queues (e45aa2b) — one shared queue put a completed turn's cache write behind a session upsert and made testCompletedResponseCachesFinalTurnTpsWithoutTranscriptReload time out at 10 s. Per-scope ordering preserved, both queues stay off the main thread. This build is the verification for that regression

## 3.9.37 — test speed: retry backoff made injectable (HermesRetryBackoff) and zeroed in the two affected test classes, so a simulated connectivity failure no longer costs 15 s of wall clock per case. Production schedule unchanged (1+2+4+8 s); the retry loop still runs all five attempts. Expected Test 640 s to about 520 s

## 3.9.36 — diagnostics only: draft lifecycle probe (setContent/setDraft/clearDraft/resolveSubmission/moveDraft/restoreAbandonedNewChatDraft/hydrate) logging draft key + text length + didStartConversation, so the draft resurrection chain is proven from logs instead of inferred. No behaviour change

## 3.9.36 — diagnostics only: draft lifecycle probe (setContent/setDraft/clearDraft/resolveSubmission/moveDraft/restoreAbandonedNewChatDraft/hydrate) logging draft key + text length + didStartConversation so the draft resurrection chain is proven from logs instead of inferred. No behaviour change: markConversationStarted wiring and .newChat semantics untouched until the runtime logs land

## 3.9.35 — cache: session cache writes run on a serial cache queue off the MainActor and are awaited, so ordering and read-after-write both hold while the UI never blocks on the write; cache-write telemetry split per writer. Attribution correction: the 522/1123 ms phase readings were background time — the main-thread blocker in the logs is transcriptMessages.fullRecompute (up to 1008 ms), recorded as the next step and not touched here

## 3.9.35 — cache: session cache writes moved off the MainActor onto a serial cache queue (ordering guaranteed by construction); cache-write telemetry split per writer. Attribution correction: the 522/1123 ms phase readings were background time — the main-thread blocker in the logs is transcriptMessages.fullRecompute (up to 1008 ms), recorded as the next step and not touched here

## 3.9.35 — cache: session cache writes moved off the MainActor onto a serial cache queue, so ordering is guaranteed by construction; cache-write telemetry split per writer (Cache Write / Cache Write (sessions) / Cache Write (session)). Attribution correction: the 522/1123 ms phase readings were background time — the main-thread blocker in the logs is transcriptMessages.fullRecompute (up to 1008 ms), recorded as the next step and not touched here

## 3.9.34 — telemetry bridge: #920 phase durations (Stream Batch Apply, Transcript Apply, Markdown Parse, Cache Read/Write, Session Open) now aggregate into hermex-logs.jsonl as type=phase events with count/p50/p90/max and context (chars, mutated, messages, rows). No per-interval disk I/O; signposts and the hitch meter unchanged; the watchdog and jank events untouched

## 3.9.34 — telemetry bridge: #920 phase durations (Stream Batch Apply, Transcript Apply, Markdown Parse, Cache Read/Write, Session Open) now aggregate into hermex-logs.jsonl as type=phase events with count/p50/p90/max and context (chars, mutated, messages, rows). No per-interval disk I/O; signposts and the hitch meter unchanged; the watchdog and jank events untouched

## 3.9.34 — instrumentation: upstream #920 signposts (Session Open, Transcript Apply, Markdown Parse, Stream Batch Apply, Cache Read/Write) plus a DEBUG-only frame-hitch meter behind --hitch-meter. Measures only — no optimisation, no behaviour change; the existing watchdog and freeze telemetry stack is untouched

## 3.9.33 — draft: a message sent during a run no longer returns as a draft — the streaming send path clears the durable draft store the same way the standard path does, so re-entering the chat stops restoring text that was already sent; the two paths now share one sequence, pinned by a regression test

## 3.9.32 — goal card: the notice clears itself after three seconds — the card is one line with its own dismissal, a send clears it, and now the timer does too, so a status nobody acts on cannot hold reading space; all three exits share one method so they cannot drift apart

## 3.9.31 — share: the payload no longer depends on the URL arriving — the drain runs on activation and the destination dialog is re-asked when the app returns from the extension, so a share sent while Hermex was backgrounded lands in the chosen chat instead of opening an empty one (measured 02.10 20:54: the payload was reserved while backgrounded, the dialog was requested with the scene inactive and dropped, and the text was retyped by hand); the goal status card is one line with its own dismissal and clears on the next send, instead of holding a third of the transcript with the keyboard up until the chat was reloaded; pipeline: tests and the device build run in parallel and publication sits behind both (needs: [test, build]) so a red suite still cannot release

## 3.9.30 — release 3.9.30

## 3.9.30 — every failed delivery is caught, in one shape: send, steer, queued message, voice note, attachment, scheduled send, approval and clarification each report their failure through `DeliveryTelemetry`, which classifies it (offline, unreachable, timeout, rate limited, quota, server, bad request, unauthorized, decoding, cancelled) with the privacy-safe category the log already uses and whether repeating it could duplicate work — the point being that a message which did not arrive is never silent, whatever the error happens to be called; only a transport that is down reaches the screen; share opens Hermex Plus and not the App Store app (the fork declares its own URL scheme `hermesplus` instead of upstream's `hermes-agent`, which both installed apps claimed — a test pins it, like gate 14 does for the bundle id); Send during a response no longer stops the run — a refused steer queues the message instead of cancelling the agent's work in progress; Reply, Forward, Save and Pin stay available while the agent writes (a pin is screen-local, the rest only read), while Edit, Fork and Regenerate stay disabled; gate 17

## 3.9.22 — share: fallback to a named pasteboard when the app group container is unreachable (sideloaded builds lose the entitlement), with the transport logged; composer: 8pt horizontal margin

## 3.9.21 — composer: widen layout to 8 pt horizontal margin (closer to edges while keeping safe clearance from hardware rounded corners)

## 3.9.20 — composer: attach files through a UIKit document picker (asCopy, multi-select) — the SwiftUI .fileImporter never delivered a picked file, so the picker's Open button did nothing

## 3.9.19 — composer: unified solid card block enclosing the input field and toolbar row, no transparency, mic and scheduled badge in place

## 3.9.18 — composer: the mic and the scheduled-messages badge leave the horizontal scroller and join the fixed part of the row (with Send), so they are always on screen; the scroller keeps the selectors

## 3.9.17 — revert: the composer is back to the 3.9.13 view — my last three changes lost the mic while typing, hid Send on an empty field and pushed the model/workspace row behind a menu. The measured field-height fix and the telemetry stay

## 3.9.16 — composer: adaptive layout — the collapsed row stays the reference, the expanded state becomes two zones inside the same card (full-width field + a compact tools band), so the field gets its width back and the controls stop drifting to the middle

## 3.9.15 — the goal button in the header comes back after re-entering the chat: the state is restored from the server on entry, silently. The goal block itself is left as it was

## 3.9.14 — the composer keeps one row with the keyboard up: focus no longer inserts the selector row (it moved behind the plus menu), so the expanded state matches the collapsed look he liked

## 3.9.13 — the field's container is no longer a flexible frame: it is pinned to the measured text height, so the field stops stretching to its 108pt ceiling and the surface stops reserving 110pt around an empty draft

## 3.9.12 — measurement build: the composer reports its own numbers (field width/laid-out height/clamped, plus surface and row heights) so the next fix targets the real addend instead of a guess

## 3.9.11 — composer field height comes from the laid-out text (layoutManager.usedRect) instead of sizeThatFits, which returned the 96pt ceiling for an empty field — the field stops sitting five lines tall

## 3.9.10 — composer height stops oscillating: re-measure on width change, publish only on a real height change (3.9.9 closed a feedback loop through the transcript inset)

## 3.9.9 — composer height unstuck: the field re-measures when its width changes, so a one-line draft no longer keeps a four-line card (telemetry showed the field pinned at its 96pt ceiling)

## 3.9.8 — composer look restored: the 3.9.7 composer change is reverted, controls and plus menu are back where they were

## 3.9.7 — composer is one line at rest like Telegram: the 44pt control row now waits for content instead of appearing on focus, so the transcript keeps that height until you type

## 3.9.6 — multi-line drafts stay inside the composer card: the ceiling moved onto the text frame and the container admits its padding, so text scrolls inside instead of drawing over the border

## 3.9.5 — composer is shorter at rest: the empty focused card loses ~50pt (field one line, tighter padding, controls row closer), glass look untouched

## 3.9.4 — composer opens as one line and no longer shows the transcript through the field; Copy is back for assistant replies

## 3.9.3 — composer opens as one line and stops showing the transcript through the field; Copy is back for assistant replies

## 3.9.2 — schedule wiring restored (long-press Send works again, counter badge back), opaque header bar, composer growth policy, gates 15-16

## 3.9.1 — the fork signs as com.braintimebox.hermexplus, so it installs beside the App Store Hermex instead of colliding with it; gate 14 pins the identifier so a merge cannot take upstream's side and restore the collision; includes 3.8.2's composer fix (no reading-mode FAB, no state that could hide the composer)

## 3.9.0 — Hermex Plus signs under its own bundle identifier (com.braintimebox.hermesplus), so it installs beside Hermex instead of colliding with it — first install lands as a fresh app and the server password is entered once. Also lands the release-pipeline fixes: the build watch no longer abandons a green build

## 3.8.2 — the composer never disappears — the reading-mode FAB and the state that could hide both it and the composer are gone, so tapping the chat only dismisses the keyboard; the reasoning list is computed once per frame instead of twice, and the typing indicator stops once a response's content is final

## 3.8.1 — attachments are read off the main actor (an iCloud file no longer freezes the composer) and a refused attachment names its reason; the composer offers None to turn reasoning off

## 3.8.0 — the session list self-recovers from any load failure, and the failure is now logged

## 3.7.0 — Upstream 1.6.0 sync

Merged `uzairansaruzi/hermex` upstream `1.6.0` (105 commits since the fork point).
Every conflict block was resolved by measurement, not by preference: our blocks
carry a measured cause in their comments and were kept, their structural
additions were taken, and independent additions were unioned.

### Scroll — the two models now cooperate instead of competing

- `sizeChangeAnchor` is **back**, conditioned on `shouldFollowLatestMessage` and
  `isDisclosureSettling`. It returns `nil` while the reader is parked, so the
  engine can no longer yank the viewport on its own. Our own code had removed
  this anchor because the unconditional form yanked, then compensated by hand
  across 27 commits.
- Their `FollowLatch` is the **only** owner of the viewport. `ChatScrollOwner`
  and `ScrollOwnershipState` are gone, and the comments in `ChatView` say so:
  two owners was the conflict, and a change of owner re-evaluated the whole
  `ChatView` body plus its environment cascade — the shape behind the 3–14 s
  AttributeGraph freezes. Their latch produces far fewer transitions, so the
  container had nothing left to isolate. It is covered by 27 of their tests.
- Kept our ↓ button behaviour. The tap cancels an in-flight deceleration before
  the programmatic scroll, because `ScrollViewProxy.scrollTo` is silently ignored
  while a flick is still coasting — without it the button looks dead until the
  scroll stops. The merge kept the observer and dropped the `post`, so this is a
  restoration, not a new feature.
- `ChatPrependScrollPositionController` is replaced by
  `ChatScrollPositionController`, which is that class plus `Mode.hold`,
  `hasPrependCapture`, `didRevertSwiftUIOffset`, `resyncAfterHold`,
  `contentSizeChangedThisTurn` and `quietReleaseTask`. Position is released
  when content settles rather than after a fixed one-second timer.
- Their `ignoresCoastingGesture` closes a case we never modelled: a send or
  scroll-to-bottom while the transcript is still decelerating.

### Share — one transport, one visible failure path

- The share extension and the app now exchange drafts through the App Group
  container with a reservation, instead of our pasteboard channel plus a
  URL payload. The extension also reports every failure in place
  ("Could not save shared content.", "Shared content saved. Open Hermex
  manually.") and tries four ways of opening the host app.
- Destination **choice is kept**: shared content asks where it should land
  ("New Chat" / "Choose existing…"), and the reservation is released exactly
  once for whichever branch consumes it, cancel included.

### Streaming — cheap live path, complete settled path

- Kept our O(1) live renderer; the settled path takes their
  `MarkdownMathLayoutCache` and selectable headings. Formatting and math still
  appear when the stream settles; the hot path never pays for them.
- Kept our measured per-token fixes: the incremental transcript fast path, the
  reload-amplification guard, the pagination cursor, EXPERIMENT B identity and
  the pan-gesture metrics hook. `TranscriptMessageContent` is gone: it was our
  3.4.8 scroll-isolation container, dead since their latch took the viewport, and
  Swift still type-checked its 40-argument row on every build.
- Took their terminal content fence (it survives `streamEnd`, which our flag did
  not) and `setLiveTokensPerSecondIfChanged` (no write when the value is
  unchanged).

### Chat — features

- Pin, Save, Scheduled Messages, Forward and Reply are preserved. All five are
  expressed through the upstream `ChatMessageActionItem` API so the SwiftUI
  menu and the UIKit context menu stay in step.
- Took `ChatDraftStore`: drafts are keyed per chat **and per server**, flushed
  to disk, and carry quotes, attachments and settings. On-hydration text is
  preserved instead of being overwritten.

### Composer

- Collapsed pill / expanded card behaviour, where a tap on the field expands it
  and presenting a sheet never snaps it shut. Our height cap (96pt) and the
  no-op height-update guard are kept, so the field cannot balloon and typing
  does not relayout the transcript.

### Workspace

- The file tree **opens closed**. Upstream expanded every top-level folder on
  first visit, which on a phone buries the workspace's own entries behind a wall
  of their children. The reader now expands what they need, and that choice is
  remembered per server and workspace.

### Sessions

- Messaging-channel sessions (Telegram, Discord, Slack…) are **listed** again.
  We hid them because the server refused to continue them; upstream #320 removed
  that refusal and routes them through the import step, so the filter was hiding
  rows the app can now open.

### Lines the union dropped

The merge could not be compiled for a day, and that hid every error behind the
first one. Six lines had been lost to a union that took one side of a hunk, and
they only became visible once the file compiled:

- `actions.pendingActionCoordinator = pendingActionCoordinator` in
  `ChatViewModel.init`. `ChatActionsState` holds the coordinator weakly, so the
  approval prompt, the clarification prompt, the session approval bypass and both
  action error messages read `nil`/`false` for the life of the view model.
- the `didSet` that clears `sendErrorIsFromStreamRecovery`, so a later send error
  was wiped by an earlier recovery confirmation;
- `transcriptRevision &+= 1` in `applyReloadedMessages`, so a reload that only
  rewrote a row's contents never re-scanned it;
- a trailing `errorMessage = nil` that swallowed the offline timeout message;
- two call sites still passing two arguments to `onScrollToLatestContent`.

Twenty-four tests failed the moment the build first succeeded. All of them pass.

### Release mechanics

- `VERSION`, the CHANGELOG heading and every `MARKETING_VERSION` now agree.

---

## 3.6.1 — release 3.6.1

## 3.6.0 — Scroll cleanup (dead code removal + stream guard)

### Scroll — removed dead `sizeChangeAnchor`

- `ChatScrollPolicy.sizeChangeAnchor()` was defined (25 lines) but never called. Removed with its documentation block.

### Scroll — removed dead `explicitFollowCommand` parameter

- `resolveOwner(explicitFollowCommand:)` was accepted but never passed `true` by any caller. Removed. The ↓ button is now documented as one-shot in the `resolveOwner` docstring.

### Scroll — streaming follow guard against double-fire

- `onChange(of: streamingScrollTrigger)` now checks `activeStreamID != nil`. Without this, non-streaming events (loadMessages, reloadMessages) that also bump the trigger caused a redundant `scrollTo` alongside `onChange(of: messages.count)`.

### Scroll — stale comments cleaned

- Removed 4 outdated comments referencing `sizeChangeAnchor`, the old "160pt streaming band", and "Telegram-style no auto-glue" — all describe mechanisms that no longer exist in the codebase.

## 3.5.9 — Scroll conflict elimination (↓ button one-shot + streaming follow)

### Scroll — ↓ button is now one-shot (no permanent ownership lock)

- **Problem:** tapping ↓ set `scrollOwnership = .app` permanently. When the user immediately scrolled back up, the ownership lingered `.app` for 1–2 frames (deferred metrics), during which a streaming size change re-glued the viewport to the bottom — the "↓ fights the finger" jump.
- **Fix:** ↓ button no longer sets ownership. It fires a one-shot scroll to the bottom and clears the cooldown. Ownership is determined naturally by `updateScrollMetrics` after the scroll settles: at the bottom → `.app`, scrolled up → `.user`. The send action (`prepareTranscriptForExplicitSend`) still sets `.app` — that's correct for sending.

### Scroll — streaming follow via streamingScrollTrigger (old text problem)

- **Problem:** `streamingScrollTrigger` was generated on every token flush but never consumed (removed in 3.5.8). During streaming, `messages.count` doesn't change (same message, more tokens), so `onChange(of: messages.count)` doesn't fire. Streaming text grew silently below the viewport while the user stared at stale content.
- **Fix:** re-added `onChange(of: streamingScrollTrigger)` with the same `scrollOwner == .app` guard. Streaming content growth now triggers follow-latest. When the user scrolls up (`scrollOwner == .user`), the handler exits early — no fight.

## 3.5.8 — Scroll architecture unification + instant first token

### Performance — first token appears in 16ms (was 200ms)

- **Problem:** `streamingWordRevealCadenceNanoseconds` was 200ms, batching tokens before display. First character delayed by up to 200ms after arrival.
- **Fix:** reduced to 16ms (one frame at 60fps). Tokens appear almost instantly.

### Scroll — unified bottom threshold (3 → 1)

- **Problem:** three separate thresholds (8pt ownership, 80pt UI, 160pt streaming) created confusion and conflicting behavior. User 30pt up was "near bottom" for UI but "reading" for ownership.
- **Fix:** single 80px threshold for all purposes: ownership, UI chrome, and streaming detection. User owns viewport unless within 80px of bottom.

### Scroll — removed sizeChangeAnchor (system glue)

- **Problem:** `.defaultScrollAnchor(.bottom, for: .sizeChanges)` glued viewport to bottom during content growth, fighting user scroll. Any re-measure (image decode, markdown layout) triggered the jump.
- **Fix:** removed `sizeChangeAnchor` entirely. Follow-latest driven explicitly by `onChange(of: messages.count)`. No system glue, no "scroll won't listen" jump.

### Scroll — removed streamingScrollTrigger (redundant follow)

- **Problem:** `streamingScrollTrigger` incremented on every token flush, triggering `scrollToLatestContent` even when `onChange(of: messages.count)` already handled it. Double-follow caused fight during user scroll.
- **Fix:** removed `streamingScrollTrigger` onChange handler. `onChange(of: messages.count)` is the single follow mechanism.

## 3.5.7 — Silent streaming ON by default

---

# Upstream history

Synced from `uzairansaruzi/hermex`. Kept below our release history because
`scripts/release-check.py` requires the top heading to equal `VERSION`.

## [1.6.0] - 2026-09-05
## 3.9.50 — Markdown streaming reverted to LightEngine; X-Hermex-Request-ID; nginx timeouts 300s
- Markdown streaming reverted to LightEngine (Text(verbatim)) due to watchdog p90 regression (35% >50ms on 3.9.49); block pipeline retained for settled content.
- Added X-Hermex-Request-ID UUID header to HermexLogger POST /webhook/hermex-logs for correlation with proxy-1118 logs.
- Nginx proxy timeouts increased to 300s (proxy_read_timeout/connect_timeout) to reduce idle-timeout drops on mobile networks.
- Minor fixes: ServerCatalog refresh, project-snapshot documentation.
