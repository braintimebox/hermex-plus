import SwiftUI

/// The Bot editor and mention panel, with only the controls rooms support.
struct BotRoomComposerView: View {
    @Bindable var reader: BotRoomReader
    var threadID: String? = nil
    let roster: [BotProfile]
    let avatars: [String: UIImage]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HeaderLogoColor.storageKey) private var themeHex = HeaderLogoColor.defaultHex
    @AppStorage(PrimaryActionTintSettings.isEnabledKey) private var tintsPrimaryActions = false
    @AppStorage(AppHaptics.isEnabledKey) private var isHapticsEnabled = true
    @State private var selection = ComposerSelection()
    @State private var focused = false
    @State private var inputHeight: CGFloat = 22
    @State private var measuredHeight: CGFloat = 0
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
                        onPasteFileProviders: { _ in }, onPasteFileURLs: { _ in },
                        onPasteImageProviders: { _ in }, onPasteImages: { _ in },
                        onTapChip: { _ in }, onTapQuote: { _ in }, onRemoveQuote: { _ in },
                        placeholder: threadID == nil ? String(localized: "Message \(reader.room.name)") : String(localized: "Reply in thread"), acceptsAttachments: false
                    )
                    actionButton
                }
                .padding(ChatComposerMetrics.pillInset)
                .modifier(ChatComposerSurfaceStyle(isExpanded: focused))
            }
        }
        // Same geometry as the regular chat and the bot: horizontal 16, no bottom
        // inset. The 8 points kept the glass surface off the bottom edge and let
        // the transcript show through the strip underneath it.
        .padding(.horizontal, 16)
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
    }

    private func send() { Task { await reader.send(threadID: threadID) } }
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
