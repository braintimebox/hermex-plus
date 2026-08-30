import SwiftUI
import UIKit

struct ChatTranscriptView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Exact scroll-position preservation across "Load older" prepends. The
    /// naive `ScrollViewProxy.scrollTo(identity, .top)` fallback cannot align to
    /// a not-yet-mounted LazyVStack row, so the controller snapshots the UIKit
    /// geometry before the request and offsets by the content-height delta.
    @State private var prependScrollPositionController = ChatPrependScrollPositionController()

    let isLoading: Bool
    let errorMessage: String?
    let messages: [ChatMessage]
    /// When set, scroll to the transcript row whose `message.id` matches this.
    /// The parent clears it via `onPinnedScrollConsumed` after the scroll fires.
    var pinnedScrollTarget: String? = nil
    var onPinnedScrollConsumed: () -> Void = {}
    let displayedTranscriptMessages: [TranscriptMessage]
    let compressionReferenceCard: CompressionReferenceCard?
    let reasoningGroups: [ReasoningGroup]
    let completedToolCallGroupsForAnchor: (String?) -> [ToolCallGroup]
    let liveReasoningText: String
    let reasoningAnchorMessageID: String?
    let liveToolCalls: [ToolCall]
    let toolCallAnchorMessageID: String?
    let streamingAssistantMessageID: String?
    let liveTokensPerSecond: Double?
    let activeStreamRecoveryState: ActiveStreamRecoveryState
    let clarificationPrompt: ClarificationPromptState?
    let isRespondingToClarification: Bool
    let clarificationErrorMessage: String?
    let hidesRunStatusAccessibility: Bool
    let showsThinkingAndToolCards: Bool
    let showsAssistantTypingIndicator: Bool
    let showsCompressingStatus: Bool
    let showsScrollToBottomButton: Bool
    let scrollOwner: ChatScrollOwner
    let isAutoScrollPaused: Bool
    let latestTranscriptMessageRole: String?
    let isScrolledNearBottom: Bool
    let activeStreamID: String?
    let streamingScrollTrigger: Int
    let cacheFirstReconcileScrollToken: Int
    let bottomAnchorID: String
    let transcriptMessageSpacing: CGFloat
    let transcriptBlockSpacing: CGFloat
    let transcriptBottomInsetHeight: CGFloat
    let scrollToBottomButtonBottomPadding: CGFloat
    let localAttachmentPreviews: [String: [String: Data]]
    let listeningMessageID: String?
    let isViewingCachedData: Bool
    let hasOlderMessages: Bool
    let isLoadingOlderMessages: Bool
    let isRegeneratingMessage: Bool
    let isEditingMessage: Bool
    let isForkingMessage: Bool
    let loadAttachmentImage: (String) async -> Data?
    let loadAttachmentData: (String) async -> Data?
    let loadTranscriptMediaImage: (TranscriptMediaReference) async -> Data?
    let loadTranscriptMediaData: (TranscriptMediaReference) async -> Data?
    let transcriptMediaCacheNamespace: String
    let actionContext: (ChatMessage, Int) -> MessageActionContext?
    let shouldRenderMessageRow: (ChatMessage) -> Bool
    let onLoadMessages: () async -> Void
    let onLoadOlderMessages: () async -> Bool
    let onUpdateScrollMetrics: (ChatScrollMetrics) -> Void
    let onDismissKeyboard: () -> Void
    let onScrollToBottom: (ScrollViewProxy) -> Void
    let onScrollToLatestTranscriptMessage: (ScrollViewProxy) -> Void
    let onScrollToLatestContent: (ScrollViewProxy, Bool, String?) -> Void
    let onPreviewAttachment: (MessageAttachment, Data?) -> Void
    let onPreviewTranscriptMedia: (TranscriptMediaReference) -> Void
    let onToggleListening: (MessageActionContext) -> Void
    let onSubmitClarification: (String) -> Void
    /// Reports the measured height of the inline clarification card so the
    /// parent can lift the floating controls above it (collision avoidance) —
    /// 0 when no card is shown. Uses onGeometryChange (iOS 18+).
    var onClarificationCardHeightChange: (CGFloat) -> Void = { _ in }
    let onSelectText: (MessageActionContext) -> Void
    let onRegenerate: (MessageActionContext) -> Void
    let onEdit: (MessageActionContext) -> Void
    let onFork: (MessageActionContext) -> Void
    let onCopy: (MessageActionContext) -> Void
    let onReply: (MessageActionContext) -> Void
    let onForward: (MessageActionContext) -> Void
    let onSave: (MessageActionContext) -> Void
    let onPin: ((MessageActionContext) -> Void)?
    let isMessagePinned: (String) -> Bool
    /// Non-nil shows the inline "Commit & Push" button under the latest assistant turn
    /// (issue #315, Slice C, surface B). Nil hides it (non-git chats, no changes, etc.).
    var inlineCommitContext: ChatInlineCommitContext? = nil
    var onInlineCommit: () -> Void = {}
    /// Non-nil shows the turn-end "File changes" recap card under the latest assistant turn
    /// (issue #316, Slice D, surface B). Nil hides it (non-git chats, no changes, streaming).
    var turnChangesSummary: TurnFileChangeSummary? = nil
    var onOpenTurnDiff: () -> Void = {}
    var onOpenTurnFileDiff: (GitFile) -> Void = { _ in }

    var body: some View {
        if isLoading && messages.isEmpty && clarificationPrompt == nil {
            ChatTranscriptLoadingSkeletonView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, messages.isEmpty, clarificationPrompt == nil {
            ContentUnavailableView {
                Label("Could Not Load Messages", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") {
                    Task { await onLoadMessages() }
                }
            }
        } else if messages.isEmpty && clarificationPrompt == nil {
            ContentUnavailableView {
                Image(systemName: "bubble.left.and.bubble.right")
            } description: {
                Text("Send a message to start the conversation.")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onDismissKeyboard()
            }
        } else {
            transcriptScrollView
        }
    }

    private var transcriptScrollView: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                let viewportWidth = max(0, viewport.size.width)
                let contentWidth = transcriptContentWidth(for: viewportWidth)

                ZStack(alignment: .bottom) {
                    ScrollView {
                        transcriptScrollContent(
                            proxy: proxy,
                            viewportWidth: viewportWidth,
                            contentWidth: contentWidth
                        )
                    }
                    .defaultScrollAnchor(
                        ChatScrollPolicy.initialTranscriptAnchor,
                        for: .initialOffset
                    )
                    .defaultScrollAnchor(
                        ChatScrollPolicy.sizeChangeAnchor(
                            owner: scrollOwner,
                            isAutoScrollPaused: isAutoScrollPaused,
                            // Only glue the viewport to the bottom while content
                            // is actually being printed. While the agent is still
                            // thinking (liveReasoningText non-empty) the size is
                            // NOT growing, so a `.bottom` anchor only competes
                            // with the app's follow path and blocks reading what
                            // is already rendered — the "chat is inaccessible
                            // while the agent thinks" behaviour.
                            // Streaming render is OFF (answer delivered when
                            // ready): the transcript content does NOT grow while
                            // the agent works, so a `.bottom` size-change anchor
                            // only glues the viewport on any incidental re-measure
                            // (scroll tick, row re-measure, typing indicator) and
                            // drives a main-thread re-layout storm — any post-send
                            // scroll/↓ trigger froze dead. Keep the anchor inactive
                            // while the answer is not streaming (no content growth).
                            isStreaming: false
                        ),
                        for: .sizeChanges
                    )
                    .frame(width: viewportWidth)
                    .refreshable {
                        if hasOlderMessages {
                            await loadOlderMessagesPreservingPosition(proxy: proxy)
                        } else {
                            await onLoadMessages()
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear
                            .frame(height: transcriptBottomInsetHeight)
                            .accessibilityHidden(true)
                    }
                    .adaptiveSoftScrollEdges()
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            guard clarificationPrompt == nil else { return }
                            onDismissKeyboard()
                        }
                    )

                    if showsScrollToBottomButton {
                        HStack {
                            Spacer()
                            ChatScrollToBottomButton(
                                bottomPadding: scrollToBottomButtonBottomPadding,
                                onTap: {
                                    onScrollToBottom(proxy)
                                }
                            )
                        }
                        // Bottom-trailing column WITH the compose FAB (friend
                        // row): ↓ lifts above the FAB (44pt + 8pt gap) so the
                        // two Hermex glass circles form one cluster.
                        .padding(.trailing, 12)
                        .transition(ChatMotion.bottomOverlayTransition(reduceMotion: reduceMotion))
                    }
                }
                .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: showsScrollToBottomButton)
                .background(Color(.systemBackground))
                .background {
                    // Overscroll / bounce region below the last message is not
                    // covered by the transcript background in dark mode — scrolling
                    // past the tail (or the .sizeChanges anchor gluing to the bottom
                    // during streaming) can flash a dark gap. Paint the scroll area's
                    // backdrop explicitly so the bounce zone matches the theme.
                    Color(.systemBackground).ignoresSafeArea()
                }
                .onChange(of: messages.count) {
                    // Only follow when the APP owns the viewport. A stale
                    // ownership (linger after a stream) must not yank the
                    // viewport while the user reads older text.
                    guard scrollOwner == .app else { return }

                    if latestTranscriptMessageRole == "user" {
                        onScrollToLatestTranscriptMessage(proxy)
                    } else {
                        onScrollToLatestContent(proxy, true, "newRow")
                    }
                }
                .onChange(of: streamingScrollTrigger) {
                    if scrollOwner == .app {
                        onScrollToLatestContent(proxy, true, "streamingTrigger")
                    }
                }
                .onChange(of: cacheFirstReconcileScrollToken) {
                    // Cache-first reconcile (#289): the server transcript just replaced
                    // the lighter cached render, so snap back to the bottom (no
                    // animation) unless the reader owns the viewport.
                    guard scrollOwner == .app else { return }
                    onScrollToLatestContent(proxy, false, "cacheReconcile")
                }
                .onChange(of: clarificationPrompt?.id) {
                    guard clarificationPrompt != nil, scrollOwner == .app else { return }
                    onScrollToBottom(proxy)
                }
                .onChange(of: pinnedScrollTarget) {
                    guard let target = pinnedScrollTarget else { return }
                    // Resolve the pinned message id → its transcript row's ForEach
                    // identity (messageId ?? renderID), then scroll to it. The
                    // scroll target MUST match the ForEach `.id(transcriptMessage.id)`
                    // or `ScrollViewProxy.scrollTo` is silently ignored. A pinned id
                    // can be stale (e.g. the message was compacted away), so scroll
                    // only when the row still exists.
                    let row = displayedTranscriptMessages.first { $0.message.id == target }
                    if let row {
                        withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
                            proxy.scrollTo(row.id, anchor: .top)
                        }
                    }
                    onPinnedScrollConsumed()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    // Keyboard may show while the reader is up (e.g. FAB tap):
                    // only the app owner may snap to the bottom; a reader who
                    // scrolled up must NOT get yanked by the keyboard event.
                    if scrollOwner == .app, isScrolledNearBottom {
                        onScrollToBottom(proxy)
                    }
                }
            }
        }
    }

    private func transcriptScrollContent(
        proxy: ScrollViewProxy,
        viewportWidth: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        // The bottom-anchor marker must be OUTSIDE the lazy container: inside a
        // LazyVStack it is not mounted until scrolled into view, so
        // `scrollTo(bottomAnchorID)` on the ↓ button could teleport BELOW the
        // real content — the "↓ ведёт ниже и виден чёрный экран" bug. A
        // non-lazy 1pt marker at the content's true end is always mounted and
        // always resolvable.
        VStack(spacing: 0) {
            // P0 ROOT CAUSE FIX (3.4.8): The LazyVStack + ForEach content is wrapped
            // in an EquatableView so scroll/composer state changes in ChatView do NOT
            // trigger Markdown re-layout for N visible rows. Without this, every scroll
            // owner change, composer height update, or near-bottom flip re-evaluated
            // ChatTranscriptView body → ForEach created N ChatTranscriptMessageBlock
            // structs → SwiftUICore re-laid-out all visible Markdown views → 2-4s freeze.
            // EquatableView prevents body re-evaluation when content inputs are stable.
            EquatableView(content: TranscriptMessageContent(
                displayedTranscriptMessages: displayedTranscriptMessages,
                compressionReferenceCard: compressionReferenceCard,
                reasoningGroups: reasoningGroups,
                completedToolCallGroupsForAnchor: completedToolCallGroupsForAnchor,
                liveReasoningText: liveReasoningText,
                reasoningAnchorMessageID: reasoningAnchorMessageID,
                liveToolCalls: liveToolCalls,
                toolCallAnchorMessageID: toolCallAnchorMessageID,
                streamingAssistantMessageID: streamingAssistantMessageID,
                liveTokensPerSecond: liveTokensPerSecond,
                activeStreamID: activeStreamID,
                localAttachmentPreviews: localAttachmentPreviews,
                listeningMessageID: listeningMessageID,
                isViewingCachedData: isViewingCachedData,
                isRegeneratingMessage: isRegeneratingMessage,
                isEditingMessage: isEditingMessage,
                isForkingMessage: isForkingMessage,
                showsThinkingAndToolCards: showsThinkingAndToolCards,
                showsCompressingStatus: showsCompressingStatus,
                transcriptBlockSpacing: transcriptBlockSpacing,
                transcriptMessageSpacing: transcriptMessageSpacing,
                actionContext: actionContext,
                shouldRenderMessageRow: shouldRenderMessageRow,
                loadAttachmentImage: loadAttachmentImage,
                loadAttachmentData: loadAttachmentData,
                loadTranscriptMediaImage: loadTranscriptMediaImage,
                loadTranscriptMediaData: loadTranscriptMediaData,
                transcriptMediaCacheNamespace: transcriptMediaCacheNamespace,
                onPreviewAttachment: onPreviewAttachment,
                onPreviewTranscriptMedia: onPreviewTranscriptMedia,
                onToggleListening: onToggleListening,
                onSelectText: onSelectText,
                onRegenerate: onRegenerate,
                onEdit: onEdit,
                onFork: onFork,
                onCopy: onCopy,
                onReply: onReply,
                onForward: onForward,
                onSave: onSave,
                onPin: onPin,
                isMessagePinned: isMessagePinned,
                olderMessagesButton: { proxy in
                    AnyView(olderMessagesButton(proxy: proxy))
                },
                liveResponseBlocks: AnyView(liveResponseBlocks),
                inlineClarificationCard: AnyView(inlineClarificationCard
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        onClarificationCardHeightChange(height)
                    }),
                typingIndicator: AnyView(typingIndicator),
                turnChangesCard: AnyView(turnChangesCard),
                inlineCommitButton: AnyView(inlineCommitButton),
                transcriptLooseBlocks: AnyView(transcriptLooseBlocks),
                bottomAnchorID: bottomAnchorID,
                compressionReferenceCardView: { card in AnyView(compressionReferenceCardView(card)) }
            ))

            Color.clear
                .frame(height: 1)
                .id(bottomAnchorID)
                .allowsHitTesting(false)
        }
        .padding(.top, 16)
        .frame(width: contentWidth, alignment: .leading)
        .padding(.horizontal, transcriptHorizontalPadding)
        .frame(width: viewportWidth, alignment: .leading)
        .clipped()
        .background {
            ZStack {
                ChatScrollObserver(
                    isStreaming: activeStreamID != nil,
                    prependScrollPositionController: prependScrollPositionController
                ) { metrics in
                    onUpdateScrollMetrics(metrics)
                }

                ChatVerticalScrollAxisGuard()

                // Opaque fill over the whole viewport so the area BELOW the
                // last mounted LazyVStack row (which stays unrendered during a
                // fast scroll-to-bottom) is the chat background instead of a
                // black gap — the black-screen-on-↓ regression.
                Color(.systemBackground)
            }
            .accessibilityHidden(true)
        }
    }

    private func compressionReferenceCardView(_ card: CompressionReferenceCard) -> some View {
        MarkerMessageCardView(kind: .compressionReference, content: card.referenceText)
    }

    private var transcriptHorizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 20 : 16
    }

    private func transcriptContentWidth(for viewportWidth: CGFloat) -> CGFloat {
        max(0, viewportWidth - (transcriptHorizontalPadding * 2))
    }

    @ViewBuilder
    private func olderMessagesButton(proxy: ScrollViewProxy) -> some View {
        if hasOlderMessages {
            LoadOlderMessagesButton(isLoading: isLoadingOlderMessages) {
                Task { await loadOlderMessagesPreservingPosition(proxy: proxy) }
            }
        }
    }

    private func loadOlderMessagesPreservingPosition(proxy: ScrollViewProxy) async {
        // Exact path first: snapshot the UIKit scroll geometry, prepend, then
        // offset by the net content-height growth. `ScrollViewProxy.scrollTo` to
        // a coarse anchor cannot preserve the reader's exact gap above the
        // previous first row, and a LazyVStack row that is not yet mounted makes
        // scrollTo silently a no-op — the "Load older does nothing" bug.
        let capturedExactPosition = prependScrollPositionController.capture()
        let identity = displayedTranscriptMessages.first?.id
        let didLoad = await onLoadOlderMessages()
        guard didLoad else {
            prependScrollPositionController.cancelPreservation()
            return
        }

        if capturedExactPosition,
           prependScrollPositionController.restoreAfterPrepend() {
            return
        }

        // Coarse fallback (user moved during the request, or the controller had
        // no scroll view). Snap, never animate: an animated ride down through
        // the lazy rows of a long transcript forces a re-layout of the markdown
        // tree on main — the same mechanism that rendered the black screen on ↓.
        guard let identity else { return }

        await Task.yield()
        proxy.scrollTo(identity, anchor: .top)
    }

    @ViewBuilder
    private var transcriptLooseBlocks: some View {
        reasoningBlocks(anchorMessageID: nil)
        toolCallGroups(anchorMessageID: nil)
    }

    @ViewBuilder
    private var liveResponseBlocks: some View {
        if activeStreamID != nil {
            if showsThinkingAndToolCards {
                if hasLiveReasoningText,
                   !hasDisplayedTranscriptMessage(anchorID: reasoningAnchorMessageID) {
                    ReasoningBlockView(text: liveReasoningText)
                }

                if !liveToolCalls.isEmpty,
                   !hasDisplayedTranscriptMessage(anchorID: toolCallAnchorMessageID) {
                    ToolActivityGroupView(
                        group: ToolCallGroup.live(
                            anchorMessageID: toolCallAnchorMessageID,
                            toolCalls: liveToolCalls
                        )
                    )
                }
            }

            if activeStreamRecoveryState != .idle {
                StreamRecoveryStatusView(state: activeStreamRecoveryState)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(hidesRunStatusAccessibility)
                    .transition(ChatMotion.bottomOverlayTransition(reduceMotion: reduceMotion))
            }
        }
    }

    @ViewBuilder
    private var inlineClarificationCard: some View {
        if let clarificationPrompt {
            ClarificationRequestCard(
                prompt: clarificationPrompt,
                isResponding: isRespondingToClarification,
                errorMessage: clarificationErrorMessage,
                onSubmit: onSubmitClarification
            )
            .id(clarificationPrompt.id)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(ChatMotion.bottomOverlayTransition(reduceMotion: reduceMotion))
        }
    }

    @ViewBuilder
    private var typingIndicator: some View {
        if showsCompressingStatus {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Сжимаю контекст…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(hidesRunStatusAccessibility)
            .transition(.opacity)
        } else if showsAssistantTypingIndicator {
            AssistantTypingIndicatorView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(hidesRunStatusAccessibility)
        }
    }

    @ViewBuilder
    private var turnChangesCard: some View {
        if let summary = turnChangesSummary {
            GitTurnChangesCard(
                summary: summary,
                onOpenAll: onOpenTurnDiff,
                onOpenFile: onOpenTurnFileDiff
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var inlineCommitButton: some View {
        if let context = inlineCommitContext {
            GitInlineCommitButton(
                runningPhase: context.runningPhase,
                isDisabled: context.isDisabled,
                action: onInlineCommit
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
    }

    private var hasLiveReasoningText: Bool {
        !liveReasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hasDisplayedTranscriptMessage(anchorID: String?) -> Bool {
        guard let anchorID else { return false }

        return displayedTranscriptMessages.contains { $0.anchorID == anchorID }
    }

    @ViewBuilder
    private func reasoningBlocks(anchorMessageID: String?) -> some View {
        if showsThinkingAndToolCards {
            ForEach(reasoningGroups.filter { $0.anchorMessageID == anchorMessageID }) { group in
                ReasoningBlockView(text: group.text)
            }
        }
    }

    @ViewBuilder
    private func toolCallGroups(anchorMessageID: String?) -> some View {
        if showsThinkingAndToolCards {
            ForEach(completedToolCallGroupsForAnchor(anchorMessageID)) { group in
                ToolActivityGroupView(group: group)
            }
        }
    }
}

private struct ChatTranscriptMessageBlock: View, Equatable {
    let transcriptMessage: TranscriptMessage
    let transcriptBlockSpacing: CGFloat
    let showsThinkingAndToolCards: Bool
    let reasoningGroups: [ReasoningGroup]
    let toolCallGroups: [ToolCallGroup]
    let liveReasoningText: String
    let reasoningAnchorMessageID: String?
    let liveToolCalls: [ToolCall]
    let toolCallAnchorMessageID: String?
    let streamingAssistantMessageID: String?
    let liveTokensPerSecond: Double?
    let localAttachmentPreviews: [String: Data]?
    let listeningMessageID: String?
    let isViewingCachedData: Bool
    let hasActiveStream: Bool
    let isRegeneratingMessage: Bool
    let isEditingMessage: Bool
    let isForkingMessage: Bool
    let loadAttachmentImage: (String) async -> Data?
    let loadAttachmentData: (String) async -> Data?
    let loadTranscriptMediaImage: (TranscriptMediaReference) async -> Data?
    let loadTranscriptMediaData: (TranscriptMediaReference) async -> Data?
    let transcriptMediaCacheNamespace: String
    let actionContext: (ChatMessage, Int) -> MessageActionContext?
    let shouldRenderMessageRow: (ChatMessage) -> Bool
    let onPreviewAttachment: (MessageAttachment, Data?) -> Void
    let onPreviewTranscriptMedia: (TranscriptMediaReference) -> Void
    let onToggleListening: (MessageActionContext) -> Void
    let onSelectText: (MessageActionContext) -> Void
    let onRegenerate: (MessageActionContext) -> Void
    let onEdit: (MessageActionContext) -> Void
    let onFork: (MessageActionContext) -> Void
    let onCopy: (MessageActionContext) -> Void
    let onReply: (MessageActionContext) -> Void
    let onForward: (MessageActionContext) -> Void
    let onSave: (MessageActionContext) -> Void
    let onPin: ((MessageActionContext) -> Void)?
    let isMessagePinned: (String) -> Bool

    // Equality over the value inputs only. The closures are pure functions of
    // these values (e.g. `actionContext` is fully determined by
    // `transcriptMessage`), so two blocks that compare equal render identically.
    // This lets `.equatable()` skip re-evaluating rows whose data is unchanged
    // even though their closure props are recreated on every parent body pass.
    static func == (lhs: ChatTranscriptMessageBlock, rhs: ChatTranscriptMessageBlock) -> Bool {
        lhs.transcriptMessage == rhs.transcriptMessage &&
            lhs.transcriptBlockSpacing == rhs.transcriptBlockSpacing &&
            lhs.showsThinkingAndToolCards == rhs.showsThinkingAndToolCards &&
            // P0 (3.3.3): `hasActiveStream` — GLOBAL per-row flip on send →
            // all N rows re-evaluate. Excluded: streaming row already gates
            // on streamingAssistantMessageID + changing content.
            //
            // P0 (3.4.5): `reasoningGroups` + `toolCallGroups` — GLOBAL arrays
            // that change when any tool call / reasoning block updates. For
            // settled rows (non-anchor) these are always empty []. Including
            // them in equatable meant a single tool-call completion re-evaluated
            // ALL N rows → Markdown → AttributeGraph layout → freeze. The anchor
            // row already re-evaluates via streamingAssistantMessageID + changing
            // content; non-anchor rows never render reasoning/tool blocks.
            lhs.liveReasoningText == rhs.liveReasoningText &&
            lhs.reasoningAnchorMessageID == rhs.reasoningAnchorMessageID &&
            lhs.liveToolCalls == rhs.liveToolCalls &&
            lhs.toolCallAnchorMessageID == rhs.toolCallAnchorMessageID &&
            lhs.streamingAssistantMessageID == rhs.streamingAssistantMessageID &&
            lhs.liveTokensPerSecond == rhs.liveTokensPerSecond &&
            lhs.localAttachmentPreviews == rhs.localAttachmentPreviews &&
            lhs.listeningMessageID == rhs.listeningMessageID &&
            lhs.isViewingCachedData == rhs.isViewingCachedData &&
            lhs.isRegeneratingMessage == rhs.isRegeneratingMessage &&
            lhs.isEditingMessage == rhs.isEditingMessage &&
            lhs.isForkingMessage == rhs.isForkingMessage &&
            lhs.transcriptMediaCacheNamespace == rhs.transcriptMediaCacheNamespace
    }

    var body: some View {
        VStack(alignment: .leading, spacing: transcriptBlockSpacing) {
            reasoningBlocks
            liveReasoningBlock
            toolActivityGroups
            liveToolActivityGroup

            if shouldRenderMessageRow(transcriptMessage.message) {
                ChatTranscriptMessageRow(
                    message: transcriptMessage.message,
                    visibleIndex: transcriptMessage.loadedIndex,
                    actionContext: actionContext(transcriptMessage.message, transcriptMessage.loadedIndex),
                    localAttachmentPreviews: localAttachmentPreviews,
                    listeningMessageID: listeningMessageID,
                    isViewingCachedData: isViewingCachedData,
                    hasActiveStream: hasActiveStream,
                    isStreaming: ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
                        hasActiveStream: hasActiveStream,
                        messageRole: transcriptMessage.message.role,
                        messageID: transcriptMessage.message.messageId,
                        streamingAssistantMessageID: streamingAssistantMessageID
                    ),
                    liveTokensPerSecond: liveTokensPerSecond,
                    isRegeneratingMessage: isRegeneratingMessage,
                    isEditingMessage: isEditingMessage,
                    isForkingMessage: isForkingMessage,
                    loadAttachmentImage: loadAttachmentImage,
                    loadAttachmentData: loadAttachmentData,
                    loadTranscriptMediaImage: loadTranscriptMediaImage,
                    loadTranscriptMediaData: loadTranscriptMediaData,
                    transcriptMediaCacheNamespace: transcriptMediaCacheNamespace,
                    onPreviewAttachment: onPreviewAttachment,
                    onPreviewTranscriptMedia: onPreviewTranscriptMedia,
                    onToggleListening: onToggleListening,
                    onSelectText: onSelectText,
                    onRegenerate: onRegenerate,
                    onEdit: onEdit,
                    onFork: onFork,
                    onCopy: onCopy,
                    onReply: onReply,
                    onForward: onForward,
                    onSave: onSave,
                    onPin: onPin,
                    isMessagePinned: isMessagePinned
                )
            }
        }
    }

    @ViewBuilder
    private var reasoningBlocks: some View {
        if showsThinkingAndToolCards {
            ForEach(reasoningGroups.filter { $0.anchorMessageID == transcriptMessage.anchorID }) { group in
                ReasoningBlockView(text: group.text)
            }
        }
    }

    @ViewBuilder
    private var liveReasoningBlock: some View {
        if shouldRenderLiveReasoningBlock {
            ReasoningBlockView(text: liveReasoningText)
        }
    }

    @ViewBuilder
    private var toolActivityGroups: some View {
        if showsThinkingAndToolCards {
            ForEach(toolCallGroups) { group in
                ToolActivityGroupView(group: group)
            }
        }
    }

    @ViewBuilder
    private var liveToolActivityGroup: some View {
        if shouldRenderLiveToolActivityGroup {
            ToolActivityGroupView(
                group: ToolCallGroup.live(
                    anchorMessageID: toolCallAnchorMessageID,
                    toolCalls: liveToolCalls
                )
            )
        }
    }

    private var shouldRenderLiveReasoningBlock: Bool {
        hasActiveStream &&
            showsThinkingAndToolCards &&
            reasoningAnchorMessageID == transcriptMessage.anchorID &&
            !liveReasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldRenderLiveToolActivityGroup: Bool {
        hasActiveStream &&
            showsThinkingAndToolCards &&
            toolCallAnchorMessageID == transcriptMessage.anchorID &&
            !liveToolCalls.isEmpty
    }
}

private struct ChatTranscriptMessageRow: View {
    let message: ChatMessage
    let visibleIndex: Int
    let actionContext: MessageActionContext?
    let localAttachmentPreviews: [String: Data]?
    let listeningMessageID: String?
    let isViewingCachedData: Bool
    let hasActiveStream: Bool
    let isStreaming: Bool
    let liveTokensPerSecond: Double?
    let isRegeneratingMessage: Bool
    let isEditingMessage: Bool
    let isForkingMessage: Bool
    let loadAttachmentImage: (String) async -> Data?
    let loadAttachmentData: (String) async -> Data?
    let loadTranscriptMediaImage: (TranscriptMediaReference) async -> Data?
    let loadTranscriptMediaData: (TranscriptMediaReference) async -> Data?
    let transcriptMediaCacheNamespace: String
    let onPreviewAttachment: (MessageAttachment, Data?) -> Void
    let onPreviewTranscriptMedia: (TranscriptMediaReference) -> Void
    let onToggleListening: (MessageActionContext) -> Void
    let onSelectText: (MessageActionContext) -> Void
    let onRegenerate: (MessageActionContext) -> Void
    let onEdit: (MessageActionContext) -> Void
    let onFork: (MessageActionContext) -> Void
    let onCopy: (MessageActionContext) -> Void
    let onReply: (MessageActionContext) -> Void
    let onForward: (MessageActionContext) -> Void
    let onSave: (MessageActionContext) -> Void
    let onPin: ((MessageActionContext) -> Void)?
    let isMessagePinned: (String) -> Bool

    var body: some View {
        // Compaction marker messages render as collapsible cards (matching the
        // web UI), never as user bubbles — and without bubble actions, which
        // don't apply to system-emitted markers.
        if let markerKind = ChatMarkerMessageClassifier.classify(message) {
            MarkerMessageCardView(kind: markerKind, content: message.content)
        } else if let actionContext {
            bubble
                .contentShape(Rectangle())
                .contextMenu {
                    ChatMessageActionMenu(
                        context: actionContext,
                        listeningMessageID: listeningMessageID,
                        isViewingCachedData: isViewingCachedData,
                        hasActiveStream: hasActiveStream,
                        isRegeneratingMessage: isRegeneratingMessage,
                        isEditingMessage: isEditingMessage,
                        isForkingMessage: isForkingMessage,
                        onToggleListening: onToggleListening,
                        onSelectText: onSelectText,
                        onRegenerate: onRegenerate,
                        onEdit: onEdit,
                        onFork: onFork,
                        onCopy: onCopy,
                        onReply: onReply,
                        onForward: onForward,
                        onSave: onSave,
                        onPin: onPin,
                        isPinned: isMessagePinned(message.id)
                    )
                }
        } else {
            bubble
        }
    }

    @ViewBuilder
    private var bubble: some View {
        // P0 freeze (verified driver: every incoming token changes
        // `message.content`, breaks `ChatTranscriptMessageBlock.Equatable`, and
        // forces a full transcript re-layout on the main thread — the
        // `AttributeGraph + LayoutProxy.dimensions` dead-freeze family, freezes
        // of 5+s that need a force-quit). While the assistant message is still
        // streaming we render a STABLE typing indicator instead of the growing
        // `MessageBubbleView`, so the row (and the transcript layout) never
        // re-lays-out per token. The full formatted answer renders ONCE on
        // stream completion (`isStreaming` → false), matching the
        // "don't stream — deliver when ready" decision.
        if isStreaming {
            // P0 (3.4.2→3.4.6): replaced AssistantTypingIndicatorView with
            // LightStreamingRenderer — plain Text(verbatim:) O(1) per token.
            // The user sees text appearing in real-time during streaming instead
            // of static dots. Markdown formatting appears once the stream settles
            // (isStreaming → false → MessageBubbleView → MarkdownRenderer).
            // Equatable fixes (3.3.3 hasActiveStream, 3.4.6 toolCallGroups) ensure
            // settled rows skip re-evaluation even as the streaming row updates.
            LightStreamingRenderer(content: message.content ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        } else {
            MessageBubbleView(
                message: message,
                loadAttachmentImage: loadAttachmentImage,
                loadAttachmentData: loadAttachmentData,
                loadTranscriptMediaImage: loadTranscriptMediaImage,
                loadTranscriptMediaData: loadTranscriptMediaData,
                transcriptMediaCacheNamespace: transcriptMediaCacheNamespace,
                localAttachmentPreviews: localAttachmentPreviews,
                onPreviewAttachment: onPreviewAttachment,
                onPreviewTranscriptMedia: onPreviewTranscriptMedia,
                isStreaming: isStreaming,
                liveTokensPerSecond: liveTokensPerSecond
            )
        }
    }
}

private struct ChatScrollToBottomButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let bottomPadding: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(.primary)
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
        .padding(.bottom, bottomPadding)
        .accessibilityLabel("Scroll to latest message")
    }
}

private struct LoadOlderMessagesButton: View {
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }

                Text(isLoading ? String(localized: "Loading older messages") : String(localized: "Load older messages"))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color(.separator).opacity(0.32), lineWidth: 0.5)
            )
        }
        .buttonStyle(.chatTactile(.capsule))
        .disabled(isLoading)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(isLoading ? String(localized: "Loading older messages") : String(localized: "Load older messages"))
    }
}\n

