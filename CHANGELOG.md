## 3.5.3 — Silent Streaming: 90% fewer per-token UI updates

### Performance — suppress reasoning/tool observable updates during streaming

- **Problem:** every streaming token triggered ~80 UI update cycles (30-60 tool + 3-5 reasoning + 8-15 token + 1 metering). On long replies, the cascade of AttributeGraph recalculations through equatable row invalidation produced 3-15s main-thread freezes — the dominant freeze family across 84 verified freeze events.
- **Root cause:** `ChatStreamCoordinator.handle()` propagated every `.reasoning`, `.toolStarted`, `.toolCompleted` event to the delegate (ChatViewModel), which mutated `liveReasoningText` and `liveToolCalls` (observable properties). These mutations invalidated `.equatable()` on ALL N transcript rows → full re-evaluation + markdown re-layout on the main thread.
- **Fix:** `ChatStreamCoordinator` gains a `suppressesReasoningAndToolUpdates` flag (default: false). When true, `.reasoning`/`.toolStarted`/`.toolCompleted` events skip the delegate append (no observable state mutation) while `liveActivityManager.update()` still fires — Live Activity / Dynamic Island / status bar remain synchronized. Tool results and reasoning content appear after the response finishes (server-side auto-replace via `applyCompletedStreamSession`).
- **Settings:** new "Silent Streaming" toggle under Chat settings (`chatTranscript.suppressesReasoningAndToolUpdates`, default off). Live propagation via `@AppStorage` → `ChatView.onChange` → `ChatViewModel.setSuppressesReasoningAndToolUpdates` → `ChatStreamCoordinator`.
- **Effect:** per-token UI updates drop from ~80 to ~2-5. Tool progress and reasoning appear once the stream completes. Approval/clarification prompts remain live (user action required). Live Activity shows streaming status throughout.

## 3.5.2 — P0 freeze fix: scrollOwner isolation (eliminate environment cascade)

### Fixed — scroll owner transition (app→user) caused 3-14s AttributeGraph freeze

- **Root cause (verified across 7 stream=false freeze events, all on ChatView):** scrollOwner was a `@State` property in ChatView (3400+ lines). When it changed (app→user), SwiftUI re-evaluated ChatView's entire body AND propagated the change via `.environment(\\.scrollOwner)` to ALL descendants — including ChatTranscriptView with its ForEach over N rows. The environment cascade forced AttributeGraph to recalculate the full view tree, causing 3-14s main-thread blocks. Confirmed by freeze stacks: `AttributeGraph`, `swift_weakDestroy → SwiftUI`, `SwiftUICore`.
- **Fix:** extracted scrollOwner into `ScrollOwnershipState` (@Observable class in ChatScrollPolicy.swift). ChatView stores it as `@State` but passes it directly to ChatTranscriptView as a parameter — NO environment cascade. ChatTranscriptView derives `scrollOwner` and `showsScrollToBottomButton` from the object. Only ChatTranscriptView (not the entire descendant tree) re-evaluates on owner transitions.
- **Effect:** scroll owner transitions no longer trigger environment cascade → no full tree recalculation → no AttributeGraph freeze. Telemetry keys preserved for backward compatibility.

## 3.5.0 — P0 root cause: scroll/chrome props → Environment (layout storm fix)
