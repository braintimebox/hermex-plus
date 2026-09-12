import SwiftUI
import SwiftData
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private enum GitChatAlert: Identifiable {
    case confirmRemote(GitRemoteAction)
    case dirtyCheckout(GitCheckoutTarget)
    case error(String)

    var id: String {
        switch self {
        case .confirmRemote(let action): "remote:\(action.rawValue)"
        case .dirtyCheckout(let target): "checkout:\(target.id)"
        case .error(let message): "error:\(message)"
        }
    }
}

private enum ActiveGitSheet: Identifiable {
    case changes
    case commit

    var id: Self { self }
}

/// What the per-turn diff sheet shows (issue #316): every changed file in the turn,
/// opened at one of them for a recap-card row tap.
private enum TurnDiffPresentation: Identifiable {
    case turnFiles([GitFile], initial: GitFile?)

    var id: String {
        switch self {
        case .turnFiles(let files, let initial):
            return "turn:" + files.map(\.id).joined(separator: "|") + ":" + (initial?.id ?? "")
        }
    }
}

/// Reports the first completed UIKit appearance transition for a SwiftUI destination.
/// `NavigationStack` does not expose push completion directly, while `viewDidAppear`
/// and the transition coordinator remain synchronized with system animation speed.
struct NavigationAppearanceCompletionObserver: UIViewControllerRepresentable {
    let action: @MainActor () -> Void

    func makeUIViewController(context: Context) -> NavigationAppearanceObserverViewController {
        NavigationAppearanceObserverViewController(action: action)
    }

    func updateUIViewController(
        _ uiViewController: NavigationAppearanceObserverViewController,
        context: Context
    ) {
        uiViewController.action = action
    }
}

@MainActor
final class NavigationAppearanceObserverViewController: UIViewController {
    var action: @MainActor () -> Void

    private var isAwaitingTransitionCompletion = false
    private var didReportAppearance = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard !didReportAppearance, let coordinator = transitionCoordinator else { return }
        isAwaitingTransitionCompletion = true
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard let self else { return }
            isAwaitingTransitionCompletion = false
            guard !context.isCancelled else { return }
            reportAppearanceIfNeeded()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isAwaitingTransitionCompletion else { return }
        reportAppearanceIfNeeded()
    }

    private func reportAppearanceIfNeeded() {
        guard !didReportAppearance else { return }
        didReportAppearance = true
        action()
    }
}

private struct ListenPlaybackBar: View {
    let phase: ListenPlaybackPhase
    let displayTime: TimeInterval
    let duration: TimeInterval
    let speed: ListenPlaybackSpeed
    let onTogglePlayPause: () -> Void
    let onStop: () -> Void
    let onScrub: (TimeInterval) -> Void
    let onScrubbingChanged: (Bool) -> Void
    let onSpeedChange: (ListenPlaybackSpeed) -> Void

    private var isReady: Bool {
        phase == .playing || phase == .paused
    }

    private var isPlaying: Bool {
        phase == .playing
    }

    private var boundedDisplayTime: TimeInterval {
        min(max(0, displayTime), max(duration, 0))
    }