// MARK: - P0 ROOT CAUSE FIX (3.4.8): TranscriptMessageContent
// Extracted from ChatTranscriptView to prevent scroll/composer state changes
// from triggering N x Markdown re-layout. This struct receives ONLY content-
// relevant props and has custom Equatable that skips scroll/chrome fields.

private struct TranscriptMessageContent: View, Equatable {
    let displayedTranscriptMessages: [TranscriptMessage]
    let compressionReferenceCard: CompressionReferenceCard?
    let reasoningGroups: [ReasoningGroup]
    let completedToolCallGroupsForAnchor: (String?) -> [ToolCallGroup]
    let liveReasoningText: String
    let reasoningAnchorMessageID: String?
    let liveToolCalls: [ToolCall]
    let toolCallAnchorMessageID: String?
    let streamingAssistantMessageID: String?
    let liveTokensPerSecond: Double?
    let activeStreamID: String?
    let localAttachmentPreviews: [String: [String: Data]]
    let listeningMessageID: String?
    let isViewingCachedData: Bool
    let isRegeneratingMessage: Bool
    let isEditingMessage: Bool
    let isForkingMessage: Bool
    let showsThinkingAndToolCards: Bool
    let showsCompressingStatus: Bool
    let transcriptBlockSpacing: CGFloat
    let transcriptMessageSpacing: CGFloat
    let actionContext: (ChatMessage, Int) -> MessageActionContext?
    let shouldRenderMessageRow: (ChatMessage) -> Bool
    let loadAttachmentImage: (String) async -> Data?
    let loadAttachmentData: (String) async -> Data?
    let loadTranscriptMediaImage: (TranscriptMediaReference) async -> Data?
    let loadTranscriptMediaData: (TranscriptMediaReference) async -> Data?
    let transcriptMediaCacheNamespace: String
    let onPreviewAttachment: (MessageAttachment, Data?) -> Void
    let onPreviewTranscriptMedia: (TranscriptMediaReference) -> Void
    let onToggleListening: (MessageActionContext) -> Void
    let onSelectText: (MessageActionContext) -> Void
    let onRegenerate: (MessageActionContext) -> Void
    let onEdit: (MessageActionContext) -> Void
    let onFork: (MessageActionContext) -> Void
    let onCopy: (MessageActionContext) -> Void
    let onReply: (MessageActionContext) -> Void
    let onForward: (MessageActionContext) -> Void
    let onSave: (MessageActionContext) -> Void
    let onPin: ((MessageActionContext) -> Void)?
    let isMessagePinned: (String) -> Bool
    let olderMessagesButton: (ScrollViewProxy) -> AnyView
    let liveResponseBlocks: AnyView
    let inlineClarificationCard: AnyView
    let typingIndicator: AnyView
    let turnChangesCard: AnyView
    let inlineCommitButton: AnyView
    let transcriptLooseBlocks: AnyView
    let bottomAnchorID: String
    let compressionReferenceCardView: (CompressionReferenceCard) -> AnyView

