import SwiftUI
import UniformTypeIdentifiers

/// The Bot editor and mention panel, with only the controls rooms support.
struct BotRoomComposerView: View {
    @Bindable var reader: BotRoomReader
    var threadID: String? = nil
    let roster: [BotProfile]
    let avatars: [String: UIImage]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HeaderLogoColor.storageKey) private var themeHex = HeaderLogoColor.defaultHex
    @AppStorage(PrimaryActionTintSettings.isEnabledKey) private var tintsPrimaryActions = false
    @AppStorage(AppHaptics.isEnabledKey) private var isHapticsEnabled = true
    @State private var selection = ComposerSelection()
    @State private var focused = false
    @State private var inputHeight: CGFloat = 22
    @State private var measuredHeight: CGFloat = 0
    /// The schedule sheet: without an entry point the queue had no way in, and the calendar
    /// in the header showed a list nobody could add to.
    /// Files picked or pasted into this draft. Uploaded at send time, so a file that is
    /// removed from the draft never becomes a blob the room has to store.
    @State private var attachments: [RoomAttachmentUpload] = []
    @State private var attachmentNotice: String?
    @State private var isPickingAttachments = false
    @State private var isScheduling = false
    @State private var scheduledAt = Date().addingTimeInterval(3_600)
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 16

    var body: some View {
        AdaptiveGlassContainer(spacing: 6) {
            VStack(spacing: 8) {
                if focused, reader.mayEditDraft(in: threadID),
                   let trigger = BotMentionTrigger.detect(in: reader.draft(in: threadID), selection: selection.range) {
                    let completions = BotRoomMentions.completions(room: reader.room, query: trigger.query)
                    if !completions.isEmpty {
                        BotMentionAutocompleteView(completions: completions, avatars: avatars, room: reader.room, roster: roster) { item in
                            let result = trigger.applying(tag: item.tag, to: reader.draft(in: threadID))
                            reader.setDraft(result.draft, in: threadID)
                            selection = selection.moved(to: result.selection)
                            ChatHaptics.autocompleteAccepted(isEnabled: isHapticsEnabled)
                        }
                    }
                }
                HStack(spacing: 4) {
                    ComposerTextInputView(
                        text: Binding(get: { reader.draft(in: threadID) }, set: { reader.setDraft($0, in: threadID) }), selection: $selection, isFocused: $focused,
                        inputHeight: $inputHeight, measuredHeight: $measuredHeight,
                        isDisabled: !reader.mayEditDraft(in: threadID), isCollapsed: !focused,
                        isKeyboardSendEnabled: reader.maySend(in: threadID), verticalPadding: 6,
                        chipSkills: [], chipFilePaths: [], quotes: [], onKeyboardSend: send,
                        onPasteFileProviders: { providers in add(providers: providers) },
                        onPasteFileURLs: { urls in add(urls: urls) },
                        onPasteImageProviders: { providers in add(providers: providers) },
                        onPasteImages: { images in add(images: images) },
                        onTapChip: { _ in }, onTapQuote: { _ in }, onRemoveQuote: { _ in },
                        placeholder: threadID == nil ? String(localized: "Message \(reader.room.name)") : String(localized: "Reply in thread"), acceptsAttachments: true
                    )
                    if reader.showsComposer {
                        // The attach control sits next to Send, where the user already is
                        // when they decide a message needs a file.
                        Button { isPickingAttachments = true } label: {
                            Image(systemName: "paperclip")
                                .font(.system(size: 18, weight: .regular))
                                .frame(width: ChatComposerMetrics.actionSize)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Attach a file"))
                    }
                    actionButton
                }
                if !attachments.isEmpty || attachmentNotice != nil {
                    attachmentBudgetLine
                }
                .padding(ChatComposerMetrics.pillInset)
                .modifier(ChatComposerSurfaceStyle(isExpanded: focused))
            }
        }
        // Same geometry as the regular chat and the bot: horizontal 16, no bottom
        // inset. The 8 points kept the glass surface off the bottom edge and let
        // the transcript show through the strip underneath it.
        .padding(.horizontal, 16)
        .roomAttachmentPicker(isPresented: $isPickingAttachments) { urls in
            guard !urls.isEmpty else { return }
            add(urls: urls)
        }
    }

    /// Rooms send or stop, never both from one control: Stop lives in the top bar
    /// (room-level execution control), the composer only submits messages. While the
    /// group works this button stays Send, because `maySend` does not look at the
    /// room's execution status — the room accepts a message at any point.
    private var actionButton: some View {
        let enabled = reader.maySend(in: threadID)
        let appearance = ChatComposerActionAppearance(isStop: false, isDisabled: !enabled,
            colorScheme: colorScheme, tintsPrimaryActions: tintsPrimaryActions, themeHex: themeHex)
        return Button {
            send()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: iconSize, weight: .semibold))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(width: ChatComposerMetrics.actionSize)
            .frame(minHeight: ChatComposerMetrics.actionSize)
            .background(appearance.background).foregroundStyle(appearance.foreground).clipShape(Capsule())
        }
        .buttonStyle(.chatTactile(.icon)).disabled(!enabled)
        .accessibilityLabel(Text("Send"))
        // The same gesture the chat uses: long-press Send for "Schedule Message". It lives
        // on the send button because that is where the user already is when they decide the
        // message should go later.
        .contextMenu {
            if enabled {
                Button { send() } label: { Label("Send", systemImage: "arrow.up.circle.fill") }
                Button {
                    scheduledAt = Date().addingTimeInterval(3_600)
                    isScheduling = true
                } label: {
                    Label("Schedule Message", systemImage: "calendar.badge.plus")
                }
            }
        }
        .sheet(isPresented: $isScheduling) { scheduleSheet }
    }

    /// Date, time, and the one button that turns a draft into a queued message.
    private var scheduleSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Send at", selection: $scheduledAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    Text("The message leaves the queue when it is due and the app is running. It keeps its id, so a retry cannot post it twice.")
                }
            }
            .navigationTitle("Schedule Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isScheduling = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") { schedule() }
                        .disabled(!reader.maySend(in: threadID))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func schedule() {
        let text = reader.draft(in: threadID)
        RoomScheduleQueue.enqueue(
            room: reader.key,
            roomName: reader.room.name,
            threadID: threadID,
            text: text,
            dueAt: scheduledAt,
            serverURLString: reader.key.server.absoluteString,
            in: modelContext
        )
        reader.setDraft("", in: threadID)
        isScheduling = false
        ChatHaptics.autocompleteAccepted(isEnabled: isHapticsEnabled)
    }

    /// The budget the picker shows before anything is uploaded: the same numbers the refusal
    /// would use, so a file that will not fit is a sentence, not a failed send.
    private var attachmentBudgetLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let attachmentNotice {
                Text(attachmentNotice).font(.caption2).foregroundStyle(.red)
            }
            if !attachments.isEmpty {
                Text(budget.remainingSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var budget: RoomAttachmentBudget {
        var budget = RoomAttachmentBudget()
        for attachment in attachments { budget.append(attachment) }
        return budget
    }

    private func add(urls: [URL]) {
        attachmentNotice = nil
        var selection = budget
        for url in urls {
            // A URL from the system picker lives outside our sandbox: reading it needs the
            // security scope started, and the scope ends with this loop iteration.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try selection.add(contentsOf: url)
            } catch {
                attachmentNotice = error.localizedDescription
            }
        }
        attachments = selection.uploads
    }

    private func add(providers: [NSItemProvider]) {
        // A provider copies its file into our container asynchronously; the paste path keeps
        // that copy so the draft does not depend on the source app staying alive.
        attachmentNotice = nil
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, _ in
                guard let url else { return }
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(RoomAttachmentUpload.makeUploadID())
                    .appendingPathExtension(url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: copy)
                Task { @MainActor in add(urls: [copy]) }
            }
        }
    }

    private func add(images: [UIImage]) {
        // У вставленной картинки нет файла за спиной: пишем её в наш контейнер, чтобы
        // черновик не зависел от исходного приложения, и дальше идём общим путём add(urls:).
        attachmentNotice = nil
        for image in images {
            guard let data = image.pngData() else { continue }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(RoomAttachmentUpload.makeUploadID())
                .appendingPathExtension("png")
            do {
                try data.write(to: copy, options: .atomic)
            } catch {
                attachmentNotice = error.localizedDescription
                continue
            }
            add(urls: [copy])
        }
    }

    private func send() {
        guard attachments.isEmpty else {
            let files = attachments
            let text = reader.draft(in: threadID)
            attachments = []
            Task { await reader.send(text: text, threadID: threadID, attachments: files) }
            return
        }
        Task { await reader.send(threadID: threadID) }
    }
}