    private var sliderUpperBound: TimeInterval {
        max(duration, 0.01)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                playPauseButton

                VStack(alignment: .leading, spacing: 4) {
                    scrubber
                    timeRow
                }
                .frame(maxWidth: .infinity)

                speedMenu
                stopButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()
        }
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var playPauseButton: some View {
        if phase == .loading {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.accentColor)
            }
            .frame(width: 34, height: 34)
            .accessibilityLabel(String(localized: "Preparing audio"))
        } else {
            Button(action: onTogglePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.chatTactile(.icon))
            .disabled(!isReady)
            .accessibilityLabel(isPlaying ? String(localized: "Pause audio") : String(localized: "Play audio"))
        }
    }

    private var scrubber: some View {
        Slider(
            value: Binding(
                get: { boundedDisplayTime },
                set: { onScrub($0) }
            ),
            in: 0...sliderUpperBound,
            onEditingChanged: onScrubbingChanged
        )
        .tint(Color.accentColor)
        .disabled(!isReady || duration <= 0)
        .accessibilityLabel(String(localized: "Playback position"))
    }

    private var timeRow: some View {
        HStack(spacing: 8) {
            Text(AudioDurationFormatter.string(from: boundedDisplayTime))
            Text("/")
            Text(AudioDurationFormatter.string(from: duration))
            Spacer(minLength: 0)
        }
        .font(AppFont.caption2().monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(AudioDurationFormatter.string(from: boundedDisplayTime)) of \(AudioDurationFormatter.string(from: duration))"))
    }

    private var speedMenu: some View {
        Menu {
            ForEach(ListenPlaybackSpeed.allCases) { option in
                Button {
                    onSpeedChange(option)
                } label: {
                    HStack {
                        Text(option.title)
                        if option == speed {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(speed.title)
                .font(AppFont.caption().weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 36, minHeight: 30)
                .padding(.horizontal, 6)
                .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .disabled(!isReady)
        .accessibilityLabel(String(localized: "Playback speed"))
        .accessibilityValue(speed.title)
    }

    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.chatTactile(.icon))
        .accessibilityLabel(String(localized: "Stop audio"))
    }
}

struct ChatView: View {
    // Telemetry: track body computation time across re-evaluations
    private static let bodyTimingLock = NSLock()
    private static var lastBodyTime: CFAbsoluteTime = 0
    private static var bodyReevaluations = 0
    
    private static func bodyTimingStart() -> CFAbsoluteTime {
        CFAbsoluteTimeGetCurrent()
    }
    private let bottomAnchorID = "chat-bottom-anchor"
    private let transcriptSpacing: CGFloat = 8
    private let composerAccessoryVerticalSpacing: CGFloat = 8
    private let activeRunStatusSpacerHeight: CGFloat = 36
    private let approvalBypassStatusSpacerHeight: CGFloat = 38

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppHaptics.isEnabledKey) private var isHapticsEnabled = true
    @AppStorage(AppHaptics.streamingPulseIsEnabledKey) private var isStreamingPulseEnabled = false
    @AppStorage(StreamingSendBehavior.storageKey) private var streamingSendBehaviorRawValue = StreamingSendBehavior.steer.rawValue
    @AppStorage(ResponseCompletionNotifications.isEnabledKey) private var isResponseCompletionNotificationsEnabled = false
    @AppStorage(AgentRunLiveActivityPrivacy.showsResponseExcerptsKey) private var showsLiveActivityResponseExcerpts = false
    @AppStorage(ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey) private var showsThinkingAndToolCards = true
    @AppStorage(ChatTranscriptDisplaySettings.suppressesReasoningAndToolUpdatesKey) private var suppressesReasoningAndToolUpdates = true
    @AppStorage(ChatTranscriptDisplaySettings.foldsSettledTurnsKey) private var foldsSettledTurns = true
    @AppStorage(ChatTranscriptDisplaySettings.rtlChatLayoutEnabledKey) private var rtlChatLayoutEnabled = ChatTranscriptDisplaySettings.rtlChatLayoutDefaultEnabled
    @AppStorage(SectionVisibilitySettings.chatFilesKey) private var showsFilesButton = true
    @AppStorage(SectionVisibilitySettings.chatGitKey) private var showsGitControls = true

    let session: SessionSummary
    let server: URL
    let onAPIError: (Error) -> Void
    let loadsInitialMessages: Bool
    /// When true, the composer auto-starts voice dictation on appear — set by the
    /// "New Chat with Voice" App Intent (#338). Defaults to false for normal opens.
    let autoStartsVoiceInput: Bool
    let draftStore: ChatDraftStore
    /// Store holding the durable app-owned copies of staged attachments.
    let draftAttachmentStore: any ChatDraftAttachmentStoring
    /// True only for the pending-new-chat flow: after the composer configuration
    /// loads, the restored draft's settings snapshot is applied (each value
    /// revalidated against the live server configuration). Existing sessions
    /// load their configuration from the server and never re-apply a snapshot.
    let restoresDraftSettings: Bool
    let onConversationStarted: () -> Void

    @State private var draftMessage = ""
    @State private var draftQuotes: [ComposerQuote] = []
    @State private var draftRevision = 0
    @State private var isScrolledNearBottom = true
    @State private var isReadingOlderTranscript = false
    @State private var showsPendingDecisionOverlay = false
    /// Measured height of the inline clarification card (0 when none). Drives
    /// the collision-avoidance lift for the floating controls so they clear the
    /// actual card, not a fixed maximum (which would over-lift for short cards).
    @State private var clarificationCardHeight: CGFloat = 0
    @State private var isUserInteractingWithScroll = false
    /// Upstream's follow latch: the single owner of who may move the
    /// viewport. Replaces our `ScrollOwnershipState`.
    @State private var followLatch = ChatScrollPolicy.FollowLatch()
    /// Our spacing constants: the transcript reads a block apart, rows inside a
    /// block a little tighter. Passed down rather than read from the view.
    private let transcriptMessageSpacing: CGFloat = 10
    private let transcriptBlockSpacing: CGFloat = 6
    @State private var followScrollGeneration = 0
    /// While true the transcript's bottom size-change anchor and follow-driven
    /// scrolls are suspended so a disclosure toggle grows or shrinks in place.
    @State private var isDisclosureSettling = false
    @State private var disclosureSettleGeneration = 0
    /// Settled turns the user has opened, plus failed or stopped turns, which
    /// start open. Keyed by turn so paging older messages in does not shift them.
    @State private var expandedTurnKeys: Set<String> = []
    /// While set and in the future, auto-follow scrolls snap instead of animating, so
    /// the cache-first → network reconcile re-pins to the bottom without a jump (#289).
    @State private var cacheFirstSnapUntil: Date?
    @State private var forkedSession: SessionSummary?
    @State private var editContext: MessageActionContext?
    @State private var editDraft = ""
    @State private var showEditSheet = false
    @State private var showEditDiscardConfirmation = false
    @State private var regenerateContext: MessageActionContext?
    @State private var showRegenerateDiscardConfirmation = false
    @State private var attachmentPreviewItem: ChatAttachmentPreviewItem?
    @State private var transcriptMediaPreviewItem: TranscriptMediaPreviewItem?
    @State private var transcriptMediaImageItem: TranscriptMediaPreviewItem?
    @State private var attachmentImageItem: ChatAttachmentPreviewItem?
    /// A workspace file a chat link named; presented on the source viewer at its line.
    @State private var openedFileReference: FileReference?
    @State private var pendingProfileSelection: ProfileSummary?
    @State private var forwardMessageContent: (text: String, author: String, sessionTitle: String)?
    @State private var showingForwardPicker = false
    @State private var showingSchedulePicker = false    /// Full-screen reader for a response chosen via "Select Text".
    @State private var selectableResponseText: SelectableResponseText?

    @State private var showingScheduledList = false
    @State private var showingChatSearch = false
    @State private var showShareSheet = false
    @State private var shareText = ""
    @State private var showProfileNewSessionConfirmation = false
    /// Set while the destructive `/clear` confirmation is on screen. Holds the
    /// submitted draft so a confirmed clear consumes it and a cancel leaves it
    /// in the composer (#389).
    @State private var pendingClearConfirmation: PendingClearConfirmation?
    @State private var goalDraft = ""
    @State private var showsGoalSheet = false
    @State private var activeGitSheet: ActiveGitSheet?
    @State private var turnDiffPresentation: TurnDiffPresentation?
    @State private var pinnedMessageIDs: [String] = []
    /// Set to a pinned message's id to scroll the transcript to it; cleared by
    /// `ChatTranscriptView` once the scroll is consumed.
    @State private var pinnedScrollTarget: String?
    @State private var showsPinnedMessagesSheet = false
    @State private var viewModel: ChatViewModel
    @State private var gitAvailabilityViewModel: GitWorkspaceAvailabilityViewModel
    @State private var gitToastState = GitActionToastState()
    @State private var gitAlert: GitChatAlert?
    @State private var composerHeight: CGFloat = 52
    /// Measured height of the collapsed clarification bar, the request's only
    /// layout footprint; the expanded card overlays the transcript instead.
    @State private var clarificationBarHeight: CGFloat = 0
    @State private var composerIsFocused = false
    /// Full-screen reading mode: the composer is HIDDEN by default; a round
    /// compose FAB at the bottom-trailing reveals it on demand (tap → composer
    /// slides up + keyboard). Hidden again on tap-outside, scroll, or after
    /// sending — the chat returns to reading the response full-screen.
    @State private var composerVisible = true
    @State private var didHydrateDraft = false
    /// Whether this chat has already asked the server for its skills on the
    /// transcript's behalf, so a request that failed does not repeat with every
    /// later transcript update.
    @State private var hasRequestedSkillsForTranscriptChips = false
    /// True from the moment hydration finds persisted attachment records until
    /// their restore pass finishes. It gates `syncDraftAttachments` across the
    /// whole window, so the not-yet-rebuilt composer strip can never overwrite
    /// the persisted set.
    @State private var isRestoringDraftAttachments = false
    /// Records hydration found, handed to the restore pass that runs alongside
    /// the transcript load rather than in front of it.
    @State private var draftAttachmentsAwaitingRestore: [ChatDraftAttachment] = []
    /// Restored attachment records whose re-upload failed; they stay in the
    /// draft for a later retry and are unioned into every attachment sync.
    @State private var draftAttachmentsPendingRetry: [ChatDraftAttachment] = []
    @State private var lastSyncedDraftAttachments: [ChatDraftAttachment] = []
    @State private var restoredDraftSettings: ChatDraftSettings?
    @State private var didApplyRestoredDraftSettings = false
    @State private var didCompleteInitialAppearance = false
    @State private var isInitialComposerFocusContentReady = false
    @State private var didApplyInitialComposerFocusPolicy = false
    @State private var shouldRestoreComposerFocusAfterPreview = false
    @State private var responseCompletionNotificationTracker = ResponseCompletionNotificationTracker()
    @State private var responseCompletionBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    @State private var activeStreamStatusRefreshTask: Task<Void, Never>?
    @State private var initialAttachments: [SharedAttachmentImport]
    @State private var didUploadInitialAttachments = false

    init(
        session: SessionSummary,
        server: URL,
        onAPIError: @escaping (Error) -> Void,
        initialDraft: String = "",
        initialQuotes: [ComposerQuote] = [],
        initialAttachments: [SharedAttachmentImport] = [],
        loadsInitialMessages: Bool = true,
        autoStartsVoiceInput: Bool = false,
        draftStore: ChatDraftStore? = nil,
        draftAttachmentStore: (any ChatDraftAttachmentStoring)? = nil,
        restoresDraftSettings: Bool = false,
        onConversationStarted: @escaping () -> Void = {}
    ) {
        self.session = session
        self.server = server
        self.onAPIError = onAPIError
        self.loadsInitialMessages = loadsInitialMessages
        self.autoStartsVoiceInput = autoStartsVoiceInput
        self.draftStore = draftStore ?? .shared
        let resolvedDraftAttachmentStore = draftAttachmentStore ?? ChatDraftAttachmentStore.shared
        self.draftAttachmentStore = resolvedDraftAttachmentStore
        self.restoresDraftSettings = restoresDraftSettings
        self.onConversationStarted = onConversationStarted
        _draftMessage = State(initialValue: initialDraft)
        _draftQuotes = State(initialValue: initialQuotes)
        _initialAttachments = State(initialValue: initialAttachments)
        _viewModel = State(initialValue: ChatViewModel(
            session: session,
            server: server,
            showsLiveActivityResponseExcerpts: UserDefaults.standard.bool(
                forKey: AgentRunLiveActivityPrivacy.showsResponseExcerptsKey
            ),
            draftAttachmentStore: resolvedDraftAttachmentStore
        ))
        _gitAvailabilityViewModel = State(initialValue: GitWorkspaceAvailabilityViewModel(
            session: session,
            server: server
        ))
    }

    // Extracted from `body` so the type-checker doesn't have to solve the whole composer
    // call alongside the rest of the screen in one expression (#316 pushed it over the
    // "unable to type-check in reasonable time" limit).
    private var scheduledMessageCount: Int {
        let sessionID = session.sessionId ?? ""
        guard !sessionID.isEmpty else { return 0 }
        var fetch = FetchDescriptor<PendingScheduledMessage>()
        fetch.predicate = #Predicate { $0.sessionId == sessionID }
        return (try? modelContext.fetchCount(fetch)) ?? 0
    }

    /// Round compose button shown while the composer is hidden (reading mode).
    /// Tap → composer slides up and takes focus (keyboard on demand only).
    /// Style: the SAME Hermex glass circle as the ↓ button (adaptiveGlass) —
    /// one design language, both buttons are "friends" in the bottom-right
    /// column (user: "эти две кнопки подружить и сделать нормальное
    /// оформление в стиле Hermex").
    private var composeFAB: some View {
        Button {
            showComposer()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .adaptiveGlass(
                    .regular,
                    isInteractive: true,
                    fallbackMaterial: .regularMaterial,
                    in: Circle()
                )
                .chatMinimumHitTarget(in: Circle())
        }
        .buttonStyle(.chatTactile(
            .icon,
            shadow: ChatTactileButtonStyle.Shadow(
                color: .black,
                opacity: colorScheme == .dark ? 0.32 : 0.16,
                radius: 8,
                y: 4,
                pressedOpacity: colorScheme == .dark ? 0.18 : 0.08,
                pressedRadius: 3,
                pressedY: 2
            )
        ))
        .accessibilityLabel(String(localized: "Write a message"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 16)
        .padding(.bottom, 20)
    }

    private func showComposer() {
        guard viewModel.errorMessage == nil else { return }
        withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
            composerVisible = true
        }
        requestComposerFocusIfPossible()
    }

    private func hideComposer() {
        withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
            composerVisible = false
        }
        composerIsFocused = false
    }

    /// Composer visibility + keyboard follow the same rule: the input bar is
    /// revealed ONLY by an explicit tap (FAB or the composer field itself while
    /// visible). No auto-focus on chat open — the keyboard must never eat the
    /// screen while the user is simply reading.
    private var messageComposer: some View {
        MessageComposerView(
            draftMessage: persistedDraftBinding,
            quotes: persistedQuotesBinding,
            isFocused: $composerIsFocused,
            isSending: viewModel.isStartingChat || viewModel.isSendingVoiceNote,
            isCompressingSession: viewModel.isCompressingSession,
            isWaitingForStream: viewModel.activeStreamID != nil,
            isCancellingStream: viewModel.isCancellingStream,
            readOnlyMessage: composerReadOnlyMessage,
            errorMessage: viewModel.sendErrorMessage,
            configurationErrorMessage: viewModel.composerConfigurationErrorMessage,
            contextWindowSnapshot: viewModel.contextWindowSnapshot,
            gitViewModel: gitAvailabilityViewModel,
            modelGroups: viewModel.modelCatalogGroups,
            selectedModelID: viewModel.selectedModelID,
            selectedModelProviderID: viewModel.selectedModelProviderID,
            selectedModelTitle: viewModel.selectedModelTitle,
            workspaceRoots: viewModel.workspaceRoots,
            selectedWorkspacePath: viewModel.selectedWorkspacePath,
            workspaceSuggestions: viewModel.workspaceSuggestions,
            workspaceManagementServer: server,
            personalitySuggestions: viewModel.personalitySuggestions,
            skillSuggestions: viewModel.skillSlashSuggestions,
            hasLoadedSkillSuggestions: viewModel.hasLoadedSkillSlashSuggestions,
            agentCommands: viewModel.agentCommands,
            profileOptions: viewModel.profileOptions,
            isSingleProfileMode: viewModel.isSingleProfileMode,
            selectedProfileName: viewModel.selectedProfileName,
            selectedProfileTitle: viewModel.selectedProfileTitle,
            selectedReasoningEffort: viewModel.selectedReasoningEffort,
            supportedReasoningEfforts: viewModel.supportedReasoningEfforts,
            supportsReasoningEffort: viewModel.supportsReasoningEffort,
            showsReasoningControl: viewModel.showsReasoningEffortControl,
            isUpdatingConfiguration: viewModel.isUpdatingComposerConfiguration,
            pendingAttachments: viewModel.pendingAttachments,
            // An in-flight draft restore counts as an upload in progress: until
            // it finishes, the composer does not yet hold the attachments the
            // user expects this message to carry.
            isUploadingAttachment: viewModel.isUploadingAttachment || isRestoringDraftAttachments,
            attachmentUploadCount: viewModel.attachmentUploadCount,
            attachmentUploadGeneration: viewModel.attachmentUploadGeneration,
            isSendingVoiceNote: viewModel.isSendingVoiceNote,
            autoStartsVoiceInput: autoStartsVoiceInput,
            apiClient: viewModel.client,
            sessionID: session.sessionId,
            chipFilePaths: viewModel.fileChipPaths,
            filePathSearch: viewModel.filePathSearch,
            uploadAttachmentErrorMessage: viewModel.uploadAttachmentErrorMessage,
            onSend: {
                Task { await sendDraftMessage() }
            },
            onSendVoiceNote: { data, filename in
                Task { await sendVoiceNote(audioData: data, filename: filename) }
            },
            quotedMessage: viewModel.quotedMessage,
            onDismissQuote: { viewModel.quotedMessage = nil },
            onSchedule: { showingSchedulePicker = true },
            // track the action that happens right before the freeze
            onScheduleTapped: {
                HermexLogger.shared.log(type: "event", screen: "ChatView", message: "schedule button tapped")
            },
            scheduledCount: scheduledMessageCount,
            onOpenScheduledList: { showingScheduledList = true },
            onCollapseComposer: { hideComposer() },
            onCancel: {
                Task { await cancelStream() }
            },
            onSelectModel: { option in
                Task {
                    let didSelect = await viewModel.selectComposerModel(option)
                    if didSelect {
                        let _: Void = ChatHaptics.configurationSelected(isEnabled: isHapticsEnabled)
                    }
                }
            },
            onModelPickerOpen: {
                await viewModel.refreshModelCatalogForPickerOpen()
            },
            onSelectReasoningEffort: { effort in
                Task {
                    let didSelect = await viewModel.selectReasoningEffort(effort)
                    if didSelect {
                        ChatHaptics.configurationSelected(isEnabled: isHapticsEnabled)
                    }
                }
            },
            onLoadWorkspaceSuggestions: { prefix in
                await viewModel.loadWorkspaceSuggestions(prefix: prefix)
            },
            onWorkspaceRegistryChanged: {
                await viewModel.refreshWorkspaceRoots()
            },
            onLoadPersonalitySuggestions: {
                await viewModel.loadPersonalitySuggestions()
            },
            onLoadSkillSuggestions: {
                await viewModel.loadSkillSlashSuggestions()
            },
            onSelectWorkspace: { path in
                let didSelect = await viewModel.selectWorkspacePath(path)
                if didSelect {
                    ChatHaptics.configurationSelected(isEnabled: isHapticsEnabled)
                }
            },
            onSelectProfile: { profile in
                handleProfileSelection(profile)
            },
            onHeightChange: { height in
                // Clamp: banner + field + action bar + voice bar fit well under
                // 260pt. A runaway height (the focus feedback loop) must never
                // inflate the bottom inset again. Only propagate real moves so
                // minor layout chatter can't keep the loop alive.
                let clamped = min(height, 260)
                if abs(composerHeight - clamped) > 4 {
                    composerHeight = clamped
                }
                // Diagnostic for the blank gap between the transcript and the
                // composer. Log the three heights that control the bottom inset,
                // so the next gap report shows whether the inset is inflated by
                // composerHeight/accessories or the content simply isn't anchored.
                HermexLogger.shared.log(
                    type: "event",
                    screen: "ChatView",
                    message: "composer height c=\(Int(height)) inset=\(Int(transcriptBottomInsetHeight)) acc=\(Int(composerAccessorySpacerHeight)) focused=\(composerIsFocused)"
                )
            },
            onPhotoItemSelected: { item in
                Task { await handlePhotoSelection(item) }
            },
            onFileURLsSelected: { urls in
                Task { await handleSelectedFileURLs(urls) }
            },
            onPasteFileProviders: { providers in
                Task { await handlePastedFileProviders(providers) }
            },
            onPasteFileURLs: { urls in
                Task { await handlePastedFileURLs(urls) }
            },
            onPasteImageProviders: { providers in
                Task { await handlePastedImageProviders(providers) }
            },
            onPasteImages: { images in
                Task { await handlePastedImages(images) }
            },
            onRemoveAttachment: { id in
                let removedAttachment = viewModel.pendingAttachments.first(where: { $0.id == id })
                viewModel.removePendingAttachment(id: id)
                // Explicit discard: the record drops out of the draft via the
                // observation sync; delete its now-unreferenced local copy.
                if let file = removedAttachment?.draftFileName {
                    Task { await draftAttachmentStore.delete(named: file) }
                }
            },
            onPreviewAttachment: { attachment in
                presentAttachmentPreview(ChatAttachmentPreviewItem(pending: attachment))
            },
            onDismissUploadAttachmentError: {
                viewModel.setUploadAttachmentError(nil)
            },
            onSelectFileReference: { path in
                viewModel.recordFileChipReference(path)
            },
            onOpenFileReference: { path in
                openedFileReference = FileReference(path: path, line: nil, column: nil)
            },
            onSelectGitBranch: { target in
                Task { await performGitCheckout(target) }
            },
            onCreateGitBranch: { target in
                Task { await performGitCheckout(target) }
            },
            onRefreshGitBranches: {
                Task { await gitAvailabilityViewModel.loadBranches() }
            }
        )
        // The composer flips wholesale with the transcript under the RTL
        // toggle (#259): input, placeholder, and chrome mirror together.
        .environment(\.layoutDirection, chatLayoutDirection)
    }

    private var composerReadOnlyMessage: String? {
        Self.composerReadOnlyMessage(
            for: session,
            isViewingCachedData: viewModel.isViewingCachedData
        )
    }

    static func composerReadOnlyMessage(
        for session: SessionSummary,
        isViewingCachedData: Bool
    ) -> String? {
        if isViewingCachedData {
            return String(localized: "Reconnect to send messages.")
        }
        if session.isSessionReadOnly {
            return String(localized: "Read-only")
        }
        return nil
    }

    /// An image is known to be an image before it is fetched, so it opens in the
    /// full-bleed lightbox. Everything else keeps the preview sheet, which still has to
    /// decide between audio, video, and an unsupported file once the bytes arrive.
    private func presentTranscriptMediaPreview(_ reference: TranscriptMediaReference) {
        presentPreviewRestoringComposerFocusIfNeeded {
            let item = TranscriptMediaPreviewItem(reference: reference)
            if reference.isRasterImageCandidate, !reference.isExtensionlessRemoteMediaCandidate {
                transcriptMediaImageItem = item
            } else {
                transcriptMediaPreviewItem = item
            }
        }
    }

    private func presentAttachmentPreview(_ item: ChatAttachmentPreviewItem) {
        presentPreviewRestoringComposerFocusIfNeeded {
            if item.inferredIsImage {
                attachmentImageItem = item
            } else {
                attachmentPreviewItem = item
            }
        }
    }

    private func transcriptMediaImageLightbox(for item: TranscriptMediaPreviewItem) -> some View {
        TranscriptMediaImageLightbox(
            server: server,
            sessionID: transcriptMediaSessionID,
            item: item,
            onAPIError: onAPIError
        )
    }

    private func transcriptMediaPreviewView(for item: TranscriptMediaPreviewItem) -> some View {
        TranscriptMediaPreviewView(
            server: server,
            sessionID: transcriptMediaSessionID,
            item: item,
            onAPIError: onAPIError
        )
    }

    /// A chat link that names a workspace file opens the source viewer at its line; every
    /// other link keeps the system behaviour. The viewer's own error state covers a path
    /// the server no longer has, so the tap never waits on a fetch.
    private func handleTranscriptLink(_ url: URL) -> OpenURLAction.Result {
        guard let reference = FileReference.parse(url.absoluteString, workspaceRoot: session.workspace) else {
            return .systemAction
        }
        openedFileReference = reference
        return .handled
    }

    private func fileReferenceSheet(for reference: FileReference) -> some View {
        NavigationStack {
            FilePreviewView(
                session: session,
                server: server,
                entry: WorkspaceEntry(name: reference.name, path: reference.path),
                initialLine: reference.line,
                onAPIError: onAPIError
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { openedFileReference = nil }
                }
            }
        }
    }

    private var transcriptMediaSessionID: String? {
        guard let sessionID = session.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionID.isEmpty
        else {
            return nil
        }
        return sessionID
    }

    private var transcriptMediaCacheNamespace: String {
        "\(server.absoluteString)|\(transcriptMediaSessionID ?? "local:\(session.id)")"
    }

    /// Extracted from `body` so the view's single chained expression stays
    /// inside the compiler's type-checking budget.
    @ViewBuilder
    private var approvalOverlay: some View {
        if let approvalPrompt = viewModel.approvalPrompt {
            ApprovalRequestOverlay(
                prompt: approvalPrompt,
                isResponding: viewModel.isRespondingToApproval,
                errorMessage: viewModel.approvalErrorMessage,
                onChoice: { choice in
                    Task {
                        let didRespond = await viewModel.respondToApproval(choice)
                        if didRespond {
                            ChatHaptics.approvalSubmitted(choice, isEnabled: isHapticsEnabled)
                        }
                    }
                },
                onSkipAll: {
                    Task {
                        let didSkip = await viewModel.skipApprovalsForCurrentSession()
                        if didSkip {
                            ChatHaptics.approvalBypassEnabled(isEnabled: isHapticsEnabled)
                        }
                    }
                }
            )
            .zIndex(10)
        }
    }

    /// The chat scaffold. Split from `body` so the confirmation-alert chain
    /// below stays inside the compiler's type-checking budget.
    private var chatContent: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if viewModel.isViewingCachedData {
                    ChatOfflineCacheBanner()
                }

                listenPlaybackBar

                messageContent
                    .environment(\.layoutDirection, chatLayoutDirection)
            }
            .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: viewModel.showsListenPlaybackBar)

            Group {
                if composerVisible {
                    BottomComposerMaterialFade(composerHeight: composerHeight)

                    composerAccessoryStack

                    clarificationInset

                    messageComposer

                    approvalOverlay
                } else if viewModel.clarificationPrompt == nil {
                    composeFAB
                }
            }
            .transition(ChatMotion.bottomOverlayTransition(reduceMotion: reduceMotion))
        }
        .overlay(alignment: .top) {
            GitActionToastOverlay(state: gitToastState)
        }
    }

    private var chatViewContent: some View {
        chatContent
        // The appearance-completion observer lives at the whole-chat level (not
        // inside the composer): with reading mode the composer is hidden, so the
        // observer must fire regardless of composer visibility — it drives the
        // initial message load.
        .background(
            NavigationAppearanceCompletionObserver(action: handleInitialAppearanceCompletion)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("chat-detail:\(viewModel.displayTitle)")
        .task(id: didCompleteInitialAppearance) {
            await handleInitialAppearanceTask()
        }
        .onChange(of: scenePhase) {
                handleScenePhaseChange(scenePhase)
            }
            .onChange(of: viewModel.activeStreamID) {
                handleActiveStreamChange()
            }
            .onChange(of: viewModel.transcriptRelayoutScrollToken) {
                // Open a brief snap window so the cache-first reconcile re-pin (and any
                // message-count auto-follow racing it) lands without an animated jump (#289).
                cacheFirstSnapUntil = Date().addingTimeInterval(0.35)
            }
            .onChange(of: viewModel.clarificationPrompt?.id) { _, newID in
                // When the clarification card disappears the inline view is removed and
                // `onGeometryChange` no longer fires, so its @State would stay stale and
                // keep the controls lifted. Reset it explicitly on dismissal.
                if viewModel.clarificationPrompt == nil {
                    clarificationCardHeight = 0
                }
                // Auto-hide composer when clarification appears to prevent
                // the FAB and clarification card from overlapping in the
                // bottom-right corner.
                if newID != nil, composerVisible {
                    composerVisible = false
                }
            }
            .onChange(of: viewModel.isUploadingAttachment) { _, isUploading in
                if !isUploading {
                    applyInitialComposerFocusPolicyIfNeeded()
                }
            }
            .onChange(of: viewModel.uploadAttachmentErrorMessage) { _, newValue in
                if newValue == nil {
                    applyInitialComposerFocusPolicyIfNeeded()
                }
            }
            .modifier(
                ChatDraftSyncModifier(
                    pendingAttachments: viewModel.pendingAttachments,
                    composerSettings: currentComposerSettings,
                    onAttachmentsChange: syncDraftAttachments,
                    onSettingsChange: syncDraftSettings
                )
            )
            .onChange(of: showsLiveActivityResponseExcerpts) {
                viewModel.setShowsLiveActivityResponseExcerpts(showsLiveActivityResponseExcerpts)
            }
            .onChange(of: suppressesReasoningAndToolUpdates) {
                viewModel.setSuppressesReasoningAndToolUpdates(suppressesReasoningAndToolUpdates)
            }
            .onDisappear {
                flushDraftsBestEffort()
                activeStreamStatusRefreshTask?.cancel()
                activeStreamStatusRefreshTask = nil
                viewModel.suspendStreamForNavigation()
                viewModel.cleanupPollingTasks()
                // Preserve an unsent draft so it isn't lost when leaving the chat;
                // clear the stored one once the message has been sent (draft empty).
                if let sid = session.sessionId {
                    if draftMessage.isEmpty {
                        UserDefaults.standard.removeObject(forKey: "chat.draft.\(sid)")
                    } else {
                        UserDefaults.standard.set(draftMessage, forKey: "chat.draft.\(sid)")
                    }
                }
                // Defer audio teardown off the dismiss animation path — avoids
                // blocking the navigation pop for ~0.5s while AVAudioPlayer /
                // AVSpeechSynthesizer release their resources.
                Task { viewModel.stopListening() }
            }
            .onAppear {
                MainThreadWatchdog.shared.setScreen("ChatView")
                HermexLogger.shared.log(type: "event", screen: "ChatView", message: "chat opened")
                Task {
                    // Avoid a DOUBLE stream reconnect on open: `loadMessages`
                    // (when loadsInitialMessages) already reconnects after the
                    // history load. Only reconnect here when we did NOT go
                    // through loadMessages (e.g. opened from cache). Doing it in
                    // both places re-arms the SSE twice, which shows up as the
                    // repeated "chat opened" + main-thread freeze on open.
                    if !loadsInitialMessages {
                        await viewModel.reconnectStreamIfNeeded(modelContext: modelContext)
                    }

                    if viewModel.activeStreamID != nil {
                        handleActiveStreamChange()
                    }

                    if let lastError = viewModel.lastError {
                        onAPIError(lastError)
                    }
                }
            }
            .onChange(of: viewModel.responseCompletionHapticTrigger) {
                guard viewModel.responseCompletionHapticTrigger > 0 else { return }
                handleResponseCompletionSideEffects()
            }
            .onChange(of: viewModel.streamingHapticPulseTrigger, handleStreamingHapticPulse)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ChatToolbarTitleLabel(
                        title: displayTitle,
                        subtitle: headerSubtitle
                    )
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ChatToolbarActionCluster {
                        if viewModel.hasActivatedGoalCommand {
                            ChatToolbarActionSlot {
                                goalControlMenu
                            }
                        }

                        // Chat search — left of Files, same style.
                        if !viewModel.messages.isEmpty {
                            ChatToolbarActionSlot {
                                Button {
                                    showingChatSearch = true
                                } label: {
                                    Label("Search", systemImage: "magnifyingglass")
                                }
                                .disabled(viewModel.isViewingCachedData)
                                .accessibilityLabel("Search chat")
                            }
                        }

                        // Third action — appears ONLY when the agent is waiting
                        // for a decision (approval or clarification). The
                        // clarification card renders inline at the transcript
                        // bottom and its auto-scroll is suppressed while the
                        // reader is scrolled away, so this button is the
                        // reliable access point: tap to open the prompt.
                        if viewModel.approvalPrompt != nil || viewModel.clarificationPrompt != nil {
                            ChatToolbarActionSlot {
                                Button {
                                    showsPendingDecisionOverlay = true
                                } label: {
                                    Label("Needs your answer", systemImage: "checkmark.circle.badge.questionmark")
                                }
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Needs your answer")
                            }
                        }

                        if showsFilesButton {
                            ChatToolbarActionSlot {
                                NavigationLink {
                                    FileBrowserView(session: session, server: server, onAPIError: onAPIError)
                                } label: {
                                    Label("Files", systemImage: "folder")
                                }
                                .disabled(viewModel.isViewingCachedData)
                                .accessibilityLabel("Files")
                            }
                        }

                        if showsGitControls, gitAvailabilityViewModel.hasRepository {
                            ChatToolbarActionSlot {
                                gitActionsMenu
                            }
                        }
                    }
                }
            }
            .navigationDestination(item: $forkedSession) { session in
                ChatView(session: session, server: server, onAPIError: onAPIError)
            }
            .fullScreenCover(item: $selectableResponseText) { selectableText in
                SelectableResponseTextView(selection: selectableText)
            }
    }

    var body: some View {
        // Telemetry: measure body computation time to detect layout bottlenecks
        let _ = Self.bodyTimingStart()
        chatViewContent
            .sheet(item: $attachmentPreviewItem) { item in
                ChatAttachmentPreviewView(
                    session: session,
                    server: server,
                    item: item,
                    onAPIError: onAPIError
                )
            }
            .onChange(of: attachmentPreviewItem == nil) { _, isDismissed in
                if isDismissed {
                    restoreComposerFocusAfterPreviewIfNeeded()
                }
            }
            .sheet(item: $transcriptMediaPreviewItem, content: transcriptMediaPreviewView)
            .fullScreenCover(item: $attachmentImageItem) { item in
                ChatAttachmentImageLightbox(
                    session: session,
                    server: server,
                    item: item,
                    onAPIError: onAPIError
                )
            }
            .onChange(of: attachmentImageItem == nil) { _, isDismissed in
                if isDismissed {
                    restoreComposerFocusAfterPreviewIfNeeded()
                }
            }
            .fullScreenCover(item: $transcriptMediaImageItem, content: transcriptMediaImageLightbox)
            .onChange(of: transcriptMediaImageItem == nil) { _, isDismissed in
                if isDismissed {
                    restoreComposerFocusAfterPreviewIfNeeded()
                }
            }
            .onChange(of: transcriptMediaPreviewItem == nil) { _, isDismissed in
                if isDismissed {
                    restoreComposerFocusAfterPreviewIfNeeded()
                }
            }
            .sheet(item: $openedFileReference, content: fileReferenceSheet)
            .sheet(item: $activeGitSheet, content: gitSheet)
            .sheet(item: $turnDiffPresentation, content: turnDiffSheet)
            .alert(item: $gitAlert, content: gitAlertPresentation)
            .sheet(isPresented: $showsGoalSheet) {
                GoalSubmissionSheet(
                    goalDraft: $goalDraft,
                    isSubmitting: viewModel.isSubmittingGoal,
                    onSubmit: { submittedGoal in
                        Task { await submitGoalDraft(submittedGoal) }
                    }
                )
            }
            .sheet(isPresented: $showingForwardPicker) {
                ForwardMessageSheet(
                    content: forwardMessageContent,
                    onForward: { text, author, fromTitle, toSessionId in
                        let header = "🔄 Forwarded from «\(fromTitle)» (\(author)):\n\n"
                        draftMessage = header + text
                        Task { await sendDraftMessage() }
                    },
                    client: viewModel.client
                )
            }
            .sheet(isPresented: $showEditSheet) {
                EditMessageSheet(
                    originalText: editContext?.copyText ?? "",
                    editDraft: $editDraft,
                    onSubmit: {
                        if let context = editContext {
                            Task { await submitEdit(context) }
                        }
                    }
                )
            }
            .sheet(isPresented: $showsPinnedMessagesSheet) {
                PinnedMessagesSheet(
                    pinnedIDs: pinnedMessageIDs,
                    messages: viewModel.messages,
                    onSelect: { id in
                        showsPinnedMessagesSheet = false
                        pinnedScrollTarget = id
                    },
                    onUnpin: { id in
                        pinnedMessageIDs.removeAll { $0 == id }
                    }
                )
            }
            .sheet(isPresented: $showingSchedulePicker) {
                ScheduleMessageSheet(
                    draftMessage: draftMessage,
                    chatTitle: displayTitle,
                    client: viewModel.client,
                    onSchedule: { date, text, target in
                        saveScheduledMessage(text: text, at: date, target: target)
                        showingSchedulePicker = false
                    },
                    onCancel: { showingSchedulePicker = false }
                )
            }
            .sheet(isPresented: $showingScheduledList) {
                NavigationStack {
                    ScheduledMessagesView(
                        onSendNow: { msg in
                            await sendScheduledNow(fromChat: msg)
                        }
                    )
                }
            }
            .sheet(isPresented: $showingChatSearch) {
                chatSearchSheet
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(activityItems: [shareText])
            }
            .alert(
                "Discard Later Messages?",
                isPresented: $showEditDiscardConfirmation
            ) {
                Button("Cancel", role: .cancel) {
                    editContext = nil
                    editDraft = ""
                }
                Button("Discard & Edit", role: .destructive) {
                    ChatHaptics.destructiveConfirmationAccepted(isEnabled: isHapticsEnabled)
                    showEditSheet = true
                }
            } message: {
                Text(editDiscardWarningMessage)
            }
            .alert(
                "Discard Later Messages?",
                isPresented: $showRegenerateDiscardConfirmation
            ) {
                Button("Cancel", role: .cancel) {
                    regenerateContext = nil
                }
                Button("Discard & Regenerate", role: .destructive) {
                    if let context = regenerateContext {
                        ChatHaptics.destructiveConfirmationAccepted(isEnabled: isHapticsEnabled)
                        Task { await submitRegenerate(context) }
                    }
                }
            } message: {
                Text(regenerateDiscardWarningMessage)
            }
            .alert(
                "Start New Session?",
                isPresented: $showProfileNewSessionConfirmation
            ) {
                Button("Cancel", role: .cancel) {
                    pendingProfileSelection = nil
                }
                Button("Start New Session") {
                    if let profile = pendingProfileSelection {
                        Task { await switchProfile(profile, startNewSession: true) }
                    }
                }
            } message: {
                Text(profileSwitchWarningMessage)
            }
            .modifier(
                ClearConversationAlertModifier(
                    pending: $pendingClearConfirmation,
                    isHapticsEnabled: isHapticsEnabled,
                    onConfirm: confirmClearConversation
                )
            )
            .alert(
                "Message Action Failed",
                isPresented: Binding(
                    get: { viewModel.messageActionErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.clearMessageActionError()
                        }
                    }
                )
            ) {
                Button("OK") {
                    viewModel.clearMessageActionError()
                }
            } message: {
                Text(viewModel.messageActionErrorMessage ?? "")
            }
        // Off the main body chain, which is at the type-checker's limit.
        .onChange(of: viewModel.latestRunOutcome) {
            handleLatestRunOutcomeChange(viewModel.latestRunOutcome)
        }
        .environment(\.composerChipCatalog, viewModel.composerChipCatalog)
        .environment(\.openURL, OpenURLAction(handler: handleTranscriptLink))
        .environment(\.chatWorkspaceRoot, session.workspace)
        .task(id: transcriptSkillReferenceCount) {
            await loadSkillSuggestionsForTranscriptChipsIfNeeded()
        }
        .task(id: fileChipReferenceScanToken) {
            await viewModel.loadFileChipReferences(draft: draftMessage)
        }
    }

    @ViewBuilder
    private var listenPlaybackBar: some View {
        if viewModel.showsListenPlaybackBar {
            ListenPlaybackBar(
                phase: viewModel.listenPlaybackPhase,
                displayTime: viewModel.listenPlaybackDisplayTime,
                duration: viewModel.listenPlaybackDuration,
                speed: viewModel.listenPlaybackSpeed,
                onTogglePlayPause: {
                    viewModel.toggleListenPlaybackPlayPause()
                },
                onStop: {
                    viewModel.stopListening()
                },
                onScrub: { time in
                    viewModel.scrubListenPlayback(to: time)
                },
                onScrubbingChanged: { isScrubbing in
                    viewModel.setListenPlaybackScrubbing(isScrubbing)
                },
                onSpeedChange: { speed in
                    viewModel.setListenPlaybackSpeed(speed)
                }
            )
            .transition(ChatMotion.disclosureTransition(reduceMotion: reduceMotion))
        }
    }

    private var gitWriteAvailability: GitWriteAvailability {
        GitWriteAvailability(
            isStreaming: viewModel.activeStreamID != nil,
            isViewingCachedData: viewModel.isViewingCachedData
        )
    }

    @ViewBuilder
    private func gitSheet(_ sheet: ActiveGitSheet) -> some View {
        switch sheet {
        case .changes:
            GitWorkspaceView(
                session: session,
                server: server,
                onAPIError: onAPIError,
                onAddToPrompt: addDiffSelectionToDraft
            )
        case .commit:
            GitCommitView(
                session: session,
                server: server,
                writesDisabled: gitWriteAvailability.writesDisabled,
                onAPIError: onAPIError,
                onCommitted: {
                    Task { await gitAvailabilityViewModel.refreshAfterExternalMutation() }
                }
            )
        }
    }

    @ViewBuilder
    private func turnDiffSheet(_ presentation: TurnDiffPresentation) -> some View {
        switch presentation {
        case .turnFiles(let files, let initial):
            GitDiffView(
                session: session,
                server: server,
                files: files,
                initialFile: initial,
                onAPIError: onAPIError,
                onAddToPrompt: addDiffSelectionToDraft
            )
        }
    }

    /// Drops a diff selection from a Git sheet into the composer and closes the sheet.
    private func addDiffSelectionToDraft(_ snippet: String) {
        let separator = draftMessage.isEmpty ? "" : (draftMessage.hasSuffix("\n") ? "\n" : "\n\n")
        persistedDraftBinding.wrappedValue = draftMessage + separator + snippet + "\n"
        activeGitSheet = nil
        turnDiffPresentation = nil
    }

    private var gitActionsMenu: some View {
        GitActionsMenuButton(
            presentation: GitToolbarPresentation(
                hasRepository: gitAvailabilityViewModel.hasRepository,
                isLoading: gitAvailabilityViewModel.isLoading || gitAvailabilityViewModel.isStatusLoading,
                info: gitAvailabilityViewModel.gitInfo,
                status: gitAvailabilityViewModel.status,
                statusFailed: gitAvailabilityViewModel.statusError != nil
            ),
            isEnabled: !viewModel.isViewingCachedData,
            fetchDisabled: gitWriteAvailability.fetchDisabled,
            writesDisabled: gitWriteAvailability.writesDisabled,
            isRunningAction: gitAvailabilityViewModel.isRunningGitAction,
            onTap: {
                HapticButtonHaptics.tap(isEnabled: isHapticsEnabled)
            },
            onChanges: {
                activeGitSheet = .changes
            },
            onStageEdit: {
                activeGitSheet = .commit
            },
            onCommit: {
                Task { await performQuickCommit(push: false) }
            },
            onCommitAndPush: {
                Task { await performQuickCommit(push: true) }
            },
            onFetch: {
                Task { await performGitRemoteAction(.fetch) }
            },
            onPull: {
                gitAlert = .confirmRemote(.pull)
            },
            onPush: {
                gitAlert = .confirmRemote(.push)
            }
        )
    }

    /// Inputs for the inline "Commit & Push" button shown under the latest assistant turn.
    /// Only for git workspaces, when the latest message is an assistant turn (not while a
    /// response streams), and there is something to commit (or a commit is in flight).
    private var inlineCommitContext: ChatInlineCommitContext? {
        guard ChatGitControlsVisibilityPolicy.showsInlineCommitButton(
            showsGitControls: showsGitControls,
            hasRepository: gitAvailabilityViewModel.hasRepository,
            isStreaming: viewModel.activeStreamID != nil,
            latestMessageRole: latestTranscriptMessageRole,
            hasCommittableChanges: gitAvailabilityViewModel.hasCommittableChanges,
            isCommitting: gitAvailabilityViewModel.isCommitting
        ) else { return nil }
        return ChatInlineCommitContext(
            runningPhase: gitAvailabilityViewModel.commitPhase,
            isDisabled: gitWriteAvailability.writesDisabled
        )
    }

    /// Turn-end "File changes" recap card for the latest assistant turn (#316). Only for git
    /// workspaces once the response finishes (status has refreshed) and the latest turn
    /// actually changed files.
    private var turnChangesRecapSummary: TurnFileChangeSummary? {
        guard ChatGitControlsVisibilityPolicy.showsTurnChangesRecap(
            showsGitControls: showsGitControls,
            hasRepository: gitAvailabilityViewModel.hasRepository,
            isStreaming: viewModel.activeStreamID != nil,
            latestMessageRole: latestTranscriptMessageRole
        ) else { return nil }
        let summary = TurnFileChangeAggregator.summarize(
            toolCalls: viewModel.latestTurnToolCalls,
            status: gitAvailabilityViewModel.status
        )
        return summary.hasChanges ? summary : nil
    }

    /// Present the per-turn diff sheet for every changed file the turn has a status match
    /// for. No-op when there is nothing diffable yet (e.g. status still refreshing).
    private func presentTurnDiff(for summary: TurnFileChangeSummary?) {
        let files = summary?.diffFiles ?? []
        guard !files.isEmpty else { return }
        turnDiffPresentation = .turnFiles(files, initial: nil)
    }

    @MainActor
    private func performQuickCommit(push: Bool) async {
        guard !gitAvailabilityViewModel.isCommitting else { return }

        let branch = gitAvailabilityViewModel.currentBranchName
        gitToastState.showProgress(GitActionProgress(
            title: GitCommitPhase.generatingMessage.progressTitle,
            subtitle: branch
        ))

        let outcome = await gitAvailabilityViewModel.quickCommit(push: push) { phase in
            gitToastState.showProgress(GitActionProgress(
                title: phase.progressTitle,
                subtitle: gitAvailabilityViewModel.currentBranchName
            ))
        }

        switch outcome {
        case .success(let result):
            var detailLines: [String] = []
            if let sha = result.shortSHA { detailLines.append(String(localized: "Commit \(sha)")) }
            if result.truncatedMessage { detailLines.append(String(localized: "Diff was large; message may be partial.")) }
            if let pushError = result.pushFailureMessage {
                // The commit landed but the requested push failed — report partial success
                // so the user knows the local commit is safe and only the push needs retrying.
                detailLines.append(String(localized: "Push failed: \(pushError)"))
            }
            gitToastState.showSuccess(GitActionSuccess(
                title: result.pushFailureMessage != nil
                    ? String(localized: "Committed — push failed")
                    : (result.didPush ? String(localized: "Commit & push complete") : String(localized: "Commit complete")),
                subtitle: result.branch,
                detailLines: detailLines
            ))
            ChatHaptics.gitActionFinished(succeeded: result.pushFailureMessage == nil, isEnabled: isHapticsEnabled)
        case .nothingToCommit:
            gitToastState.dismissProgress()
            ChatHaptics.gitActionFinished(succeeded: false, isEnabled: isHapticsEnabled)
            gitAlert = .error(String(localized: "There are no changes to commit."))
        case .tooManyChanges:
            // Status was truncated (>500 files): the commit was blocked to avoid silently
            // dropping files 501+. Always surface a message — falling back to a hardcoded
            // string if the view model ever leaves actionErrorMessage unset — because a
            // blocked commit with no feedback would be the very silent failure this guards
            // against. (Kept separate from .failure, which intentionally stays quiet when its
            // busy/no-session guard returns with no message.) No success toast/SHA.
            gitToastState.dismissProgress()
            ChatHaptics.gitActionFinished(succeeded: false, isEnabled: isHapticsEnabled)
            gitAlert = .error(gitAvailabilityViewModel.actionErrorMessage
                ?? String(localized: "Too many changes to quick-commit. Commit in smaller batches, or use git directly."))
        case .failure:
            gitToastState.dismissProgress()
            ChatHaptics.gitActionFinished(succeeded: false, isEnabled: isHapticsEnabled)
            if let message = gitAvailabilityViewModel.actionErrorMessage {
                gitAlert = .error(message)
            }
        }
    }

    @MainActor
    private func performGitCheckout(_ target: GitCheckoutTarget, stashingChanges: Bool = false) async {
        let outcome = await gitAvailabilityViewModel.checkout(target, stashingChanges: stashingChanges)
        if outcome == .requiresStash {
            gitAlert = .dirtyCheckout(target)
        } else if let message = gitAvailabilityViewModel.actionErrorMessage {
            // Surface real failures and partial successes (branch switched but the
            // stashed changes could not be restored) — the view model sets
            // actionErrorMessage in both cases and clears it on every new checkout.
            gitAlert = .error(message)
        }
    }

    @MainActor
    private func performGitRemoteAction(_ action: GitRemoteAction) async {
        gitToastState.showProgress(GitActionProgress(
            title: action.progressTitle,
            subtitle: gitAvailabilityViewModel.currentBranchName
        ))

        if await gitAvailabilityViewModel.performRemoteAction(action) {
            gitToastState.showSuccess(GitActionSuccess(
                title: action.successTitle,
                subtitle: gitAvailabilityViewModel.currentBranchName,
                detailLines: [gitAvailabilityViewModel.lastActionMessage]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            ))
            ChatHaptics.gitActionFinished(succeeded: true, isEnabled: isHapticsEnabled)
        } else {
            gitToastState.dismissProgress()
            ChatHaptics.gitActionFinished(succeeded: false, isEnabled: isHapticsEnabled)
            if let message = gitAvailabilityViewModel.actionErrorMessage {
                gitAlert = .error(message)
            }
        }
    }

    private func gitAlertPresentation(_ alert: GitChatAlert) -> Alert {
        switch alert {
        case .confirmRemote(let action):
            return Alert(
                title: Text(action == .pull ? "Pull Remote Changes?" : "Push Local Commits?"),
                message: Text(action == .pull
                    ? "Pull uses fast-forward only and will not create a merge commit."
                    : "Push the current branch to its configured upstream remote?"),
                primaryButton: .default(Text(action == .pull ? "Pull" : "Push")) {
                    Task { await performGitRemoteAction(action) }
                },
                secondaryButton: .cancel()
            )
        case .dirtyCheckout(let target):
            return Alert(
                title: Text("Uncommitted Changes"),
                message: Text("This workspace has uncommitted changes. Save them temporarily, switch branches, then restore any saved changes for the destination branch."),
                primaryButton: .default(Text("Stash & Switch")) {
                    Task { await performGitCheckout(target, stashingChanges: true) }
                },
                secondaryButton: .cancel()
            )
        case .error(let message):
            return Alert(
                title: Text("Git Action Failed"),
                message: Text(message),
                dismissButton: .default(Text("OK")) {
                    gitAvailabilityViewModel.clearActionError()
                }
            )
        }
    }

    /// The pending clarification, pinned above the composer. Sits in the same
    /// bottom stack as the composer so it rides the keyboard with it.
    private var clarificationInset: some View {
        ZStack(alignment: .bottom) {
            if let clarificationPrompt = viewModel.clarificationPrompt {
                ClarificationRequestInset(
                    prompt: clarificationPrompt,
                    isResponding: viewModel.isRespondingToClarification,
                    isStopping: viewModel.isCancellingStream,
                    errorMessage: viewModel.clarificationErrorMessage,
                    isHapticsEnabled: isHapticsEnabled,
                    onSubmit: { response in
                        Task {
                            let didRespond = await viewModel.respondToClarification(response)
                            if didRespond {
                                ChatHaptics.clarificationSubmitted(isEnabled: isHapticsEnabled)
                            }
                        }
                    },
                    onStop: {
                        Task { await cancelStream() }
                    },
                    onDismissKeyboard: dismissKeyboard,
                    onFootprintChange: { height in
                        clarificationBarHeight = height
                    }
                )
                .id(clarificationPrompt.id)
                .padding(.horizontal, 16)
                .padding(.bottom, composerHeight + 8)
                .transition(ChatMotion.bottomOverlayTransition(reduceMotion: reduceMotion))
            }
        }
        .zIndex(9)
        .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: viewModel.clarificationPrompt?.id)
    }

    @ViewBuilder
    private var composerAccessoryStack: some View {
        if composerAccessoryVisibleItemCount > 0 {
            VStack(spacing: composerAccessoryVerticalSpacing) {
                if !composerLocalNotices.isEmpty {
                    PinnedLocalNoticeStack(notices: composerLocalNotices)
                        .transition(ChatMotion.bottomOverlayTransition(reduceMotion: reduceMotion))
                }

                if let activeRunStatusPresentation {
                    ChatActiveRunStatusView(presentation: activeRunStatusPresentation)
                        .transition(ChatMotion.bottomOverlayTransition(reduceMotion: reduceMotion))
                }

                if showsApprovalBypassStatus {
                    ApprovalBypassStatusPill()
                        .transition(ChatMotion.bottomOverlayTransition(reduceMotion: reduceMotion))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, composerHeight + 8 + clarificationFootprintHeight)
            .allowsHitTesting(false)
            .zIndex(8)
            .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: composerAccessoryVisibleItemCount)
            .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: activeRunStatusPresentation)
            .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: composerLocalNotices)
            .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: showsApprovalBypassStatus)
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        VStack(spacing: 0) {
            if let latestPinnedID = pinnedMessageIDs.last,
               let pinnedMsg = viewModel.messages.first(where: { $0.id == latestPinnedID }) {
                pinnedBannerRow(
                    id: latestPinnedID,
                    message: pinnedMsg,
                    totalCount: pinnedMessageIDs.count
                )
                .background(.ultraThinMaterial)
                .contentShape(Rectangle())
                .onTapGesture {
                    pinnedScrollTarget = latestPinnedID
                }
                .contextMenu {
                    Button {
                        showsPinnedMessagesSheet = true
                    } label: {
                        Label(String(localized: "View All Pinned"), systemImage: "pin")
                    }
                    Button(role: .destructive) {
                        pinnedMessageIDs.removeAll { $0 == latestPinnedID }
                    } label: {
                        Label(String(localized: "Unpin"), systemImage: "pin.slash")
                    }
                }
            }

            ChatTranscriptView(
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            messages: viewModel.messages,
            pinnedScrollTarget: pinnedScrollTarget,
            onPinnedScrollConsumed: {
                pinnedScrollTarget = nil
            },
            displayedTranscriptMessages: displayedTranscriptMessages,
            compressionReferenceCard: viewModel.compressionReferenceCard,
            reasoningGroups: viewModel.displayedReasoningGroups,
            completedToolCallGroupsForAnchor: { anchorMessageID in
                viewModel.completedToolCallGroupsForAnchor(anchorMessageID)
            },
            liveReasoningText: viewModel.liveReasoningText,
            reasoningAnchorMessageID: viewModel.reasoningAnchorMessageID,
            liveToolCalls: viewModel.liveToolCalls,
            toolCallAnchorMessageID: viewModel.toolCallAnchorMessageID,
            streamingAssistantMessageID: viewModel.streamingAssistantMessageID,
            liveTokensPerSecond: viewModel.liveTokensPerSecond,
            activeStreamRecoveryState: viewModel.activeStreamRecoveryState,
            clarificationPromptID: viewModel.clarificationPrompt?.id,
            clarificationPrompt: viewModel.clarificationPrompt,
            isRespondingToClarification: viewModel.isRespondingToClarification,
            clarificationErrorMessage: viewModel.clarificationErrorMessage,
            cacheFirstReconcileScrollToken: viewModel.cacheFirstReconcileScrollToken,
            hidesRunStatusAccessibility: activeRunStatusPresentation != nil,
            showsThinkingAndToolCards: showsThinkingAndToolCards,
            showsAssistantTypingIndicator: showsAssistantTypingIndicator,
            showsCompressingStatus: viewModel.isCompressingContext,
            workingRowStartedAt: workingRowStartedAt,
            showsScrollToBottomButton: showsScrollToBottomButton,
            shouldFollowLatestMessage: shouldFollowLatestMessage,
            isDisclosureSettling: isDisclosureSettling,
            latestTranscriptMessageRole: latestTranscriptMessageRole,
            isScrolledNearBottom: isScrolledNearBottom,
            activeStreamID: viewModel.activeStreamID,
            streamingScrollTrigger: viewModel.streamingScrollTrigger,
            transcriptRelayoutScrollToken: viewModel.transcriptRelayoutScrollToken,
            bottomAnchorID: bottomAnchorID,
            transcriptSpacing: transcriptSpacing,
            transcriptBottomInsetHeight: transcriptBottomInsetHeight,
            localAttachmentPreviews: viewModel.localAttachmentPreviews,
            listeningMessageID: viewModel.listeningMessageID,
            isViewingCachedData: viewModel.isViewingCachedData,
            hasOlderMessages: viewModel.hasOlderMessages,
            isLoadingOlderMessages: viewModel.isLoadingOlderMessages,
            isRegeneratingMessage: viewModel.isRegeneratingMessage,
            isEditingMessage: viewModel.isEditingMessage,
            isForkingMessage: viewModel.isForkingMessage,
            loadAttachmentImage: { path in
                await viewModel.attachmentImageData(path: path)
            },
            loadAttachmentData: { path in
                await viewModel.attachmentRawData(path: path)
            },
            loadTranscriptMediaImage: { reference in
                await viewModel.transcriptMediaThumbnailData(for: reference)
            },
            loadTranscriptMediaData: { reference in
                await viewModel.transcriptMediaData(for: reference)
            },
            transcriptMediaCacheNamespace: transcriptMediaCacheNamespace,
            actionContext: { message, visibleIndex in
                viewModel.actionContext(for: message, visibleIndex: visibleIndex)
            },
            shouldRenderMessageRow: shouldRenderMessageRow,
            onLoadMessages: {
                await loadMessages()
            },
            onLoadOlderMessages: {
                let start = Date()
                let didAdd = await loadOlderMessages()
                let elapsed = Date().timeIntervalSince(start) * 1000
                if elapsed > 100 {
                    HermexLogger.shared.log(
                        type: "event",
                        screen: "ChatView",
                        message: "loadOlderMessages slow",
                        extras: ["elapsedMs": Int(elapsed), "didAdd": didAdd]
                    )
                }
                return didAdd
            },
            onUpdateScrollMetrics: updateScrollMetrics,
            onFollowEvent: handleFollowEvent,
            onDisclosureToggle: handleDisclosureToggle,
            turnFolds: turnFolds(reasoningGroups: viewModel.displayedReasoningGroups),
            terminalReplyRenderIDs: terminalReplyRenderIDs,
            expandedTurnKeys: expandedTurnKeys,
            onToggleTurnFold: toggleTurnFold,
            onDismissKeyboard: dismissKeyboard,
            onScrollToBottom: scrollToBottom,
            onScrollToLatestTranscriptMessage: { proxy in
                scrollToLatestTranscriptMessage(proxy)
            },
            onScrollToLatestContent: { proxy, animated, source in
                scrollToLatestContent(proxy, animated: animated, source: source ?? "latestContent")
            },
            onPreviewAttachment: { attachment, localData in
                presentAttachmentPreview(
                    ChatAttachmentPreviewItem(message: attachment, localData: localData)
                )
            },
            onPreviewTranscriptMedia: { reference in
                presentTranscriptMediaPreview(reference)
            },
            onAskHermex: addSelectedPassageToDraft,
            onToggleListening: { context in
                viewModel.toggleListening(to: context)
            },
            onSubmitClarification: { response in
                Task {
                    let didRespond = await viewModel.respondToClarification(response)
                    if didRespond {
                        ChatHaptics.clarificationSubmitted(isEnabled: isHapticsEnabled)
                    }
                }
            },
            onClarificationCardHeightChange: { height in
                // Only bounce the @State when the value actually changes, so a
                // steady card doesn't re-invalidate ChatView.body every layout.
                if clarificationCardHeight != height {
                    clarificationCardHeight = height
                }
            },
            onSelectText: { context in
                selectableResponseText = SelectableResponseText(context: context)
            },
            onRegenerate: beginRegenerateResponse,
            onEdit: beginEditMessage,
            onFork: { context in
                Task { await forkFromMessage(context) }
            },
            onCopy: { context in
                UIPasteboard.general.string = context.copyText
                ChatHaptics.copied(isEnabled: isHapticsEnabled)
            },
            onReply: { viewModel.quotedMessage = (
                messageId: $0.messageID,
                author: $0.role == .user ? "You" : "Hermes",
                text: $0.copyText
            ) },
            onForward: {
                forwardMessageContent = (
                    text: $0.copyText,
                    author: $0.role == .user ? "You" : "Hermes",
                    sessionTitle: "Chat"
                )
                showingForwardPicker = true
            },
            onSave: { context in
                saveMessage(context)
            },
            onPin: { context in
                if let index = pinnedMessageIDs.firstIndex(of: context.messageID) {
                    // Unpin = unpin + unsave (dual action).
                    pinnedMessageIDs.remove(at: index)
                    deleteSavedMessage(messageID: context.messageID)
                } else {
                    // Pin = pin + save (dual action).
                    pinnedMessageIDs.append(context.messageID)
                    saveMessage(context)
                }
            },
            isMessagePinned: { messageID in
                pinnedMessageIDs.contains(messageID)
            },
            inlineCommitContext: inlineCommitContext,
            onInlineCommit: {
                Task { await performQuickCommit(push: true) }
            },
            turnChangesSummary: turnChangesRecapSummary,
            onOpenTurnDiff: {
                presentTurnDiff(for: turnChangesRecapSummary)
            },
            onOpenTurnFileDiff: { file in
                turnDiffPresentation = .turnFiles(turnChangesRecapSummary?.diffFiles ?? [file], initial: file)
            }
        )
        .environment(\.isScrolledNearBottom, isScrolledNearBottom)
        .environment(\.isAutoScrollPaused, isAutoFollowScrollPaused)
        // showsScrollToBottomButton is derived inside ChatTranscriptView from the follow latch
        .environment(\.scrollToBottomButtonPadding, scrollToBottomButtonBottomPadding)
        .environment(\.latestTranscriptMessageRole, latestTranscriptMessageRole)
        }
    }

    /// One pinned-message banner row (always the most recently pinned). Tapping
    /// scrolls to it; long-press opens the pinned list or unpins. When more than
    /// one message is pinned a trailing "+N" badge signals the rest.
    private func pinnedBannerRow(id: String, message: ChatMessage, totalCount: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(message.role == "user" ? "You" : "Hermes")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Self.pinnedPreview(for: message.content))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if totalCount > 1 {
                Text("+\(totalCount - 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Collapses a message body to a single-line preview, normalising newlines
    /// and stripping inline Markdown so a long multi-paragraph message doesn't
    /// balloon the banner and a code-fenced / bolded / linked message doesn't
    /// render a dangling `` ``` `` or half-open `**` in the one-line preview.
    static func pinnedPreview(for content: String?) -> String {
        let raw = content ?? ""

        // Collapse whitespace (including newlines) to single spaces first.
        let collapsed = raw
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        // Strip inline Markdown so the preview reads as plain text:
        // fenced code, links, images, bold/italic/strikethrough, headings,
        // blockquotes, and list markers.
        var plain = collapsed
            .replacingOccurrences(of: #"```[^`]*```"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[*_~]{1,3}([^*_~]+)[*_~]{1,3}"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^([-*+]|\d+[.)])\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        plain = plain.trimmingCharacters(in: .whitespacesAndNewlines)

        // A message that is *only* markup (e.g. a lone code fence) strips to
        // empty — fall back to the collapsed raw text so the banner always
        // shows something rather than a blank row.
        if plain.isEmpty {
            plain = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Truncate to ~120 characters on a grapheme-cluster boundary so an
        // emoji or other multi-scalar glyph is never cut in half.
        if plain.count > 120 {
            let endIndex = plain.index(plain.startIndex, offsetBy: 120)
            plain = String(plain[..<endIndex]).trimmingCharacters(in: .whitespaces)
            plain += "…"
        }

        return plain
    }

    /// Changes whenever there is new text that could name a workspace file, or
    /// whenever the answers already given have been thrown away: the transcript
    /// grew, was swapped for the server's copy (which can rewrite a message in
    /// the middle without changing the count or the last id), the workspace
    /// moved, or the draft gained or lost a finished `@…`.
    ///
    /// Everything here is O(1) or bounded by the draft, because it runs on every
    /// transcript update, including each token of a live stream. The scan of the
    /// transcript itself is the view model's, and it skips candidates the server
    /// has already answered for.
    private var fileChipReferenceScanToken: String {
        let draftCandidates = ComposerChipTokenizer.fileReferenceCandidates(in: draftMessage)
        return [
            String(viewModel.messages.count),
            String(viewModel.transcriptRevision),
            String(viewModel.fileChipScopeRevision),
            draftCandidates.joined(separator: " ")
        ].joined(separator: "|")
    }

    /// How many sent messages look like they name a skill.
    ///
    /// It is both the trigger and the task's identity, so a cache-first
    /// transcript that swaps in the server's messages still warms the list when
    /// the count of messages did not change but their text did. Zero once the
    /// list has loaded or this chat has already asked, which is what keeps the
    /// scan off the streaming path.
    private var transcriptSkillReferenceCount: Int {
        guard !hasRequestedSkillsForTranscriptChips, !viewModel.hasLoadedSkillSlashSuggestions else {
            return 0
        }

        return viewModel.messages.reduce(into: 0) { count, message in
            guard message.role == "user",
                  ComposerChipTokenizer.mayContainReference(message.content ?? "")
            else { return }
            count += 1
        }
    }

    /// A sent message draws its skill reference as a chip only for skills the
    /// app has heard of, so a transcript that names one warms the skill list the
    /// way a restored draft does — and a chat that never mentions a skill still
    /// costs no skills request.
    private func loadSkillSuggestionsForTranscriptChipsIfNeeded() async {
        guard transcriptSkillReferenceCount > 0 else { return }

        await viewModel.loadSkillSlashSuggestions()

        // One ask per chat. A skills request that failed must not turn every
        // later transcript update into another one; typing `/` in the composer
        // still retries on the reader's behalf. Set after the wait so a
        // cancelled task leaves the chat free to ask again.
        hasRequestedSkillsForTranscriptChips = true
    }

    /// The chat-canvas layout direction. Driven by the manual Settings → Chat
    /// RTL toggle (#259); applied only to the transcript + composer so the
    /// sidebar, settings, and navigation chrome stay in the default direction.
    private var chatLayoutDirection: LayoutDirection {
        ChatTranscriptDisplaySettings.chatLayoutDirection(rtlEnabled: rtlChatLayoutEnabled)
    }

    private var shouldFollowLatestMessage: Bool {
        followLatch.isFollowing
    }

    /// Automatic follows run only while the latch is on and no disclosure
    /// toggle is mid-animation.
    private var isFollowingLatestContent: Bool {
        shouldFollowLatestMessage && !isDisclosureSettling
    }

    private var showsScrollToBottomButton: Bool {
        !isScrolledNearBottom && (viewModel.activeStreamID == nil || !shouldFollowLatestMessage)
    }

    private var workingRowStartedAt: Date? {
        ChatWorkingRowPolicy.startedAt(
            activeRunStartedAt: viewModel.activeRunStartedAt,
            isCancellingStream: viewModel.isCancellingStream,
            hasPendingClarificationPrompt: viewModel.clarificationPrompt != nil
        )
    }

    private func turnFolds(reasoningGroups: [ReasoningGroup]) -> TranscriptTurnFolds {
        guard foldsSettledTurns else { return .none }

        let activityAnchorIDs: Set<String> = showsThinkingAndToolCards
            ? Set(reasoningGroups.compactMap(\.anchorMessageID))
                .union(viewModel.completedToolCallGroups.compactMap(\.anchorMessageID))
            : []

        return TranscriptTurnFolds.derive(
            transcriptMessages: transcriptMessages,
            messages: viewModel.messages,
            messageOffset: viewModel.messagesOffset,
            activityAnchorIDs: activityAnchorIDs,
            rendersBubble: shouldRenderMessageRow,
            isStreamActive: viewModel.activeStreamID != nil,
            streamingAssistantMessageID: viewModel.streamingAssistantMessageID,
            latestRunOutcome: viewModel.latestRunOutcome
        )
    }

    private func handleLatestRunOutcomeChange(_ outcome: TranscriptTurnRunOutcome?) {
        guard let outcome, outcome.ending != .completed else { return }
        expandedTurnKeys.insert(outcome.turnKey)
    }

    private func toggleTurnFold(_ turnKey: String) {
        handleDisclosureToggle()
        withAnimation(ChatMotion.disclosure(reduceMotion: reduceMotion)) {
            if !expandedTurnKeys.insert(turnKey).inserted {
                expandedTurnKeys.remove(turnKey)
            }
        }
    }

    private var terminalReplyRenderIDs: Set<String> {
        TranscriptMessageMetaPolicy.terminalReplyRenderIDs(
            transcriptMessages: transcriptMessages,
            messages: viewModel.messages,
            messageOffset: viewModel.messagesOffset,
            rendersBubble: shouldRenderMessageRow,
            isStreamActive: viewModel.activeStreamID != nil,
            streamingAssistantMessageID: viewModel.streamingAssistantMessageID
        )
    }

    private var showsAssistantTypingIndicator: Bool {
        ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: viewModel.activeStreamID != nil,
            isCancellingStream: viewModel.isCancellingStream,
            hasStreamingAssistantMessage: viewModel.hasStreamingAssistantMessageContent,
            hasPendingClarificationPrompt: viewModel.clarificationPrompt != nil,
            liveReasoningText: viewModel.liveReasoningText,
            hasLiveToolCalls: !viewModel.liveToolCalls.isEmpty,
            showsThinkingAndToolCards: showsThinkingAndToolCards
        )
    }

    private var isComposerChromeCompact: Bool {
        // Compact chrome is a *reading* mode: the composer's secondary bar (workspace
        // dir + profile + git) appears only on an explicit write action, never as a
        // side effect of scrolling back down or tapping ↓ — that decoupling is what
        // stopped the "composer jumps / folder+profile flash" when the transcript
        // re-anchors.
        isReadingOlderTranscript && !composerIsFocused && !viewModel.messages.isEmpty
    }

    private var transcriptBottomInsetHeight: CGFloat {
        max(96, composerHeight + 44 + composerAccessorySpacerHeight + clarificationFootprintHeight)
    }

    private var scrollToBottomButtonBottomPadding: CGFloat {
        composerHeight + 12 + composerAccessorySpacerHeight + clarificationFootprintHeight
    }

    /// Bar height plus its gap above the composer while a clarification is
    /// pending. Constant across expand and collapse, so the transcript never
    /// moves while the card animates.
    private var clarificationFootprintHeight: CGFloat {
        viewModel.clarificationPrompt == nil ? 0 : clarificationBarHeight + 8
    }

    private var pinnedNoticeSpacerHeight: CGFloat {
        composerLocalNotices.isEmpty ? 0 : CGFloat(composerLocalNotices.count) * 60
    }

    private var composerLocalNotices: [String] {
        var notices = viewModel.pinnedLocalNotices
        if let steeringConfirmationNotice = viewModel.steeringConfirmationNotice {
            notices.append(steeringConfirmationNotice)
        }
        return notices
    }

    private var activeRunStatusPresentation: ChatActiveRunStatusPresentation? {
        ChatActiveRunStatusPolicy.presentation(
            isStartingChat: viewModel.isStartingChat,
            hasActiveStream: viewModel.activeStreamID != nil,
            activeStreamRecoveryState: viewModel.activeStreamRecoveryState,
            isCancellingStream: viewModel.isCancellingStream,
            isScrolledNearBottom: isScrolledNearBottom
        )
    }

    private var showsApprovalBypassStatus: Bool {
        viewModel.isSessionApprovalBypassEnabled && viewModel.approvalPrompt == nil
    }

    private var composerAccessorySpacerHeight: CGFloat {
        var height = pinnedNoticeSpacerHeight
        if activeRunStatusPresentation != nil {
            height += activeRunStatusSpacerHeight
        }
        if showsApprovalBypassStatus {
            height += approvalBypassStatusSpacerHeight
        }

        let visibleItemCount = composerAccessoryVisibleItemCount
        if visibleItemCount > 1 {
            height += CGFloat(visibleItemCount - 1) * composerAccessoryVerticalSpacing
        }
        return height
    }

    private var composerAccessoryVisibleItemCount: Int {
        var count = 0
        if !composerLocalNotices.isEmpty {
            count += 1
        }
        if activeRunStatusPresentation != nil {
            count += 1
        }
        if showsApprovalBypassStatus {
            count += 1
        }
        return count
    }

    private var displayTitle: String {
        viewModel.displayTitle
    }

    private var headerSubtitle: String? {
        ChatToolbarSubtitleResolver.subtitle(
            workspacePath: viewModel.selectedWorkspacePath,
            profileTitle: viewModel.selectedProfileTitle
        )
    }

    private func shouldRenderMessageRow(_ message: ChatMessage) -> Bool {
        if message.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }

        return message.role == "user" && message.attachments?.isEmpty == false
    }

    private var transcriptMessages: [TranscriptMessage] {
        viewModel.displayedTranscriptMessages
    }

    private var displayedTranscriptMessages: [TranscriptMessage] {
        transcriptMessages
    }

    @ViewBuilder
    private var chatSearchSheet: some View {
        NavigationStack {
            ChatSearchSheet(
                messages: viewModel.messages,
                roleForMessage: { role in role == "user" ? "You" : "Hermes" },
                onSelect: { messageID in
                    showingChatSearch = false
                    // Reuse the existing pinned-scroll target: it resolves the
                    // message id → transcript row and scrolls to it.
                    pinnedScrollTarget = messageID
                }
            )
        }
    }

    private var latestTranscriptMessageID: String? {
        transcriptMessages.last?.id
    }

    private var latestTranscriptMessageRole: String? {
        transcriptMessages.last?.message.role
    }

    private func prepareInitialAppearance() {
        viewModel.setShowsLiveActivityResponseExcerpts(showsLiveActivityResponseExcerpts)
        viewModel.setSuppressesReasoningAndToolUpdates(suppressesReasoningAndToolUpdates)
        if loadsInitialMessages {
            viewModel.prepareInitialMessageLoad(modelContext: modelContext)
        }
    }

    private func handleInitialAppearanceTask() async {
        // Let the navigation push animation complete before touching
        // synchronous SwiftData / CacheStore reads.
        await Task.yield()
        await hydrateDraftIfNeeded()
        prepareInitialAppearance()

        guard ChatInitialAppearancePolicy.shouldBeginAsyncWork(
            hasCompletedAppearance: didCompleteInitialAppearance
        ) else {
            return
        }

        async let chatStartup: Void = performInitialAsyncWork()
        async let gitAvailability: Void = loadInitialGitAvailability()
        async let draftAttachments: Void = restoreDraftAttachmentsIfNeeded()
        _ = await (chatStartup, gitAvailability, draftAttachments)
    }

    private func performInitialAsyncWork() async {
        guard !Task.isCancelled else { return }
        let draftSettingsInteractionGeneration = viewModel.composerConfigurationInteractionGeneration

        if loadsInitialMessages {
            await loadMessages(appliesInitialFocus: false)
            guard !Task.isCancelled else { return }
        }
        if initialAttachments.isEmpty {
            isInitialComposerFocusContentReady = true
            applyInitialComposerFocusPolicyIfNeeded()
        }
        await viewModel.loadComposerConfiguration()
        guard !Task.isCancelled else { return }

        await applyRestoredDraftSettingsIfNeeded(
            expectedInteractionGeneration: draftSettingsInteractionGeneration
        )
        guard !Task.isCancelled else { return }

        await viewModel.refreshApprovalBypassState()
        guard !Task.isCancelled else { return }

        await uploadInitialAttachmentsIfNeeded()
        guard !Task.isCancelled else { return }

        isInitialComposerFocusContentReady = true
        applyInitialComposerFocusPolicyIfNeeded()
        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private func loadInitialGitAvailability() async {
        let availabilityViewModel = GitWorkspaceAvailabilityViewModel(session: session, server: server)
        gitAvailabilityViewModel = availabilityViewModel
        await availabilityViewModel.loadIfNeeded()
    }

    private var goalControlMenu: some View {
        GoalControlsMenu(
            currentGoal: viewModel.currentGoal,
            isViewingCachedData: viewModel.isViewingCachedData,
            isActionDisabled: isGoalActionDisabled,
            onSetGoal: {
                showsGoalSheet = true
            },
            onSubmitCommand: { command in
                Task { await submitGoalCommand(command) }
            }
        )
    }

    private var isGoalActionDisabled: Bool {
        viewModel.isViewingCachedData || viewModel.activeStreamID != nil || viewModel.isSubmittingGoal
    }

    private func loadMessages(appliesInitialFocus: Bool = true) async {
        // Load the transcript FIRST, then let it actually lay out before any
        // stream reconnect. Doing both back-to-back forces one async pass that
        // re-lays-out the whole history AND re-arms the SSE at the same time —
        // the overlap is what stalls main-thread on open (the repeated
        // "chat opened" + freeze pattern). One `Task.yield()` gives SwiftUI a
        // frame to paint the loaded history before the reconnect work begins.
        await viewModel.loadMessages(modelContext: modelContext)
        await Task.yield()
        await viewModel.reconnectStreamIfNeeded(modelContext: modelContext)
        if appliesInitialFocus {
            applyInitialComposerFocusPolicyIfNeeded()
        }

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private func loadOlderMessages() async -> Bool {
        handleFollowEvent(.userScrollBegin)
        if !isReadingOlderTranscript {
            withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
                isReadingOlderTranscript = true
            }
        }

        let didLoad = await viewModel.loadOlderMessages(modelContext: modelContext)
        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }

        return didLoad
    }

    private func submitGoalDraft(_ submittedGoal: String) async {
        await submitGoal(submittedGoal, clearsDraftOnSuccess: true)
    }

    private func submitGoalCommand(_ command: String) async {
        await submitGoal(command, clearsDraftOnSuccess: false)
    }

    private func submitGoal(_ args: String, clearsDraftOnSuccess: Bool) async {
        prepareTranscriptForExplicitSend()

        let didSubmit = await viewModel.submitGoal(args: args, modelContext: modelContext)
        if didSubmit, clearsDraftOnSuccess {
            goalDraft = ""
        }

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private func confirmClearConversation(_ pending: PendingClearConfirmation) {
        Task { await clearConversation(pending) }
    }

    private func clearConversation(_ pending: PendingClearConfirmation) async {
        let result = await viewModel.clearConversationFromSlashCommand(modelContext: modelContext)
        handleSlashExecutionResult(
            result,
            parsedCommand: SlashCommandCatalog.command(named: "clear"),
            submittedDraft: pending.draft,
            submittedDraftRevision: pending.draftRevision
        )

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private func sendDraftMessage() async -> Bool {
        let submittedContent = ComposerDraftContent(text: draftMessage, quotes: draftQuotes)
        let submittedDraft = submittedContent.text
        let outboundMessage = ComposerQuoteMessageFormatter.message(
            text: submittedDraft,
            quotes: submittedContent.quotes
        )
        let submittedDraftRevision = draftRevision
        let shouldRestoreFocusAfterSend = composerIsFocused

        if submittedContent.quotes.isEmpty,
           submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
            let parsedCommand = SlashCommandExecutor.parse(submittedDraft)?.command
            // `/clear` wipes the conversation on the server, so it always asks
            // first. The draft stays in the composer until the user confirms.
            // A refusal the app already knows about (cached view, CLI session,
            // live stream) skips the alert and falls through to the normal
            // slash path, which surfaces it.
            if parsedCommand?.handler == .clientSide(.clear), viewModel.clearConversationRefusal == nil {
                pendingClearConfirmation = PendingClearConfirmation(
                    draft: submittedDraft,
                    draftRevision: submittedDraftRevision
                )
                return false
            }
            let result = await SlashCommandExecutor.execute(
                text: submittedDraft,
                viewModel: viewModel,
                modelContext: modelContext
            )
            handleSlashExecutionResult(
                result,
                parsedCommand: parsedCommand,
                submittedDraft: submittedDraft,
                submittedDraftRevision: submittedDraftRevision
            )

            if result != .sendAsMessage {
                if let lastError = viewModel.lastError {
                    onAPIError(lastError)
                }
                return false
            }
        }

        let didStart: Bool
        if viewModel.activeStreamID != nil {
            prepareTranscriptForExplicitSend()
            let result = await viewModel.submitStreamingMessage(
                outboundMessage,
                behavior: StreamingSendBehavior.storedValue(streamingSendBehaviorRawValue)
            )
            handleSlashExecutionResult(
                result,
                parsedCommand: SlashCommandCatalog.command(named: streamingSendBehaviorCommandName),
                submittedDraft: submittedDraft,
                submittedQuotes: submittedContent.quotes,
                submittedDraftRevision: submittedDraftRevision,
                consumesDraft: result.isSuccessfulSubmission
            )
            didStart = result.isSuccessfulSubmission
        } else {
            didStart = await sendStandardMessage(
                submittedContent,
                outboundMessage: outboundMessage,
                submittedDraftRevision: submittedDraftRevision
            )
        }

        if didStart {
            // Streaming path (submitStreamingMessage) never cleared draftMessage —
            // only sendStandardMessage did. When a send lands while a stream is
            // already active the text stayed in the composer after being sent
            // ("shared message kept hanging after send"). Clear it on success,
            // like the standard path; on failure the text is preserved below.
            draftMessage = ""
            ChatHaptics.messageSent(isEnabled: isHapticsEnabled)
            // Composer stays visible after send (always-visible mode).
        }

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
        return didStart
    }

    private func sendVoiceNote(audioData: Data, filename: String) async {
        prepareTranscriptForExplicitSend()

        let didSend = await viewModel.sendVoiceNote(
            audioData: audioData,
            filename: filename,
            modelContext: modelContext
        )

        if didSend {
            onConversationStarted()
            ChatHaptics.messageSent(isEnabled: isHapticsEnabled)
            // Composer stays visible after voice note send (always-visible mode).
        }

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private func sendStandardMessage(
        _ submittedContent: ComposerDraftContent,
        outboundMessage: String,
        submittedDraftRevision: Int
    ) async -> Bool {
        // Attachment-only sends (empty text and quotes) flow through; the view
        // model synthesizes their message text. Clearing the captured composer
        // content below is the correct end state after sending.
        let hasStagedAttachments = !viewModel.pendingAttachments.isEmpty
        guard !outboundMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasStagedAttachments else {
            return false
        }

        prepareTranscriptForExplicitSend()

        // Reconcile against what the composer actually staged, not against the
        // draft's whole record set. A record that is not staged — awaiting a
        // re-upload retry, or not yet reached by an in-flight restore — was
        // never carried by this send, so its durable copy must survive.
        let sendReconciliation = ChatDraftSendReconciliation.outcome(
            draftRecords: lastSyncedDraftAttachments,
            stagedAttachmentIDs: Set(viewModel.pendingAttachments.map(\.id))
        )
        draftStore.setContent(submittedContent, for: draftKey)
        draftMessage = ""
        draftQuotes = []

        let didStart = await viewModel.sendMessage(outboundMessage, modelContext: modelContext)
        if didStart {
            onConversationStarted()
            draftAttachmentsPendingRetry = sendReconciliation.retained
        }
        let resolvedContent = draftStore.resolveSubmission(
            submitted: submittedContent,
            current: ComposerDraftContent(text: draftMessage, quotes: draftQuotes),
            didStart: didStart,
            draftWasEdited: draftRevision != submittedDraftRevision,
            for: draftKey
        )
        draftMessage = resolvedContent.text
        draftQuotes = resolvedContent.quotes
        if didStart {
            // `resolveSubmission` cleared the draft's attachment records; put
            // back the ones the send never carried so they retry on a later
            // open. Deterministic here rather than waiting on the observation
            // sync that the emptied composer strip will also trigger.
            syncDraftAttachments()
        }

        return didStart
    }

    private func handleSlashExecutionResult(
        _ result: SlashCommandExecutionResult,
        parsedCommand: SlashCommand?,
        submittedDraft: String,
        submittedQuotes: [ComposerQuote] = [],
        submittedDraftRevision: Int,
        consumesDraft: Bool = true
    ) {
        switch result {
        case .executed(let message):
            if let message {
                if shouldRenderAsLocalNotice(parsedCommand) {
                    if viewModel.activeStreamID == nil {
                        viewModel.appendLocalNoticeMessage(message)
                    } else {
                        viewModel.pinLocalNoticeMessage(message)
                    }
                } else {
                    viewModel.appendLocalAssistantMessage(message)
                }
            }
            if consumesDraft {
                reconcileConsumedDraft(
                    ComposerDraftContent(text: submittedDraft, quotes: submittedQuotes),
                    submittedDraftRevision: submittedDraftRevision
                )
            }
        case .openedSession(let session):
            forkedSession = session
            if consumesDraft {
                reconcileConsumedDraft(
                    ComposerDraftContent(text: submittedDraft, quotes: submittedQuotes),
                    submittedDraftRevision: submittedDraftRevision
                )
            }
        case .unsupported(let friendlyMessage):
            viewModel.setSendErrorMessage(friendlyMessage)
            if consumesDraft {
                reconcileConsumedDraft(
                    ComposerDraftContent(text: submittedDraft, quotes: submittedQuotes),
                    submittedDraftRevision: submittedDraftRevision
                )
            }
        case .needsSubArg:
            viewModel.setSendErrorMessage(String(localized: "Choose a slash command or continue typing."))
        case .sendAsMessage:
            break
        }
    }

    private func shouldRenderAsLocalNotice(_ command: SlashCommand?) -> Bool {
        command?.handler == .serverSide(.compress) ||
            command?.handler == .serverSide(.queue) ||
            command?.handler == .serverSide(.steer) ||
            command?.handler == .serverSide(.interrupt) ||
            command?.handler == .serverSide(.background)
    }

    private var streamingSendBehaviorCommandName: String {
        switch StreamingSendBehavior.storedValue(streamingSendBehaviorRawValue) {
        case .steer:
            "steer"
        case .interrupt:
            "interrupt"
        case .queue:
            "queue"
        }
    }

    private var draftKey: ChatDraftKey {
        let normalizedSessionID = session.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionID = normalizedSessionID.flatMap { $0.isEmpty ? nil : $0 } ?? session.id
        return .session(
            server: server,
            sessionID: sessionID
        )
    }

    private var persistedDraftBinding: Binding<String> {
        Binding(
            get: { draftMessage },
            set: { newValue in
                draftMessage = newValue
                draftRevision &+= 1
                draftStore.setContent(
                    ComposerDraftContent(text: newValue, quotes: draftQuotes),
                    for: draftKey
                )
            }
        )
    }

    private var persistedQuotesBinding: Binding<[ComposerQuote]> {
        Binding(
            get: { draftQuotes },
            set: { newValue in
                draftQuotes = newValue
                draftRevision &+= 1
                draftStore.setContent(
                    ComposerDraftContent(text: draftMessage, quotes: newValue),
                    for: draftKey
                )
            }
        )
    }

    private func hydrateDraftIfNeeded() async {
        guard !didHydrateDraft else { return }
        let textBeforeHydration = draftMessage
        let quotesBeforeHydration = draftQuotes
        let persistedDraft = await draftStore.draft(for: draftKey)
        guard !Task.isCancelled,
              draftMessage == textBeforeHydration,
              draftQuotes == quotesBeforeHydration
        else { return }

        if textBeforeHydration.isEmpty {
            if let persistedDraft, !persistedDraft.text.isEmpty {
                draftMessage = persistedDraft.text
            }
        } else {
            draftStore.setDraft(textBeforeHydration, for: draftKey)
        }
        if quotesBeforeHydration.isEmpty {
            draftQuotes = persistedDraft?.quotes ?? []
        } else {
            draftStore.setQuotes(quotesBeforeHydration, for: draftKey)
        }
        didHydrateDraft = true

        restoredDraftSettings = persistedDraft?.settings
        lastSyncedDraftAttachments = persistedDraft?.attachments ?? []
        if let persistedDraft, !persistedDraft.attachments.isEmpty {
            // Hold the sync gate now and restore later: re-uploading staged
            // files is network work and must not delay the transcript.
            isRestoringDraftAttachments = true
            draftAttachmentsAwaitingRestore = persistedDraft.attachments
        }
    }

    private func restoreDraftAttachmentsIfNeeded() async {
        let records = draftAttachmentsAwaitingRestore
        guard !records.isEmpty else { return }
        draftAttachmentsAwaitingRestore = []
        await restoreDraftAttachments(records)
    }

    /// Rebuilds the composer's staged attachments from a persisted draft by
    /// re-uploading each record's durable local copy against this session. The
    /// persisted server path is never trusted: uploads live in a per-session
    /// inbox the server deletes with the session, so only the app-owned copy
    /// is a sound restore source. Records whose copy is missing are dropped
    /// (with a notice); records whose re-upload fails stay in the draft and
    /// retry on a later open. The rest of the draft loads either way.
    private func restoreDraftAttachments(_ records: [ChatDraftAttachment]) async {
        var pendingRetry: [ChatDraftAttachment] = []
        var unrecoverableCount = 0
        var wasCancelled = false

        for (offset, record) in records.enumerated() {
            if Task.isCancelled {
                // Leaving the chat mid-restore is not a restore failure. Every
                // record from here on is untried, so carry the whole remainder
                // into the retry set: the sync below is authoritative, and
                // anything missing from it would be dropped from the draft and
                // later swept from disk.
                wasCancelled = true
                pendingRetry.append(contentsOf: records[offset...])
                break
            }
            guard let fileName = record.file else {
                // Tolerate an older or partially corrupt record that predates
                // the durable-staging invariant.
                unrecoverableCount += 1
                continue
            }

            let data: Data
            do {
                data = try await draftAttachmentStore.data(named: fileName)
            } catch {
                // Only a copy that is genuinely gone is dropped. Any other
                // read failure keeps the record so a later open can retry it.
                switch ChatDraftAttachmentReadFailure.classify(error) {
                case .unrecoverable:
                    unrecoverableCount += 1
                case .transient:
                    pendingRetry.append(record)
                }
                continue
            }

            if await viewModel.reuploadDraftAttachment(record, data: data) == nil {
                pendingRetry.append(record)
            }
        }

        isRestoringDraftAttachments = false
        draftAttachmentsPendingRetry = pendingRetry
        // Authoritative sync after restore: persists the restored set plus the
        // retry union, and drops unrecoverable records from the draft.
        syncDraftAttachments()

        // Report only a real restore outcome. A cancelled pass has nothing to
        // say, and its view is going away regardless.
        guard !wasCancelled else { return }
        if !pendingRetry.isEmpty || unrecoverableCount > 0 {
            viewModel.setUploadAttachmentError(
                draftRestoreFailureMessage(retryCount: pendingRetry.count, droppedCount: unrecoverableCount)
            )
        }
    }

    /// Copy uses catalog plural variations rather than a hand-branched
    /// singular/plural, so languages whose plural rules differ from English
    /// still read correctly. The mixed case avoids a two-number sentence.
    private func draftRestoreFailureMessage(retryCount: Int, droppedCount: Int) -> String {
        switch (retryCount > 0, droppedCount > 0) {
        case (true, false):
            return String(localized: "Couldn't restore \(retryCount) saved attachments yet. They're still saved in this draft.")
        case (false, true):
            return String(localized: "\(droppedCount) saved attachments are no longer available and were removed from this draft.")
        default:
            return String(localized: "Some saved attachments couldn't be restored. Check this draft's attachments before sending.")
        }
    }

    /// Mirrors the composer's staged attachments into the persisted draft.
    /// Restored records whose re-upload failed are unioned back in so a
    /// mid-restore or post-restore sync can't silently drop them. Gated during
    /// hydration/restore so an empty or partial composer never overwrites the
    /// persisted set.
    private func syncDraftAttachments() {
        guard didHydrateDraft, !isRestoringDraftAttachments else { return }
        // Only records backed by a durable copy are persisted. Without one the
        // record could never be restored, and keeping it would hold the draft
        // alive just to report the attachment as lost on the next open.
        let pendingRecords = viewModel.pendingAttachments
            .map(ChatDraftAttachment.init(pending:))
            .filter { $0.file != nil }
        let retryRecords = draftAttachmentsPendingRetry.filter { retry in
            !pendingRecords.contains(where: { $0.id == retry.id })
        }
        let records = pendingRecords + retryRecords
        lastSyncedDraftAttachments = records
        draftStore.setAttachments(records, for: draftKey)
    }

    /// Snapshots the effective composer settings into the draft whenever they
    /// change. Only new-chat contexts snapshot: an existing session's
    /// configuration is owned by the server and is never re-applied from a
    /// draft, so persisting it would just store choices at rest that nothing
    /// reads. Snapshotting here is what lets an abandoned new chat carry its
    /// model/workspace/profile/reasoning picks to the next new chat.
    private func syncDraftSettings(_ settings: ChatDraftSettings) {
        guard didHydrateDraft, restoresDraftSettings else { return }
        draftStore.setSettings(settings, for: draftKey)
    }

    /// The composer choices that make up a draft's settings snapshot, as one
    /// Equatable value so a single `onChange` covers all five.
    private var currentComposerSettings: ChatDraftSettings {
        ChatDraftSettings(
            modelID: viewModel.selectedModelID,
            modelProviderID: viewModel.selectedModelProviderID,
            reasoningEffort: viewModel.selectedReasoningEffort,
            profileName: viewModel.selectedProfileName,
            workspacePath: viewModel.selectedWorkspacePath
        )
    }

    /// New-chat only. The view owns the one-shot restore trigger while the
    /// model owns validation, interaction fencing, and profile ordering.
    private func applyRestoredDraftSettingsIfNeeded(
        expectedInteractionGeneration: Int
    ) async {
        guard restoresDraftSettings, !didApplyRestoredDraftSettings else { return }
        didApplyRestoredDraftSettings = true
        guard let settings = restoredDraftSettings, !Task.isCancelled else { return }
        await viewModel.restoreDraftSettings(
            settings,
            expectedInteractionGeneration: expectedInteractionGeneration
        )
    }

    private func reconcileConsumedDraft(
        _ submittedContent: ComposerDraftContent,
        submittedDraftRevision: Int
    ) {
        let resolvedContent = draftStore.resolveConsumedInput(
            submitted: submittedContent,
            current: ComposerDraftContent(text: draftMessage, quotes: draftQuotes),
            draftWasEdited: draftRevision != submittedDraftRevision,
            for: draftKey
        )
        draftMessage = resolvedContent.text
        draftQuotes = resolvedContent.quotes
    }

    private func addSelectedPassageToDraft(_ passage: String) {
        guard !passage.isEmpty else { return }
        persistedQuotesBinding.wrappedValue = draftQuotes + [ComposerQuote(text: passage)]
        requestComposerFocusIfPossible()
    }

    private func flushDraftsBestEffort() {
        Task {
            try? await draftStore.flush()
        }
    }

    private func cancelStream() async {
        let didCancel = await viewModel.cancelActiveStream()
        if didCancel {
            ChatHaptics.streamCancelled(isEnabled: isHapticsEnabled)
        }

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private func forkFromMessage(_ context: MessageActionContext) async {
        let session = await viewModel.forkFromMessage(context, modelContext: modelContext)

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }

        if let session {
            forkedSession = session
        }
    }

    private func handleProfileSelection(_ profile: ProfileSummary) {
        viewModel.markComposerConfigurationInteraction()
        if viewModel.isSelectedProfile(profile) {
            return
        }

        if viewModel.messages.isEmpty {
            Task { await switchProfile(profile, startNewSession: false) }
        } else {
            pendingProfileSelection = profile
            showProfileNewSessionConfirmation = true
        }
    }

    private func switchProfile(_ profile: ProfileSummary, startNewSession: Bool) async {
        let outcome = await viewModel.switchProfile(
            profile,
            startNewSession: startNewSession,
            recordsInteraction: false
        )
        pendingProfileSelection = nil

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }

        if outcome != nil {
            ChatHaptics.configurationSelected(isEnabled: isHapticsEnabled)
        }

        if let session = outcome?.session {
            forkedSession = session
        }
    }

    private func uploadInitialAttachmentsIfNeeded() async {
        guard !didUploadInitialAttachments, !initialAttachments.isEmpty else {
            return
        }

        didUploadInitialAttachments = true
        for attachment in initialAttachments {
            await viewModel.uploadAttachment(
                data: attachment.data,
                filename: attachment.filename,
                previewData: previewData(for: attachment)
            )
        }
    }

    private func previewData(for attachment: SharedAttachmentImport) -> Data? {
        if let typeIdentifier = attachment.typeIdentifier,
           UTType(typeIdentifier)?.conforms(to: .image) == true {
            return attachment.data
        }

        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"]
        let fileExtension = URL(fileURLWithPath: attachment.filename).pathExtension.lowercased()
        return imageExtensions.contains(fileExtension) ? attachment.data : nil
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.setUploadAttachmentError(String(localized: "Could not read the selected photo."))
                return
            }
            let filename = "image_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4)).jpg"
            await viewModel.uploadAttachment(data: data, filename: filename, previewData: data)
        } catch {
            viewModel.setUploadAttachmentError(error.localizedDescription)
        }
    }

    private func handleSelectedFileURLs(_ urls: [URL]) async {
        let fileURLs = urls.filter(\.isFileURL)

        guard !fileURLs.isEmpty else {
            viewModel.setUploadAttachmentError(String(localized: "Select a file to attach it."))
            return
        }

        for url in fileURLs {
            do {
                let file = try loadPastedFile(from: url, suggestedName: nil)
                await viewModel.uploadAttachment(data: file.data, filename: file.filename)
            } catch {
                viewModel.setUploadAttachmentError(error.localizedDescription)
            }
        }
    }

    private func handlePastedFileProviders(_ providers: [NSItemProvider]) async {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard !fileProviders.isEmpty else {
            viewModel.setUploadAttachmentError(String(localized: "Paste a copied file to attach it."))
            return
        }

        for provider in fileProviders {
            do {
                let file = try await loadPastedFile(from: provider)
                await viewModel.uploadAttachment(data: file.data, filename: file.filename)
            } catch {
                viewModel.setUploadAttachmentError(error.localizedDescription)
            }
        }
    }

    private func handlePastedImageProviders(_ providers: [NSItemProvider]) async {
        let imageProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }

        guard !imageProviders.isEmpty else {
            viewModel.setUploadAttachmentError(String(localized: "Paste a copied image to attach it."))
            return
        }

        for provider in imageProviders {
            do {
                let image = try await loadPastedImage(from: provider)
                await viewModel.uploadAttachment(data: image.data, filename: image.filename, previewData: image.data)
            } catch {
                viewModel.setUploadAttachmentError(error.localizedDescription)
            }
        }
    }

    private func handlePastedImages(_ images: [UIImage]) async {
        guard !images.isEmpty else {
            viewModel.setUploadAttachmentError(String(localized: "Paste a copied image to attach it."))
            return
        }

        for image in images {
            guard let data = image.jpegData(compressionQuality: 0.92) ?? image.pngData() else {
                viewModel.setUploadAttachmentError(String(localized: "Could not read the pasted image."))
                continue
            }

            await viewModel.uploadAttachment(data: data, filename: pastedImageFilename(), previewData: data)
        }
    }

    private func loadPastedFile(from provider: NSItemProvider) async throws -> PastedFile {
        let suggestedName = provider.suggestedName

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url = pastedFileURL(from: item) else {
                    continuation.resume(throwing: PastedFileError.unreadableURL)
                    return
                }

                do {
                    let file = try loadPastedFile(from: url, suggestedName: suggestedName)
                    continuation.resume(returning: file)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func handlePastedFileURLs(_ urls: [URL]) async {
        let fileURLs = urls.filter(\.isFileURL)

        guard !fileURLs.isEmpty else {
            viewModel.setUploadAttachmentError(String(localized: "Paste a copied file to attach it."))
            return
        }

        for url in fileURLs {
            do {
                let file = try loadPastedFile(from: url, suggestedName: nil)
                await viewModel.uploadAttachment(data: file.data, filename: file.filename)
            } catch {
                viewModel.setUploadAttachmentError(error.localizedDescription)
            }
        }
    }

    private func loadPastedFile(from url: URL, suggestedName: String?) throws -> PastedFile {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try validateAttachmentSize(for: url)
        let data = try Data(contentsOf: url)
        let filename = url.lastPathComponent.isEmpty
            ? suggestedName ?? "pasted-file"
            : url.lastPathComponent
        return PastedFile(data: data, filename: filename)
    }

    private func validateAttachmentSize(for url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize,
              size > PendingAttachment.maximumUploadBytes
        else {
            return
        }

        let filename = url.lastPathComponent.isEmpty ? String(localized: "Selected file") : url.lastPathComponent
        throw PastedFileError.fileTooLarge(filename: filename)
    }

    private func loadPastedImage(from provider: NSItemProvider) async throws -> PastedFile {
        let suggestedName = provider.suggestedName
        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image)
        } ?? UTType.image.identifier

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data else {
                    continuation.resume(throwing: PastedFileError.unreadableImage)
                    return
                }

                continuation.resume(
                    returning: PastedFile(
                        data: data,
                        filename: pastedImageFilename(suggestedName: suggestedName)
                    )
                )
            }
        }
    }

    private func pastedImageFilename(suggestedName: String? = nil) -> String {
        if let suggestedName,
           !suggestedName.isEmpty,
           !URL(fileURLWithPath: suggestedName).pathExtension.isEmpty {
            return suggestedName
        }

        return "image_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4)).jpg"
    }

    private func pastedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string) ?? URL(fileURLWithPath: string)
        }

        return nil
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase != .active {
            flushDraftsBestEffort()
        }

        switch phase {
        case .background:
            if viewModel.activeStreamID != nil {
                beginResponseCompletionBackgroundTask()
            }
        case .active:
            viewModel.refreshListenPlaybackProgressAfterSceneActivation()
            endResponseCompletionBackgroundTask()
            Task {
                await viewModel.reconnectStreamIfNeeded(modelContext: modelContext)
                await viewModel.refreshApprovalBypassState()

                if let lastError = viewModel.lastError {
                    onAPIError(lastError)
                }
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func handleActiveStreamChange() {
        guard let activeStreamID = viewModel.activeStreamID else {
            activeStreamStatusRefreshTask?.cancel()
            activeStreamStatusRefreshTask = nil

            if responseCompletionNotificationTracker.shouldEndBackgroundTaskOnStreamInactive(
                completionTrigger: viewModel.responseCompletionHapticTrigger
            ) {
                endResponseCompletionBackgroundTask()
            }

            // Stream ended while user was away — reload transcript + approvals
            // so the chat is up-to-date when they return.
            Task {
                await loadMessages()
                await gitAvailabilityViewModel.refreshAfterExternalMutation()
                await viewModel.refreshApprovalBypassState()
            }
            return
        }

        // A new turn starting folds the previous one, even one that opened
        // itself after failing or being stopped.
        if let previousTurnKey = viewModel.latestRunOutcome?.turnKey {
            expandedTurnKeys.remove(previousTurnKey)
        }

        startActiveStreamStatusRefreshTask(streamID: activeStreamID)
    }

    private func startActiveStreamStatusRefreshTask(streamID: String) {
        activeStreamStatusRefreshTask?.cancel()
        activeStreamStatusRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard viewModel.activeStreamID == streamID else { return }

                if viewModel.isActiveStreamConnectionSuspended {
                    continue
                }

                await viewModel.recoverStaleActiveStreamIfNeeded(modelContext: modelContext)

                guard viewModel.activeStreamID == streamID else { return }
            }
        }
    }

    private func handleResponseCompletionSideEffects() {
        if !viewModel.responseCompletionNeedsTranscriptRefresh {
            viewModel.cacheCompletedResponse(modelContext: modelContext)
        }

        guard let completionContext = responseCompletionNotificationTracker.completionContext(
            completionTrigger: viewModel.responseCompletionHapticTrigger,
            sceneIsActive: scenePhase == .active
        ) else {
            return
        }

        ChatHaptics.assistantResponseCompleted(isEnabled: isHapticsEnabled)

        Task { @MainActor in
            defer { endResponseCompletionBackgroundTask() }

            if viewModel.responseCompletionNeedsTranscriptRefresh {
                await loadMessages()
            }

            await ResponseCompletionNotificationService.scheduleResponseCompletedIfAllowed(
                sessionID: session.sessionId,
                preferenceEnabled: isResponseCompletionNotificationsEnabled,
                completedNormally: true,
                sceneIsActive: completionContext.sceneIsActive
            )
        }
    }

    private func beginResponseCompletionBackgroundTask() {
        guard responseCompletionBackgroundTask == .invalid else { return }

        let taskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "Hermes response completion") {
            Task { @MainActor in
                endResponseCompletionBackgroundTask()
                viewModel.suspendStreamForBackground()
            }
        }

        responseCompletionBackgroundTask = taskIdentifier
        if taskIdentifier == .invalid {
            viewModel.suspendStreamForBackground()
        }
    }

    private func endResponseCompletionBackgroundTask() {
        guard responseCompletionBackgroundTask != .invalid else { return }

        UIApplication.shared.endBackgroundTask(responseCompletionBackgroundTask)
        responseCompletionBackgroundTask = .invalid
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // Deliberate jump to the latest content. Snap without animation while a
        // response is streaming so the tap lands immediately instead of racing
        // the short follow animations already chasing incoming tokens.
        ChatHaptics.scrolledToLatest(isEnabled: isHapticsEnabled)
        scrollToLatestContent(
            proxy,
            animated: viewModel.activeStreamID == nil,
            isUserInitiated: true
        )
    }

    private func scrollToLatestTranscriptMessage(
        _ proxy: ScrollViewProxy,
        animated: Bool = true,
        isUserInitiated: Bool = false
    ) {
        guard let latestTranscriptMessageID else { return }

        scheduleFollowScroll(
            proxy,
            targetID: latestTranscriptMessageID,
            anchor: .bottom,
            animated: animated,
            isUserInitiated: isUserInitiated,
            source: "latestMessage"
        )
    }

    private func scrollToLatestContent(
        _ proxy: ScrollViewProxy,
        animated: Bool = true,
        isUserInitiated: Bool = false,
        source: String = "latestContent"
    ) {
        guard !viewModel.messages.isEmpty else { return }

        // Scroll to the LAST MOUNTED message, not the `bottomAnchorID` marker.
        // That marker sits at the true end of the content but inside a LAZY
        // LazyVStack — on a fast scroll-to-bottom it may not be mounted yet, so
        // `scrollTo(bottomAnchorID)` teleports BELOW the real content and shows
        // a black gap (the "↓ flies under the chat / black screen" symptom).
        // A real mounted message never does that; the manual scroll can't reach
        // the gap either, so this matches what the reader can actually see.
        scheduleFollowScroll(
            proxy,
            targetID: latestTranscriptMessageID ?? bottomAnchorID,
            anchor: .bottom,
            animated: animated,
            isUserInitiated: isUserInitiated,
            source: source
        )
    }

    private func scheduleFollowScroll(
        _ proxy: ScrollViewProxy,
        targetID: String,
        anchor: UnitPoint,
        animated: Bool,
        isUserInitiated: Bool,
        source: String = "auto"
    ) {
        // Explicit jumps re-arm the follow latch; automatic follows (streaming
        // tokens, new rows) only run while the latch is already on and no
        // disclosure toggle is settling.
        if isUserInitiated {
            handleFollowEvent(.reset)
        } else if !isFollowingLatestContent {
            return
        }

        followScrollGeneration += 1
        let generation = followScrollGeneration

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled, generation == followScrollGeneration else { return }
            // Re-check at fire time: a drag or a disclosure toggle may have
            // begun during the delay.
            if !isUserInitiated, !isFollowingLatestContent { return }

#if DEBUG
            HermexLogger.shared.log(
                type: "event",
                screen: "ChatView",
                message: "scroll command",
                extras: [
                    "source": source,
                    "targetID": targetID,
                    "anchor": anchor == .bottom ? "bottom" : "top",
                    "generation": generation,
                    "scrollOwner": isFollowingLatestContent ? "app" : "user",
                    "isUserInitiated": isUserInitiated,
                    "animated": animated,
                ]
            )
#endif

            // Snap (no animation) while inside the cache-first reconcile window so the
            // taller server transcript replacing the cached one doesn't animate a jump
            // (#289). Evaluated at fire time so it's robust to onChange ordering.
            let isCacheFirstSnapWindow = cacheFirstSnapUntil.map { Date() < $0 } ?? false
            let isStreaming = viewModel.activeStreamID != nil
            if animated, !isStreaming, !isCacheFirstSnapWindow, !isUserInitiated {
                // Non-streaming *auto*-follow keeps the short curve so it still
                // glides. An explicit ↓ tap is always a snap: animating the tap's
                // ride to the bottom over a large lazy transcript forces a re-layout
                // of the markdown tree, which is what rendered a black screen mid-tap
                // (both mid-stream and, worse, in an idle long chat where nothing was
                // printing). Snap glues instantly and never re-lays-out the tail.
                withAnimation(ChatMotion.scrollToLatest(reduceMotion: reduceMotion)) {
                    proxy.scrollTo(targetID, anchor: anchor)
                }
            } else {
                // Streaming, snap window, or explicit ↓ tap: snap WITHOUT animation.
                // A hard glue to the bottom per flush reads as smooth continuous
                // growth (matches Telegram/chat sites); animating the per-token
                // follow retargets the prior animation every flush and produces
                // visible "jitter".
                proxy.scrollTo(targetID, anchor: anchor)
            }
        }
    }

    private func dismissKeyboard() {
        // Keyboard-only dismissal (two-step close): the composer SURVIVES a
        // keyboard dismiss — it must never collapse from a tap that merely
        // resigned focus (the "нажал в любом месте композера — он тупо
        // сворачивается" bug; a failed paste was the same path killing the
        // field mid-gesture). Collapsing happens only via ⌄ / send / a second
        // outside tap (handleTranscriptTap).
        composerIsFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Transcript tap gesture (outside the composer): toggle keyboard.
    /// Tap with keyboard up → dismiss keyboard. Tap with keyboard down →
    /// show composer + open keyboard. One-tap toggle, no two-step dance.
    private func handleTranscriptTap() {
        if composerIsFocused {
            dismissKeyboard()
        } else if canFocusComposer {
            if !composerVisible {
                withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
                    composerVisible = true
                }
            }
            requestComposerFocusIfPossible()
        }
    }

    private var canFocusComposer: Bool {
        !viewModel.isViewingCachedData
            && !viewModel.isUploadingAttachment
            && viewModel.uploadAttachmentErrorMessage == nil
    }

    private func handleInitialAppearanceCompletion() {
        didCompleteInitialAppearance = true
        applyInitialComposerFocusPolicyIfNeeded()
    }

    private func applyInitialComposerFocusPolicyIfNeeded() {
        // Reading-first mode: NO auto-focus on chat open. The composer is
        // hidden and the keyboard must never pop while the user is reading.
        // Input is revealed only by the FAB tap (see showComposer). The old
        // policy focused empty chats on open, which made the keyboard eat half
        // the screen every time a chat was opened (user: "хочу весь экран для
        // чтения, клавиатура только по требованию").
        guard !didApplyInitialComposerFocusPolicy else { return }
        didApplyInitialComposerFocusPolicy = true
    }

    private func presentPreviewRestoringComposerFocusIfNeeded(_ present: () -> Void) {
        shouldRestoreComposerFocusAfterPreview = composerIsFocused
        if composerIsFocused {
            composerIsFocused = false
        }
        present()
    }

    private func restoreComposerFocusAfterPreviewIfNeeded() {
        guard shouldRestoreComposerFocusAfterPreview else { return }
        shouldRestoreComposerFocusAfterPreview = false
        requestComposerFocusIfPossible()
    }

    private func requestComposerFocusIfPossible() {
        guard canFocusComposer else { return }

        Task { @MainActor in
            await Task.yield()
            guard canFocusComposer else { return }
            composerIsFocused = true
        }
    }

    private func handleFollowEvent(_ event: ChatScrollPolicy.FollowEvent) {
        let resolved = ChatScrollPolicy.resolveFollow(current: followLatch, event: event)
        if resolved != followLatch {
            followLatch = resolved
        }
    }

    /// Suspends follow scrolls and the bottom anchor through a disclosure
    /// animation; the transcript view pins the offset itself. The latch is
    /// untouched, so the next streaming trigger catches up once the toggle has
    /// settled.
    private func handleDisclosureToggle() {
        ChatHaptics.disclosureToggled(isEnabled: isHapticsEnabled)
        suspendBottomAnchorForDisclosure()
    }

    /// One tick per view-model bump; the view model already throttles and skips replay.
    private func handleStreamingHapticPulse() {
        ChatHaptics.streamingPulse(isEnabled: isHapticsEnabled && isStreamingPulseEnabled)
    }

    private func suspendBottomAnchorForDisclosure() {
        disclosureSettleGeneration += 1
        let generation = disclosureSettleGeneration
        isDisclosureSettling = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ChatScrollPolicy.disclosureAnchorSuspension))
            guard generation == disclosureSettleGeneration else { return }
            isDisclosureSettling = false
        }
    }

    private func updateScrollMetrics(_ metrics: ChatScrollMetrics) {
        let isStreaming = viewModel.activeStreamID != nil
        let isNearBottom = ChatScrollPolicy.isNearBottom(
            distanceFromBottom: metrics.distanceFromBottom,
            isStreaming: isStreaming
        )
        let wasNearBottomBeforeReport = isScrolledNearBottom
        // Ownership uses the unified threshold: the reader owns the viewport
        // unless they are within 80pt of the bottom.
        let isAtVeryBottom = metrics.distanceFromBottom
            <= ChatScrollPolicy.bottomThreshold(isStreaming: isStreaming)
        // Only assign when the value actually flips — reassigning an identical
        // Bool still fans a @State write through the whole ChatView body, which
        // is exactly the per-tick re-render churn this method exists to avoid.
        if isScrolledNearBottom != isNearBottom {
            isScrolledNearBottom = isNearBottom
            MainThreadWatchdog.setPerformanceContext(isScrolledNearBottom: isNearBottom)
        }
        if isUserInteractingWithScroll != metrics.isUserInteracting {
            isUserInteractingWithScroll = metrics.isUserInteracting
            MainThreadWatchdog.setPerformanceContext(isUserInteracting: metrics.isUserInteracting)
        }

        // F2 (scroll degradation): while the user is actively dragging/flicking,
        // degrade the per-glyph streaming fade so the frame budget goes to scroll.
        // Solid text stays correct; the fade resumes once the gesture ends.
        if StreamingTextFadeDefaults.isScrollDegraded != metrics.isUserInteracting {
            StreamingTextFadeDefaults.isScrollDegraded = metrics.isUserInteracting
        }

        // The latch decides who may move the viewport. One owner: upstream's
        // `resolveFollow`. Our former `ScrollOwnershipState` is gone, so there
        // is no second mechanism to disagree with it.
        let wasFollowing = followLatch.isFollowing
        handleFollowEvent(.contentScrolled(
            isAtBottom: ChatScrollPolicy.isAtBottom(distanceFromBottom: metrics.distanceFromBottom),
            isUserScrolling: metrics.isUserInteracting,
            movedAwayFromBottom: metrics.movedAwayFromBottom,
            wasNearBottom: wasNearBottomBeforeReport
        ))
        if wasFollowing != followLatch.isFollowing {
            let nowFollowing = followLatch.isFollowing
            MainThreadWatchdog.setPerformanceContext(scrollOwner: nowFollowing ? "app" : "user")
            // Telemetry: prove a yank on-device — latch transitions carry the
            // metrics that caused them. Fires only on a flip.
            let ctx = MainThreadWatchdog.snapshotPerformanceContext()
            HermexLogger.shared.log(
                type: "event",
                screen: "ChatView",
                message: "scroll follow \(wasFollowing ? "app→user" : "user→app")",
                extras: [
                    "distanceFromBottom": Int(metrics.distanceFromBottom),
                    "isStreaming": isStreaming,
                    "isInteracting": metrics.isUserInteracting,
                    "isNearBottom": isNearBottom,
                    "messageCount": ctx.messageCount,
                    "displayedRowCount": ctx.displayedRowCount,
                    "scrollOwner": wasFollowing ? "app" : "user",
                ]
            )
        }

        if !isNearBottom,
           !isReadingOlderTranscript,
           ChatScrollPolicy.shouldEnterReadingOlder(
               distanceFromBottom: metrics.distanceFromBottom
           ) {
            withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
                isReadingOlderTranscript = true
            }
        }
    }

    private var isAutoFollowScrollPaused: Bool {
        !isFollowingLatestContent
    }

    private func prepareTranscriptForExplicitSend() {
        handleFollowEvent(.reset)
        // Explicit send re-pins to the tail: the new message must be visible even
        // if the reader had scrolled up. Mark near-bottom so the `.onChange`
        // channels let the scroll-to-latest run instead of silently suppressing
        // it (ownership alone gates them; this keeps the presentation signals
        // consistent too).
        isScrolledNearBottom = true
        if isReadingOlderTranscript {
            withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
                isReadingOlderTranscript = false
            }
        }
    }

    private func saveMessage(_ context: MessageActionContext) {
        let sessionID = session.sessionId ?? ""
        // Guard against a duplicate: SavedMessage uses a UNIQUE savedKey, and a
        // second insert with the same key is silently dropped by SwiftData. The
        // pin action toggles so it won't double-save, but the standalone Save
        // menu item can run twice on the same message.
        guard findSavedMessage(messageID: context.messageID) == nil else { return }
        let saved = SavedMessage(
            messageId: context.messageID,
            sessionId: sessionID,
            sessionTitle: session.title ?? "Chat",
            content: context.copyText,
            author: context.role == .user ? "You" : "Hermes",
            serverURLString: server.absoluteString
        )
        modelContext.insert(saved)
    }

    private func findSavedMessage(messageID: String) -> SavedMessage? {
        let key = SavedMessage.cacheKey(messageId: messageID, serverURLString: server.absoluteString)
        var descriptor = FetchDescriptor<SavedMessage>(
            predicate: #Predicate { $0.savedKey == key }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func deleteSavedMessage(messageID: String) {
        if let existing = findSavedMessage(messageID: messageID) {
            modelContext.delete(existing)
        }
    }

    private func saveScheduledMessage(text: String, at date: Date, target: ScheduledMessageTarget) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let sessionId: String
        let sessionTitle: String?
        switch target {
        case .currentChat:
            sessionId = session.sessionId ?? ""
            sessionTitle = displayTitle
        case .newChat(let title):
            sessionId = ""
            sessionTitle = title
        case .existing(let pickedID, let pickedTitle):
            sessionId = pickedID
            sessionTitle = pickedTitle
        }

        HermexLogger.shared.log(
            type: "event",
            screen: "ChatView",
            message: "saving scheduled msg session=\(sessionId) target=\(target)"
        )

        let scheduled = PendingScheduledMessage(
            sessionId: sessionId,
            sessionTitle: sessionTitle,
            draftText: text,
            scheduledAt: date,
            serverURLString: server.absoluteString
        )
        modelContext.insert(scheduled)
        // Commit immediately — the Scheduled/Tasks lists fetch on a detached
        // context and only see committed rows; without save() the message
        // appeared there with a multi-second delay (SwiftData autosave).
        try? modelContext.save()
        draftMessage = ""
        // Sync to server for autonomous dispatch. Capture SCALAR values only —
        // a @Model object must not cross into a background task.
        let syncKey = scheduled.scheduleKey
        let syncSessionId = scheduled.sessionId
        let syncSessionTitle = scheduled.sessionTitle
        let syncText = scheduled.draftText
        let syncScheduledAt = scheduled.scheduledAt.timeIntervalSince1970
        let syncServerURL = scheduled.serverURLString
        Task.detached(priority: .background) {
            await syncScheduledMessageToServer(
                scheduleKey: syncKey,
                sessionId: syncSessionId,
                sessionTitle: syncSessionTitle,
                text: syncText,
                scheduledAt: syncScheduledAt,
                serverURLString: syncServerURL
            )
        }
    }

    /// "Send Now" from the scheduled-messages list inside a chat: actually
    /// delivers the message (via this chat's composer when the target is the
    /// current session, otherwise via a direct API call), then removes the
    /// pending row locally and on the server.
    private func sendScheduledNow(fromChat msg: PendingScheduledMessage) async {
        let sessionId = msg.sessionId
        let text = msg.draftText
        let serverURLString = msg.serverURLString
        let scheduleKey = msg.scheduleKey

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let serverURL = URL(string: serverURLString) else { return }

        HermexLogger.shared.log(
            type: "event",
            screen: "ChatView",
            message: "send now from chat session=\(sessionId)"
        )

        let currentSessionId = session.sessionId ?? ""
        var deliveredSessionId: String?
        var didSend = false

        // Target is THIS chat → send through the existing composer machinery.
        if sessionId == currentSessionId {
            draftMessage = text
            // sendDraftMessage returns whether the send actually STARTED. If it
            // silently failed (viewModel guard / no streamID / cache-first) the
            // optimistic row was already rolled back — so we must NOT delete the
            // scheduled row or dismiss the sheet, or the message is lost entirely
            // ("Send Now отправлено но не появилось").
            didSend = await sendDraftMessage()
            if didSend {
                deliveredSessionId = currentSessionId
            }
        } else {
            // Target is another/new chat → send directly via API.
            let apiClient = APIClient(baseURL: serverURL)
            var targetSessionId = sessionId
            if targetSessionId.isEmpty {
                do {
                    let response = try await apiClient.createSession(
                        workspace: nil, model: nil, modelProvider: nil, profile: nil
                    )
                    targetSessionId = response.session?.sessionId ?? ""
                    if !targetSessionId.isEmpty,
                       let title = msg.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !title.isEmpty {
                        _ = try? await apiClient.renameSession(id: targetSessionId, title: title)
                    }
                } catch {
                    onAPIError(error)
                    return
                }
            }
            guard !targetSessionId.isEmpty else { return }
            do {
                _ = try await apiClient.startChat(
                    sessionID: targetSessionId,
                    message: text,
                    workspace: nil,
                    model: nil
                )
                deliveredSessionId = targetSessionId
                didSend = true
            } catch {
                onAPIError(error)
            }
        }

        guard didSend else {
            // The send did not start — keep the scheduled row so the user can
            // retry; do not dismiss the sheet. Losing the row on a failed send
            // is exactly the reported "отправлено но не появилось" bug.
            return
        }

        // Remove the pending row locally and on the server.
        modelContext.delete(msg)
        do {
            try modelContext.save()
        } catch {
            print("[ScheduledMessage] local save after send-now error: \(error.localizedDescription)")
        }
        await deleteScheduledFromServer(scheduleKey: scheduleKey, serverURLString: serverURLString)
        // Dismiss the scheduled-messages sheet so the user sees the delivered
        // message land in the chat — before, the list stayed open and the row
        // never disappeared, which read as "Send Now does nothing".
        showingScheduledList = false

        // The message went to a DIFFERENT session than the one on screen —
        // navigate there so the delivery is visible. Without this the send
        // looked like a no-op ("не увидел что сообщение отправлено в этот чат",
        // "увидел другой чат Untitled после back/forward").
        if let deliveredSessionId,
           !deliveredSessionId.isEmpty,
           deliveredSessionId != currentSessionId {
            forkedSession = SessionSummary(
                sessionId: deliveredSessionId,
                title: msg.sessionTitle ?? "Chat"
            )
        }
    }

    private func deleteScheduledFromServer(scheduleKey: String, serverURLString: String) async {
        await PendingScheduledMessage.deleteFromServer(
            scheduleKey: scheduleKey,
            serverURLString: serverURLString
        )
    }

    private func syncScheduledMessageToServer(
        scheduleKey: String,
        sessionId: String,
        sessionTitle: String?,
        text: String,
        scheduledAt: TimeInterval,
        serverURLString: String
    ) async {
        guard let serverURL = URL(string: serverURLString) else { return }
        let webhookURL = serverURL.appendingPathComponent("webhook/scheduled-messages")
        let body: [String: Any] = [
            "scheduleKey": scheduleKey,
            "sessionId": sessionId,
            "sessionTitle": sessionTitle as Any,
            "text": text,
            "scheduledAt": scheduledAt,
        ]
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("[ScheduledMessage] sync failed: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("[ScheduledMessage] sync error: \(error.localizedDescription)")
        }
    }

    private func beginEditMessage(_ context: MessageActionContext) {
        editDraft = context.copyText
        editContext = context
        let messagesAfter = transcriptMessagesAfter(context)
        if messagesAfter > 0 {
            showEditDiscardConfirmation = true
        } else {
            showEditSheet = true
        }
    }

    private func submitEdit(_ context: MessageActionContext) async {
        editContext = nil
        showEditDiscardConfirmation = false

        let success = await viewModel.editMessage(context, newText: editDraft, modelContext: modelContext)

        if success {
            editDraft = ""
        }

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private func beginRegenerateResponse(_ context: MessageActionContext) {
        regenerateContext = context
        let messagesAfter = transcriptMessagesAfter(context)
        if messagesAfter > 0 {
            showRegenerateDiscardConfirmation = true
        } else {
            Task { await submitRegenerate(context) }
        }
    }

    private func submitRegenerate(_ context: MessageActionContext) async {
        regenerateContext = nil
        showRegenerateDiscardConfirmation = false

        _ = await viewModel.regenerateAssistantResponse(context, modelContext: modelContext)

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private var editDiscardWarningMessage: String {
        guard let context = editContext else { return "" }
        let messagesAfter = transcriptMessagesAfter(context)
        return String(localized: "Editing this message will discard \(messagesAfter) later messages.")
    }

    private var regenerateDiscardWarningMessage: String {
        guard let context = regenerateContext else { return "" }
        let messagesAfter = transcriptMessagesAfter(context)
        return String(localized: "Regenerating this response will discard \(messagesAfter) later messages.")
    }

    private var profileSwitchWarningMessage: String {
        guard let profile = pendingProfileSelection else {
            return String(localized: "Switching profiles starts a separate session so this transcript is not retagged.")
        }

        return String(localized: "Switch to \(profile.displayName) and start a new session. This keeps the current transcript on its original profile.")
    }

    private func transcriptMessagesAfter(_ context: MessageActionContext) -> Int {
        guard let index = transcriptMessages.firstIndex(where: { $0.message.id == context.messageID }) else {
            return 0
        }

        return max(0, transcriptMessages.count - 1 - index)
    }
}

struct ChatToolbarTitleLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if showsSubtitle, let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var showsSubtitle: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    private var accessibilityLabel: String {
        guard let subtitle else { return title }
        return "\(title), \(subtitle)"
    }
}

