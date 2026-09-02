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

/// What the per-turn diff sheet shows (issue #316): every changed file in the turn, or a
/// single file's diff (a recap-card row tap).
private enum TurnDiffPresentation: Identifiable {
    case turnFiles([GitFile])
    case file(GitFile)

    var id: String {
        switch self {
        case .turnFiles(let files): return "turn:" + files.map(\.id).joined(separator: "|")
        case .file(let file): return "file:" + file.id
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
    private let transcriptMessageSpacing: CGFloat = 10
    private let transcriptBlockSpacing: CGFloat = 6
    private let composerAccessoryVerticalSpacing: CGFloat = 8
    private let activeRunStatusSpacerHeight: CGFloat = 36
    private let approvalBypassStatusSpacerHeight: CGFloat = 38

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppHaptics.isEnabledKey) private var isHapticsEnabled = true
    @AppStorage(StreamingSendBehavior.storageKey) private var streamingSendBehaviorRawValue = StreamingSendBehavior.steer.rawValue
    @AppStorage(ResponseCompletionNotifications.isEnabledKey) private var isResponseCompletionNotificationsEnabled = false
    @AppStorage(AgentRunLiveActivityPrivacy.showsResponseExcerptsKey) private var showsLiveActivityResponseExcerpts = false
    @AppStorage(ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey) private var showsThinkingAndToolCards = true
    @AppStorage(ChatTranscriptDisplaySettings.suppressesReasoningAndToolUpdatesKey) private var suppressesReasoningAndToolUpdates = false
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

    @State private var draftMessage = ""
    @State private var isScrolledNearBottom = true
    @State private var isReadingOlderTranscript = false
    @State private var showsPendingDecisionOverlay = false
    /// Measured height of the inline clarification card (0 when none). Drives
    /// the collision-avoidance lift for the floating controls so they clear the
    /// actual card, not a fixed maximum (which would over-lift for short cards).
    @State private var clarificationCardHeight: CGFloat = 0
    /// Single source of truth for who may scroll the transcript (see
    /// `ChatScrollPolicy.resolveOwner`). All scroll sites read only this.
    /// Observable scroll-ownership container — isolated from ChatView body to
    /// prevent AttributeGraph freezes on owner transitions (see ScrollOwnershipState).
    @State private var scrollOwnership = ScrollOwnershipState()
    @State private var followScrollGeneration = 0
    @State private var isUserInteractingWithScroll = false
    @State private var userScrollCooldownUntil: Date?
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
    @State private var selectableResponseText: SelectableResponseText?
    @State private var attachmentPreviewItem: ChatAttachmentPreviewItem?
    @State private var transcriptMediaPreviewItem: TranscriptMediaPreviewItem?
    @State private var pendingProfileSelection: ProfileSummary?
    @State private var forwardMessageContent: (text: String, author: String, sessionTitle: String)?
    @State private var showingForwardPicker = false
    @State private var showingSchedulePicker = false
    @State private var showingScheduledList = false
    @State private var showingChatSearch = false
    @State private var showShareSheet = false
    @State private var shareText = ""
    @State private var showProfileNewSessionConfirmation = false
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
    @State private var composerIsFocused = false
    /// Full-screen reading mode: the composer is HIDDEN by default; a round
    /// compose FAB at the bottom-trailing reveals it on demand (tap → composer
    /// slides up + keyboard). Hidden again on tap-outside, scroll, or after
    /// sending — the chat returns to reading the response full-screen.
    @State private var composerVisible = true
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
        initialAttachments: [SharedAttachmentImport] = [],
        loadsInitialMessages: Bool = true,
        autoStartsVoiceInput: Bool = false
    ) {
        self.session = session
        self.server = server
        self.onAPIError = onAPIError
        self.loadsInitialMessages = loadsInitialMessages
        self.autoStartsVoiceInput = autoStartsVoiceInput
        let restoredDraft: String
        if initialDraft.isEmpty, let sid = session.sessionId {
            restoredDraft = UserDefaults.standard.string(forKey: "chat.draft.\(sid)") ?? ""
        } else {
            restoredDraft = initialDraft
        }
        _draftMessage = State(initialValue: restoredDraft)
        _initialAttachments = State(initialValue: initialAttachments)
        _viewModel = State(initialValue: ChatViewModel(
            session: session,
            server: server,
            showsLiveActivityResponseExcerpts: UserDefaults.standard.bool(
                forKey: AgentRunLiveActivityPrivacy.showsResponseExcerptsKey
            )
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
            draftMessage: $draftMessage,
            isFocused: $composerIsFocused,
            isSending: viewModel.isStartingChat || viewModel.isSendingVoiceNote,
            isCompressingSession: viewModel.isCompressingSession,
            isWaitingForStream: viewModel.activeStreamID != nil,
            isCancellingStream: viewModel.isCancellingStream,
            isOfflineReadOnly: viewModel.isViewingCachedData,
            isChromeCompact: isComposerChromeCompact,
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
            agentCommands: viewModel.agentCommands,
            profileOptions: viewModel.profileOptions,
            isSingleProfileMode: viewModel.isSingleProfileMode,
            selectedProfileName: viewModel.selectedProfileName,
            selectedProfileTitle: viewModel.selectedProfileTitle,
            isLoadingModels: viewModel.isLoadingComposerConfiguration,
            selectedReasoningEffort: viewModel.selectedReasoningEffort,
            supportedReasoningEfforts: viewModel.supportedReasoningEfforts,
            showsReasoningControl: viewModel.showsReasoningEffortControl,
            isUpdatingConfiguration: viewModel.isUpdatingComposerConfiguration,
            pendingAttachments: viewModel.pendingAttachments,
            isUploadingAttachment: viewModel.isUploadingAttachment,
            attachmentUploadCount: viewModel.attachmentUploadCount,
            attachmentUploadGeneration: viewModel.attachmentUploadGeneration,
            isSendingVoiceNote: viewModel.isSendingVoiceNote,
            autoStartsVoiceInput: autoStartsVoiceInput,
            apiClient: viewModel.client,
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
            onSelectReasoningEffort: { effort in
                Task {
                    let didSelect = await viewModel.selectReasoningEffort(effort)
                    if didSelect {
                        let _: Void = ChatHaptics.configurationSelected(isEnabled: isHapticsEnabled)
                    }
                }
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
                viewModel.removePendingAttachment(id: id)
            },
            onPreviewAttachment: { attachment in
                presentPreviewRestoringComposerFocusIfNeeded {
                    attachmentPreviewItem = ChatAttachmentPreviewItem(pending: attachment)
                }
            },
            onDismissUploadAttachmentError: {
                viewModel.setUploadAttachmentError(nil)
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

    private func transcriptMediaPreviewView(for item: TranscriptMediaPreviewItem) -> some View {
        TranscriptMediaPreviewView(
            server: server,
            sessionID: transcriptMediaSessionID,
            item: item,
            onAPIError: onAPIError
        )
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

    @ViewBuilder
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

                    messageComposer
                } else if viewModel.clarificationPrompt == nil {
                    composeFAB
                }
            }
            .transition(ChatMotion.bottomOverlayTransition(reduceMotion: reduceMotion))

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

            if showsPendingDecisionOverlay,
               let clarificationPrompt = viewModel.clarificationPrompt {
                ClarificationRequestOverlay(
                    prompt: clarificationPrompt,
                    isResponding: viewModel.isRespondingToClarification,
                    errorMessage: viewModel.clarificationErrorMessage,
                    bottomPadding: composerVisible ? composerHeight + 16 : 24,
                    onSubmit: { response in
                        Task {
                            _ = await viewModel.respondToClarification(response)
                        }
                    }
                )
                .zIndex(11)
            }
        }
    }

    private var chatViewContent: some View {
        chatContent
            .overlay(alignment: .top) {
            GitActionToastOverlay(state: gitToastState)
        }
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
            .onChange(of: viewModel.cacheFirstReconcileScrollToken) {
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
            .onChange(of: composerIsFocused) {
                // Focusing the composer is explicit write intent — clear the
                // "reading older transcript" compact mode so the secondary bar
                // (workspace dir + profile + git) re-expands only on the user's own
                // tap, never on scroll/⬇️. Keeps composer state consistent.
                if composerIsFocused, isReadingOlderTranscript {
                    withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
                        isReadingOlderTranscript = false
                    }
                }
            }
            .onChange(of: showsLiveActivityResponseExcerpts) {
                viewModel.setShowsLiveActivityResponseExcerpts(showsLiveActivityResponseExcerpts)
            }
            .onChange(of: suppressesReasoningAndToolUpdates) {
                viewModel.setSuppressesReasoningAndToolUpdates(suppressesReasoningAndToolUpdates)
            }
            .onDisappear {
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
            GitWorkspaceView(session: session, server: server, onAPIError: onAPIError)
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
        case .turnFiles(let files):
            GitTurnDiffSheet(session: session, server: server, files: files, onAPIError: onAPIError)
        case .file(let file):
            GitDiffView(session: session, server: server, file: file, onAPIError: onAPIError)
        }
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
        guard gitAvailabilityViewModel.hasRepository,
              viewModel.activeStreamID == nil,
              latestTranscriptMessageRole == "assistant",
              gitAvailabilityViewModel.hasCommittableChanges || gitAvailabilityViewModel.isCommitting
        else { return nil }
        return ChatInlineCommitContext(
            runningPhase: gitAvailabilityViewModel.commitPhase,
            isDisabled: gitWriteAvailability.writesDisabled
        )
    }

    /// Turn-end "File changes" recap card for the latest assistant turn (#316). Only for git
    /// workspaces once the response finishes (status has refreshed) and the latest turn
    /// actually changed files.
    private var turnChangesRecapSummary: TurnFileChangeSummary? {
        guard gitAvailabilityViewModel.hasRepository,
              viewModel.activeStreamID == nil,
              latestTranscriptMessageRole == "assistant"
        else { return nil }
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
        turnDiffPresentation = .turnFiles(files)
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
        case .nothingToCommit:
            gitToastState.dismissProgress()
            gitAlert = .error(String(localized: "There are no changes to commit."))
        case .tooManyChanges:
            // Status was truncated (>500 files): the commit was blocked to avoid silently
            // dropping files 501+. Always surface a message — falling back to a hardcoded
            // string if the view model ever leaves actionErrorMessage unset — because a
            // blocked commit with no feedback would be the very silent failure this guards
            // against. (Kept separate from .failure, which intentionally stays quiet when its
            // busy/no-session guard returns with no message.) No success toast/SHA.
            gitToastState.dismissProgress()
            gitAlert = .error(gitAvailabilityViewModel.actionErrorMessage
                ?? String(localized: "Too many changes to quick-commit. Commit in smaller batches, or use git directly."))
        case .failure:
            gitToastState.dismissProgress()
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
        } else {
            gitToastState.dismissProgress()
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

    @ViewBuilder
    private var composerAccessoryStack: some View {
        if composerAccessoryVisibleItemCount > 0 {
            VStack(spacing: composerAccessoryVerticalSpacing) {
                if !viewModel.pinnedLocalNotices.isEmpty {
                    PinnedLocalNoticeStack(notices: viewModel.pinnedLocalNotices)
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
            .padding(.bottom, composerHeight + 8)
            .allowsHitTesting(false)
            .zIndex(8)
            .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: composerAccessoryVisibleItemCount)
            .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: activeRunStatusPresentation)
            .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: viewModel.pinnedLocalNotices)
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
            clarificationPrompt: viewModel.clarificationPrompt,
            isRespondingToClarification: viewModel.isRespondingToClarification,
            clarificationErrorMessage: viewModel.clarificationErrorMessage,
            hidesRunStatusAccessibility: activeRunStatusPresentation != nil,
            showsThinkingAndToolCards: showsThinkingAndToolCards,
            showsAssistantTypingIndicator: showsAssistantTypingIndicator,
            showsCompressingStatus: viewModel.isCompressingContext,
            scrollOwnership: scrollOwnership,
            activeStreamID: viewModel.activeStreamID,
            streamingScrollTrigger: viewModel.streamingScrollTrigger,
            cacheFirstReconcileScrollToken: viewModel.cacheFirstReconcileScrollToken,
            bottomAnchorID: bottomAnchorID,
            transcriptMessageSpacing: transcriptMessageSpacing,
            transcriptBlockSpacing: transcriptBlockSpacing,
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
            onDismissKeyboard: handleTranscriptTap,
            onScrollToBottom: scrollToBottom,
            onScrollToLatestTranscriptMessage: { proxy in
                scrollToLatestTranscriptMessage(proxy)
            },
            onScrollToLatestContent: { proxy, animated, source in
                scrollToLatestContent(proxy, animated: animated, source: source ?? "latestContent")
            },
            onPreviewAttachment: { attachment, localData in
                presentPreviewRestoringComposerFocusIfNeeded {
                    attachmentPreviewItem = ChatAttachmentPreviewItem(message: attachment, localData: localData)
                }
            },
            onPreviewTranscriptMedia: { reference in
                transcriptMediaPreviewItem = TranscriptMediaPreviewItem(reference: reference)
            },
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
                turnDiffPresentation = .file(file)
            }
        )
        // scrollOwnership is passed directly to ChatTranscriptView (no environment cascade)
        .environment(\.isScrolledNearBottom, isScrolledNearBottom)
        .environment(\.isAutoScrollPaused, isAutoFollowScrollPaused)
        // showsScrollToBottomButton is now derived inside ChatTranscriptView from scrollOwnership
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

    /// The chat-canvas layout direction. Driven by the manual Settings → Chat
    /// RTL toggle (#259); applied only to the transcript + composer so the
    /// sidebar, settings, and navigation chrome stay in the default direction.
    private var chatLayoutDirection: LayoutDirection {
        ChatTranscriptDisplaySettings.chatLayoutDirection(rtlEnabled: rtlChatLayoutEnabled)
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
        // Compact chrome is a *reading* mode triggered by scrolling up into older
        // messages. Focusing the composer (intent to write) and sending always
        // re-expand it, so the secondary bar (workspace dir + profile + git) only
        // appears on an explicit write action — never as a side effect of scrolling
        // back down or tapping ⬇️. Decoupling this from scroll prevents the
        // "composer jumps / folder+profile flash" when the transcript re-anchors.
        isReadingOlderTranscript && !composerIsFocused && !viewModel.messages.isEmpty
    }

    /// Height reserved at the transcript bottom for the inline clarification
    /// card when one is pending. Drives the collision-avoidance lift so the
    /// floating controls clear the ACTUAL card height (measured via
    /// `onClarificationCardHeightChange`) — not a fixed max, which would
    /// over-lift for short cards. 0 when no card is on screen.
    private var transcriptBottomInsetHeight: CGFloat {
        // Reading mode (composer hidden): the transcript runs to the very bottom
        // of the screen — 0 inset. Only when the composer is visible does the
        // content lift above it.
        let base = composerVisible
            ? max(96, composerHeight + 44 + composerAccessorySpacerHeight)
            : 0
        // Collision avoidance: when a clarification card is displayed inline, the
        // transcript must leave room for it as well as the composer, so the
        // floating controls don't overlap the card.
        return base + clarificationCardHeight
    }

    private var scrollToBottomButtonBottomPadding: CGFloat {
        // Friend-row with the compose FAB (48pt + 8pt gap + 20pt bottom): ↓
        // sits directly above the FAB in one bottom-right cluster. When the
        // composer is visible the FAB is hidden and the button clears the
        // composer as before.
        let base = composerVisible
            ? composerHeight + 12 + composerAccessorySpacerHeight
            : 76
        // Collision avoidance: lift the ↓ button above the inline clarification
        // card so it never overlaps the question/options.
        return base + clarificationCardHeight
    }

    private var pinnedNoticeSpacerHeight: CGFloat {
        viewModel.pinnedLocalNotices.isEmpty ? 0 : CGFloat(viewModel.pinnedLocalNotices.count) * 60
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
        if !viewModel.pinnedLocalNotices.isEmpty {
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
        prepareInitialAppearance()

        guard ChatInitialAppearancePolicy.shouldBeginAsyncWork(
            hasCompletedAppearance: didCompleteInitialAppearance
        ) else {
            return
        }

        async let chatStartup: Void = performInitialAsyncWork()
        async let gitAvailability: Void = loadInitialGitAvailability()
        _ = await (chatStartup, gitAvailability)
    }

    private func performInitialAsyncWork() async {
        guard !Task.isCancelled else { return }

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
        scrollOwnership.owner = .user
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

    @discardableResult
    private func sendDraftMessage() async -> Bool {
        let submittedDraft = draftMessage

        if submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
            let parsedCommand = SlashCommandExecutor.parse(submittedDraft)?.command
            let result = await SlashCommandExecutor.execute(text: submittedDraft, viewModel: viewModel)
            handleSlashExecutionResult(result, parsedCommand: parsedCommand)

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
                submittedDraft,
                behavior: StreamingSendBehavior.storedValue(streamingSendBehaviorRawValue)
            )
            handleSlashExecutionResult(result, parsedCommand: SlashCommandCatalog.command(named: streamingSendBehaviorCommandName))
            didStart = result.isSuccessfulSubmission
        } else {
            didStart = await sendStandardMessage(submittedDraft)
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
            ChatHaptics.messageSent(isEnabled: isHapticsEnabled)
            // Composer stays visible after voice note send (always-visible mode).
        }

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private func sendStandardMessage(_ submittedDraft: String) async -> Bool {
        guard !submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        prepareTranscriptForExplicitSend()

        draftMessage = ""

        let didStart = await viewModel.sendMessage(submittedDraft, modelContext: modelContext)
        if !didStart, draftMessage.isEmpty {
            draftMessage = submittedDraft
        }

        return didStart
    }

    private func handleSlashExecutionResult(
        _ result: SlashCommandExecutionResult,
        parsedCommand: SlashCommand?
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
            draftMessage = ""
        case .openedSession(let session):
            forkedSession = session
            draftMessage = ""
        case .unsupported(let friendlyMessage):
            viewModel.setSendErrorMessage(friendlyMessage)
            draftMessage = ""
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
        let outcome = await viewModel.switchProfile(profile, startNewSession: startNewSession)
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
        // The ↓ button does exactly one thing: scroll to the very bottom of the
        // transcript. Target the 1pt `bottomAnchorID` marker that sits at the
        // true end of the content — NOT the last message, which can stop short of
        // the actual bottom (trailing padding, typing indicator, etc.), leaving
        // the viewport above the newest content and making the button feel dead.
        //
        // Cancel in-flight deceleration first: while the user's flick is still
        // coasting, `ScrollViewProxy.scrollTo` is silently ignored, so the button
        // would otherwise appear dead until the scroll settled.
        NotificationCenter.default.post(name: .hermexCancelTranscriptInertia, object: nil)
        scrollToLatestContent(proxy, animated: false, isUserInitiated: true, source: "down")
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
        // Auto-follow (streaming tokens, new rows) must not override the user's
        // scroll position while they are interacting or within the cooldown.
        if !isUserInitiated, isAutoFollowScrollPaused {
            return
        }

        if isUserInitiated {
            // An explicit ↓ tap / send is an unconditional re-arm of follow-latest.
            scrollOwnership.owner = .app
            userScrollCooldownUntil = nil
        } else if scrollOwnership.owner == .user {
            // Auto channels (streaming size changes, new message rows) must never
            // re-arm follow-latest. If the reader owns the viewport, ownership
            // stays with them until they explicitly tap ↓ or send. Re-arming here
            // is what silently yanked the viewport back down mid-read.
            return
        }
        followScrollGeneration += 1
        let generation = followScrollGeneration

        Task { @MainActor in
            await Task.yield()
            // Streaming follow fires on every token flush (~20-50/s). Sleeping here
            // queues a fresh Task per flush that then has to jump back onto MainActor,
            // which accumulates into visible scroll lag while the response streams.
            // The sleep only benefits the animated non-streaming follow (letting a
            // queued animation retarget), which no longer happens during streaming.
            if viewModel.activeStreamID == nil, !isUserInitiated {
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            // An explicit ↓ tap is unconditional: never let a newer auto-follow
            // generation cancel it, or the button feels dead if a token flush (or
            // any background scroll) lands between the tap and this fire.
            guard !Task.isCancelled, (isUserInitiated || generation == followScrollGeneration) else { return }
            // Re-check at fire time: a gesture may have begun during the delay.
            if !isUserInitiated, isAutoFollowScrollPaused { return }

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
                    "scrollOwner": scrollOwnership.owner == .app ? "app" : "user",
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

    private func updateScrollMetrics(_ metrics: ChatScrollMetrics) {
        let isStreaming = viewModel.activeStreamID != nil
        let isNearBottom = ChatScrollPolicy.isNearBottom(
            distanceFromBottom: metrics.distanceFromBottom,
            isStreaming: isStreaming
        )
        // Ownership uses a MUCH stricter threshold: the reader owns the viewport
        // unless they are literally at the bottom (≤8pt). UI bands (80/160pt)
        // still drive chrome state below.
        let isAtVeryBottom = metrics.distanceFromBottom <= ChatScrollPolicy.ownershipBottomThreshold
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

        // Touching the scroll view pauses auto-follow for a short window so
        // streaming layout growth cannot yank the viewport mid-gesture.
        if metrics.isUserInteracting {
            userScrollCooldownUntil = ChatScrollPolicy.cooldownDeadline()
        }

        // The single ownership decision (ChatScrollPolicy.resolveOwner):
        //   - finger priority over printing: while streaming, ANY scroll touch
        //     immediately yields the viewport to the reader — without this the
        //     160pt streaming near-bottom band kept follow-latest on, and the
        //     system `.sizeChanges` anchor glued the viewport back on every
        //     token, so the reader could never escape the band;
        //   - ownership must also follow the position, not the touch state: a
        //     quick flick up that ends before the next sample must still drop
        //     app ownership (synchronous KVO metrics make this reliable);
        //   - idle at the bottom returns ownership to the app;
        //   - while streaming, ownership stays with the reader until an
        //     explicit ↓ tap or send (Telegram-style, no auto-glue).
        // NOTE: isReadingOlderTranscript is intentionally NOT reset on
        // near-bottom. Resetting it made the composer chrome re-expand purely
        // because the transcript re-anchored — the "composer jumps when I tap
        // ↓" bug. Reading mode clears only on explicit write intent.
        let resolved = ChatScrollPolicy.resolveOwner(
            current: scrollOwnership.owner,
            isStreaming: isStreaming,
            isUserInteracting: metrics.isUserInteracting,
            isAtVeryBottom: isAtVeryBottom,
            isInCooldown: userScrollCooldownUntil.map { Date() < $0 } ?? false
        )
        if scrollOwnership.owner != resolved {
            let previous = scrollOwnership.owner
            scrollOwnership.owner = resolved
            MainThreadWatchdog.setPerformanceContext(scrollOwner: resolved == .app ? "app" : "user")
            // Telemetry: prove the yank on-device — owner transitions with the
            // position metrics that caused them. Rate-limited naturally: the
            // equality guard above fires only on flips.
            let ctx = MainThreadWatchdog.snapshotPerformanceContext()
            HermexLogger.shared.log(
                type: "event",
                screen: "ChatView",
                message: "scroll owner \(previous == .app ? "app→user" : "user→app")",
                extras: [
                    "distanceFromBottom": Int(metrics.distanceFromBottom),
                    "isStreaming": isStreaming,
                    "isInteracting": metrics.isUserInteracting,
                    "isNearBottom": isNearBottom,
                    "messageCount": ctx.messageCount,
                    "displayedRowCount": ctx.displayedRowCount,
                    "scrollOwner": previous == .app ? "app" : "user",
                ]
            )
        }

        if !isNearBottom,
           !isReadingOlderTranscript,
           ChatScrollPolicy.shouldEnterReadingOlder(
               distanceFromBottom: metrics.distanceFromBottom,
               isStreaming: isStreaming
           ) {
            withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
                isReadingOlderTranscript = true
            }
        }
    }

    private var isAutoFollowScrollPaused: Bool {
        ChatScrollPolicy.isAutoScrollPaused(
            isUserInteracting: isUserInteractingWithScroll,
            cooldownUntil: userScrollCooldownUntil
        )
    }

    private func prepareTranscriptForExplicitSend() {
        scrollOwnership.owner = .app
        // Explicit send re-pins to the tail: the new message must be visible even
        // if the reader had scrolled up. Mark near-bottom so the `.onChange`
        // channels let the scroll-to-latest run instead of silently suppressing
        // it (ownership alone gates them; this keeps the presentation signals
        // consistent too).
        isScrolledNearBottom = true
        userScrollCooldownUntil = nil
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