/// Room handles are server routing keys. Friendly names only help searching;
/// unlike Bot Chat, room sends must never append an identification annotation.
enum BotRoomMentions {
    static func completions(room: BotGroupRoom, query: String) -> [BotMentions.Completion] {
        let members = room.members.compactMap { member -> BotMentions.Completion? in
            guard let handle = member.handle, !handle.isEmpty,
                  let profile = BotProfile(.object(["name": .string(member.id), "display_name": .string(member.name)])) else { return nil }
            return BotMentions.Completion(profile: profile, tag: handle)
        }
        let everyone = ["all", "everyone"].compactMap { tag -> BotMentions.Completion? in
            guard let profile = BotProfile(.object(["name": .string("room-mention:" + tag),
                "display_name": .string(String(localized: "Everyone"))])) else { return nil }
            return BotMentions.Completion(profile: profile, tag: tag)
        }
        return Array((members + everyone).filter {
            query.isEmpty || $0.tag.localizedStandardContains(query) || $0.profile.name.localizedStandardContains(query)
        }.prefix(8))
    }
}

struct BotRoomActionCard: View {
    let reader: BotRoomReader
    let action: BotRoomAction
    var body: some View {
        if let approval = action.approval {
            BotPendingRequestCard(request: .approval(approval), identity: identity,
                isEnabled: reader.mayAct(action), canStop: reader.mayStop,
                isAnswering: reader.busy && reader.inactiveActions.contains(action.id), resolution: nil,
                onApprove: { choice in Task { await reader.act(action, choice: choice) } },
                onAnswer: { _ in }, onSkip: {}, onCredential: { _ in },
                onStop: { Task { await reader.stop() } }, onConnection: { _ in })
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(identity).font(.caption).foregroundStyle(.secondary)
                if action.isRetry {
                    Button("Retry") { Task { await reader.act(action) } }.disabled(!reader.mayAct(action))
                } else {
                    Label("Needs attention. Answer the request in Hermes Desktop on this same connection.", systemImage: "desktopcomputer")
                        .font(.callout)
                }
            }
            .padding(16).frame(maxWidth: 560, alignment: .leading)
            .pendingRequestCardSurface(cornerRadius: BotPendingRequestCard.cornerRadius)
        }
    }
    private var identity: String {
        let member = reader.room.members.first { $0.id == action.id.member }
        return [member?.name, reader.room.name, reader.connection.name].compactMap { $0 }.joined(separator: " · ")
    }
}