struct ChatToolbarActionCluster<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 44)
        .modifier(LegacyToolbarClusterStyle())
        .accessibilityElement(children: .contain)
    }
}

/// On iOS 26+ the navigation toolbar already renders this trailing item inside a
/// Liquid Glass pill, so styling the cluster ourselves stacked a second capsule
/// and produced the double border reported in #333. Below iOS 26 the system
/// supplies no pill, so we keep the original material capsule there.
private struct LegacyToolbarClusterStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content
                .background(
                    Color(.secondarySystemBackground).opacity(colorScheme == .dark ? 0.24 : 0.42),
                    in: Capsule()
                )
                .adaptiveGlass(
                    .regular,
                    isInteractive: false,
                    fallbackMaterial: .ultraThinMaterial,
                    in: Capsule()
                )
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color(.separator).opacity(colorScheme == .dark ? 0.38 : 0.24), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }
}

struct ChatToolbarActionSlot<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .labelStyle(.iconOnly)
            .font(.body)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

enum ChatToolbarSubtitleResolver {
    static func subtitle(workspacePath: String?, profileTitle: String?) -> String? {
        if let workspace = nonEmpty(workspacePath) {
            return workspace.lastPathComponentFallback
        }

        guard let profile = nonEmpty(profileTitle), profile != "Profile" else {
            return nil
        }

        return profile
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The draft that raised the destructive `/clear` confirmation, so confirming
/// consumes exactly the text that was sent and cancelling leaves it alone.
private struct PendingClearConfirmation: Equatable {
    let draft: String
    let draftRevision: Int
}

/// The `/clear` confirmation, in its own modifier so `ChatView.body`'s alert
/// chain stays inside the compiler's type-checking budget.
private struct ClearConversationAlertModifier: ViewModifier {
    @Binding var pending: PendingClearConfirmation?
    let isHapticsEnabled: Bool
    let onConfirm: (PendingClearConfirmation) -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Clear Conversation?",
            isPresented: Binding(
                get: { pending != nil },
                set: { isPresented in
                    if !isPresented {
                        pending = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pending = nil
            }
            Button("Clear", role: .destructive) {
                guard let confirmed = pending else { return }
                ChatHaptics.destructiveConfirmationAccepted(isEnabled: isHapticsEnabled)
                pending = nil
                onConfirm(confirmed)
            }
        } message: {
            Text("This deletes every message in this conversation on the server. It cannot be undone.")
        }
    }
}

private struct PastedFile {
    let data: Data
    let filename: String
}

private enum PastedFileError: LocalizedError {
    case unreadableURL
    case unreadableImage
    case fileTooLarge(filename: String)

    var errorDescription: String? {
        switch self {
        case .unreadableURL:
            String(localized: "Could not read the pasted file.")
        case .unreadableImage:
            String(localized: "Could not read the pasted image.")
        case .fileTooLarge(let filename):
            PendingAttachment.uploadTooLargeMessage(filename: filename)
        }
    }
}

private extension SlashCommandExecutionResult {
    var isSuccessfulSubmission: Bool {
        switch self {
        case .executed, .openedSession:
            true
        case .sendAsMessage, .unsupported, .needsSubArg:
            false
        }
    }
}

// MARK: - Sheet Views (no new files needed)

/// Where a scheduled message should be delivered when it fires.
enum ScheduledMessageTarget {
    /// The chat the user is currently viewing.
    case currentChat
    /// The server should create a brand-new chat. `title` is the optional
    /// user-chosen name for that new chat.
    case newChat(title: String?)
    /// A specific existing chat, picked from the session list.
    case existing(sessionId: String, title: String?)
}

/// Explicit destination choice shown when the message is NOT attached to the
/// current chat — so the user always sees where the message will go.
private enum ScheduledChatChoice: String, CaseIterable, Identifiable {
    case newChat = "New Chat"
    case existingChat = "Existing Chat"

    var id: String { rawValue }
}

struct ScheduleMessageSheet: View {
    let draftMessage: String
    let chatTitle: String?
    let client: APIClient?
    let onSchedule: (Date, String, ScheduledMessageTarget) -> Void
    let onCancel: () -> Void

    @State private var messageText: String = ""
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var attachToChat: Bool
    @State private var showEmptyAlert = false
    @State private var sessions: [SessionListItem] = []
    @State private var pickedExistingSession: SessionListItem?
    @State private var showSessionPicker = false
    @State private var chatChoice: ScheduledChatChoice = .newChat
    @State private var newChatTitle = ""

    init(
        draftMessage: String,
        chatTitle: String? = nil,
        client: APIClient? = nil,
        onSchedule: @escaping (Date, String, ScheduledMessageTarget) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.draftMessage = draftMessage
        self.chatTitle = chatTitle
        self.client = client
        self.onSchedule = onSchedule
        self.onCancel = onCancel
        _attachToChat = State(initialValue: chatTitle != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $messageText)
                        .font(.body)
                        .frame(minHeight: 80)
                } header: {
                    Text("Message")
                }

                if let title = chatTitle {
                    Section {
                        Toggle("Attach to \u{201C}\(title)\u{201D}", isOn: $attachToChat)
                    }
                }

                // When not attached to the current chat, the destination MUST
                // be explicit: a brand-new chat or one picked from the list.
                if !attachToChat {
                    Section {
                        Picker("Destination", selection: $chatChoice) {
                            ForEach(ScheduledChatChoice.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)

                        if chatChoice == .newChat {
                            TextField("New chat title (optional)", text: $newChatTitle)
                                .textInputAutocapitalization(.sentences)
                        }

                        if chatChoice == .existingChat {
                            if let picked = pickedExistingSession {
                                HStack {
                                    Label(picked.displayTitle, systemImage: "bubble.left.and.bubble.right")
                                    Spacer()
                                    Button("Change") { showSessionPicker = true }
                                }
                            } else {
                                Button {
                                    showSessionPicker = true
                                } label: {
                                    Label("Choose Chat", systemImage: "bubble.left.and.bubble.right")
                                }
                            }
                        }
                    }
                }

                Section {
                    DatePicker(
                        "Send at",
                        selection: $scheduledDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Schedule Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            showEmptyAlert = true
                            return
                        }
                        // Require an explicit destination before scheduling.
                        guard target != nil else {
                            showSessionPicker = true
                            return
                        }
                        HermexLogger.shared.log(
                            type: "event",
                            screen: "ScheduleSheet",
                            message: "schedule confirmed target=\(target!)"
                        )
                        onSchedule(scheduledDate, messageText, target!)
                    }
                }
            }
            .alert("Message text cannot be empty", isPresented: $showEmptyAlert) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showSessionPicker) {
                SessionPickerForForward(sessions: sessions, title: "Choose Chat") { session in
                    pickedExistingSession = session
                    chatChoice = .existingChat
                    // Choosing an explicit existing chat must clear "Attach to
                    // current". The attach toggle stays on by default when the
                    // sheet opens from a chat, and `target` returns .currentChat
                    // while it's on — so without this the user's explicit pick

                    // silently ignored and the message goes to the current/new
                    // chat instead of the one they chose.
                    attachToChat = false
                }
            }
            .task {
                guard let client else { return }
                do {
                    let response = try await client.sessions()
                    sessions = (response.sessions ?? []).map {
                        SessionListItem(
                            id: $0.sessionId ?? $0.id,
                            displayTitle: $0.title ?? "Chat",
                            lastMessagePreview: nil
                        )
                    }
                } catch {
                    sessions = []
                }
            }
        }
        .onAppear {
            messageText = draftMessage
        }
        .presentationDetents([.medium, .large])
    }

    /// Explicit destination, or nil when the user picked "Existing Chat" but
    /// hasn't chosen one yet.
    private var target: ScheduledMessageTarget? {
        if attachToChat {
            return .currentChat
        }
        switch chatChoice {
        case .newChat:
            let title = newChatTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return .newChat(title: title.isEmpty ? nil : title)
        case .existingChat:
            guard let picked = pickedExistingSession, !picked.id.isEmpty else { return nil }
            return .existing(sessionId: picked.id, title: picked.displayTitle)
        }
    }
}