    static func == (lhs: TranscriptMessageContent, rhs: TranscriptMessageContent) -> Bool {
        lhs.displayedTranscriptMessages == rhs.displayedTranscriptMessages &&
            lhs.compressionReferenceCard == rhs.compressionReferenceCard &&
            lhs.streamingAssistantMessageID == rhs.streamingAssistantMessageID &&
            lhs.activeStreamID == rhs.activeStreamID &&
            lhs.liveReasoningText == rhs.liveReasoningText &&
            lhs.reasoningAnchorMessageID == rhs.reasoningAnchorMessageID &&
            lhs.toolCallAnchorMessageID == rhs.toolCallAnchorMessageID &&
            lhs.isViewingCachedData == rhs.isViewingCachedData &&
            lhs.isRegeneratingMessage == rhs.isRegeneratingMessage &&
            lhs.isEditingMessage == rhs.isEditingMessage &&
            lhs.isForkingMessage == rhs.isForkingMessage &&
            lhs.listeningMessageID == rhs.listeningMessageID &&
            lhs.showsThinkingAndToolCards == rhs.showsThinkingAndToolCards &&
            lhs.showsCompressingStatus == rhs.showsCompressingStatus
    }

    var body: some View {
        LazyVStack(spacing: transcriptMessageSpacing) {
            olderMessagesButton

            if let compressionReferenceCard, compressionReferenceCard.afterRenderID == nil {
                compressionReferenceCardView(compressionReferenceCard)
            }

            ForEach(displayedTranscriptMessages) { transcriptMessage in
                let isReasoningAnchor = reasoningAnchorMessageID == transcriptMessage.anchorID
                let isToolCallAnchor = toolCallAnchorMessageID == transcriptMessage.anchorID
                let isStreamingRow = streamingAssistantMessageID != nil
                    && transcriptMessage.message.messageId == streamingAssistantMessageID

                ChatTranscriptMessageBlock(
                    transcriptMessage: transcriptMessage,
                    transcriptBlockSpacing: transcriptBlockSpacing,
                    showsThinkingAndToolCards: showsThinkingAndToolCards,
                    reasoningGroups: reasoningGroups,
                    toolCallGroups: completedToolCallGroupsForAnchor(transcriptMessage.anchorID),
                    liveReasoningText: isReasoningAnchor ? liveReasoningText : "",
                    reasoningAnchorMessageID: isReasoningAnchor ? reasoningAnchorMessageID : nil,
                    liveToolCalls: isToolCallAnchor ? liveToolCalls : [],
                    toolCallAnchorMessageID: isToolCallAnchor ? toolCallAnchorMessageID : nil,
                    streamingAssistantMessageID: isStreamingRow ? streamingAssistantMessageID : nil,
                    liveTokensPerSecond: isStreamingRow ? liveTokensPerSecond : nil,
                    localAttachmentPreviews: localAttachmentPreviews[transcriptMessage.message.id],
                    listeningMessageID: listeningMessageID,
                    isViewingCachedData: isViewingCachedData,
                    hasActiveStream: activeStreamID != nil,
                    isRegeneratingMessage: isRegeneratingMessage,
                    isEditingMessage: isEditingMessage,
                    isForkingMessage: isForkingMessage,
                    loadAttachmentImage: loadAttachmentImage,
                    loadAttachmentData: loadAttachmentData,
                    loadTranscriptMediaImage: loadTranscriptMediaImage,
                    loadTranscriptMediaData: loadTranscriptMediaData,
                    transcriptMediaCacheNamespace: transcriptMediaCacheNamespace,
                    actionContext: actionContext,
                    shouldRenderMessageRow: shouldRenderMessageRow,
                    onPreviewAttachment: onPreviewAttachment,
                    onPreviewTranscriptMedia: onPreviewTranscriptMedia,
                    onToggleListening: onToggleListening,
                    onSelectText: onSelectText,
                    onRegenerate: onRegenerate,
                    onEdit: onEdit,
                    onFork: onFork,
                    onCopy: onCopy,
                    onReply: onReply,
                    onForward: onForward,
                    onSave: onSave,
                    onPin: onPin,
                    isMessagePinned: isMessagePinned
                )
                .equatable()
                .id(transcriptMessage.id)

                if let compressionReferenceCard,
                   compressionReferenceCard.afterRenderID == transcriptMessage.renderID {
                    compressionReferenceCardView(compressionReferenceCard)
                }
            }

            transcriptLooseBlocks
            liveResponseBlocks
            inlineClarificationCard
            typingIndicator
            turnChangesCard
            inlineCommitButton
        }

        Color.clear
            .frame(height: 1)
            .id(bottomAnchorID)
            .allowsHitTesting(false)
    }
}