fileprivate struct ForwardMessageSheet: View {
    let content: (text: String, author: String, sessionTitle: String)?
    let onForward: (String, String, String, String) -> Void
    let client: APIClient

    @State private var sessions: [SessionSummary] = []

    var body: some View {
        SessionPickerForForward(
            sessions: sessions.map {
                SessionListItem(id: ($0.id ?? $0.sessionId) ?? "", displayTitle: $0.title ?? "Chat", lastMessagePreview: nil)
            }
        ) { session in
            guard let content else { return }
            onForward(content.text, content.author, content.sessionTitle, session.id)
        }
        .task {
            do {
                let response = try await client.sessions()
                sessions = response.sessions ?? []
            } catch {
                sessions = []
            }
        }
    }
}


// MARK: - System Share Sheet (inlined — fileprivate to avoid pbxproj changes)

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Pinned messages list (Telegram-style: a page listing every pin)

/// A sheet listing all pinned messages, newest first. Tapping a row scrolls the
/// transcript to it; a trailing unpin button removes it. Mirrors Telegram's
/// "pinned messages" page instead of stacking every pin in the chat header.
private struct PinnedMessagesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pinnedIDs: [String]
    let messages: [ChatMessage]
    let onSelect: (String) -> Void
    let onUnpin: (String) -> Void

    private var pinnedMessages: [(id: String, message: ChatMessage)] {
        // Preserve pin order (newest last), skip ids no longer present.
        pinnedIDs.compactMap { id in
            messages.first(where: { $0.id == id }).map { (id, $0) }
        }
        .reversed()
    }

    var body: some View {
        NavigationStack {
            Group {
                if pinnedMessages.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Pinned Messages"),
                        systemImage: "pin",
                        description: Text(String(localized: "Long-press a message and choose Pin to keep it here."))
                    )
                } else {
                    List {
                        ForEach(pinnedMessages, id: \.id) { item in
                            Button {
                                dismiss()
                                onSelect(item.id)
                            } label: {
     VStack(alignment: .leading, spacing: 3) {
         HStack(spacing: 6) {
             Text(item.message.role == "user" ? "You" : "Hermes")
                 .font(.caption.weight(.semibold))
                 .foregroundStyle(.secondary)
             Spacer()
             Label(String(localized: "View in chat"), systemImage: "arrow.turn.down.right")
                 .font(.caption)
                 .foregroundStyle(.tint)
         }
         Text(ChatView.pinnedPreview(for: item.message.content))
             .font(.subheadline)
             .lineLimit(2)
             .foregroundStyle(.primary)
     }
     .frame(maxWidth: .infinity, alignment: .leading)
 }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onUnpin(item.id)
                                } label: {
                                    Label(String(localized: "Unpin"), systemImage: "pin.slash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(String(localized: "Pinned Messages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Search the current chat's transcript messages. New fileprivate struct so no
/// pbxproj registration is needed (inlined at the bottom of ChatView.swift).
fileprivate struct ChatSearchSheet: View {
    let messages: [ChatMessage]
    let roleForMessage: (String?) -> String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [ChatMessage] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return messages.filter { message in
            (message.content ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { message in
                    Button {
                        onSelect(message.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(roleForMessage(message.role))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(message.content ?? "")
                                .font(.subheadline)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(String(localized: "Search Chat"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: String(localized: "Search messages"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
            }
        }
    }
}

private struct ChatDraftSyncModifier: ViewModifier {
    let pendingAttachments: [PendingAttachment]
    let composerSettings: ChatDraftSettings
    let onAttachmentsChange: () -> Void
    let onSettingsChange: (ChatDraftSettings) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: pendingAttachments) { _, _ in
                onAttachmentsChange()
            }
            .onChange(of: composerSettings) { _, newSettings in
                onSettingsChange(newSettings)
            }
    }
}
