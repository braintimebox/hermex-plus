import SwiftUI
import UIKit

struct SelectableTextPresentation: Identifiable, Equatable {
    let id: String
    let text: String

    init(id: String, text: String) {
        self.id = id
        self.text = text
    }

    init(context: MessageActionContext) {
        self.init(id: context.messageID, text: context.copyText)
    }
}

/// One entry of the message action menu. The SwiftUI menu and the UIKit
/// context-menu interaction both build from this list so they never drift.
struct ChatMessageActionItem: Identifiable {
    enum Kind: String {
        case listen
        case regenerate
        case edit
        case fork
        case copy
        case selectText
        case reply
        case forward
        case save
        case pin
    }

    let kind: Kind
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let perform: () -> Void

    var id: Kind { kind }
}

struct ChatMessageActionMenu: View {
    let context: MessageActionContext
    let listeningMessageID: String?
    let isViewingCachedData: Bool
    let hasActiveStream: Bool
    let isRegeneratingMessage: Bool
    let isEditingMessage: Bool
    let isForkingMessage: Bool
    let onToggleListening: (MessageActionContext) -> Void
    let onRegenerate: (MessageActionContext) -> Void
    let onEdit: (MessageActionContext) -> Void
    let onFork: (MessageActionContext) -> Void
    let onCopy: (MessageActionContext) -> Void
    let onSelectText: ((MessageActionContext) -> Void)?
    let onReply: (MessageActionContext) -> Void
    let onForward: (MessageActionContext) -> Void
    let onSave: (MessageActionContext) -> Void
    let onPin: ((MessageActionContext) -> Void)?
    let isPinned: Bool

    var body: some View {
        ForEach(items) { item in
            Button {
                item.perform()
            } label: {
                Label(item.title, systemImage: item.systemImage)
            }
            .disabled(!item.isEnabled)
        }
    }

    /// The actions for this message in display order. Mutating actions are
    /// disabled while the transcript is cached or a stream is active.
    var items: [ChatMessageActionItem] {
        var items: [ChatMessageActionItem] = []

        if context.role == .assistant {
            items.append(ChatMessageActionItem(
                kind: .listen,
                title: isListening ? String(localized: "Stop Listening") : String(localized: "Listen"),
                systemImage: isListening ? "speaker.slash" : "speaker.wave.2",
                isEnabled: true,
                perform: { onToggleListening(context) }
            ))
            items.append(ChatMessageActionItem(
                kind: .regenerate,
                title: String(localized: "Regenerate Response"),
                systemImage: "arrow.clockwise",
                isEnabled: !(isViewingCachedData || hasActiveStream || isRegeneratingMessage),
                perform: { onRegenerate(context) }
            ))
        }

        if context.role == .user {
            items.append(ChatMessageActionItem(
                kind: .edit,
                title: String(localized: "Edit Message"),
                systemImage: "pencil",
                isEnabled: !(isViewingCachedData || hasActiveStream || isEditingMessage),
                perform: { onEdit(context) }
            ))
        }

        items.append(ChatMessageActionItem(
            kind: .fork,
            title: String(localized: "Fork From Here"),
            systemImage: "arrow.triangle.branch",
            isEnabled: !(isViewingCachedData || hasActiveStream || isForkingMessage),
            perform: { onFork(context) }
        ))
        // HERMEX-FORK: Copy restored for every role. Upstream 1.6.0's rework of
        // this menu scoped the Copy item to `context.role == .user`, so assistant
        // replies lost their only copy path: the meta-row copy button renders
        // only in the branch where there is no action context, and assistant
        // messages always have one. In v3.6.0 (pre-sync) Copy was unconditional —
        // this returns it. Gate 16 could not catch this: the callback is called,
        // the role condition is what disappeared.
        items.append(ChatMessageActionItem(
            kind: .copy,
            title: String(localized: "Copy"),
            systemImage: "doc.on.doc",
            isEnabled: true,
            perform: { onCopy(context) }
        ))

        if let onSelectText {
            items.append(ChatMessageActionItem(
                kind: .selectText,
                title: String(localized: "Select Text"),
                systemImage: "text.cursor",
                isEnabled: true,
                perform: { onSelectText(context) }
            ))
        }
        items.append(ChatMessageActionItem(
            kind: .reply,
            title: String(localized: "Reply"),
            systemImage: "arrowshape.turn.up.left",
            isEnabled: !(isViewingCachedData || hasActiveStream),
            perform: { onReply(context) }
        ))
        items.append(ChatMessageActionItem(
            kind: .forward,
            title: String(localized: "Forward"),
            systemImage: "arrowshape.turn.up.right",
            isEnabled: !(isViewingCachedData || hasActiveStream),
            perform: { onForward(context) }
        ))
        items.append(ChatMessageActionItem(
            kind: .save,
            title: String(localized: "Save"),
            systemImage: "bookmark",
            isEnabled: !(isViewingCachedData || hasActiveStream),
            perform: { onSave(context) }
        ))
        if let onPin {
            items.append(ChatMessageActionItem(
                kind: .pin,
                title: isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                systemImage: isPinned ? "pin.slash" : "pin",
                isEnabled: !(isViewingCachedData || hasActiveStream),
                perform: { onPin(context) }
            ))
        }

        return items
    }

    /// The same actions as a UIKit menu, for `ChatMessageContextMenuView`.
    func uiMenu() -> UIMenu {
        UIMenu(children: items.map { item in
            let action = UIAction(
                title: item.title,
                image: UIImage(systemName: item.systemImage)
            ) { _ in
                item.perform()
            }
            if !item.isEnabled {
                action.attributes = .disabled
            }
            return action
        })
    }

    private var isListening: Bool {
        listeningMessageID == context.messageID
    }
}

struct SelectableTextPresentationView: View {
    let selection: SelectableTextPresentation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: selection.text)
                .accessibilityIdentifier("selectable-response-text")
                .background(Color(.systemBackground))
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .systemBackground
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        // A wrapped UITextView does not inherit SwiftUI's layoutDirection; `.natural`
        // lets each paragraph align by its own writing direction so RTL message text
        // reads right-aligned while LTR stays left-aligned (issue #294).
        textView.textAlignment = .natural
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 32, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
    }
}

struct EditMessageSheet: View {
    @Environment(\.dismiss) private var dismiss

    let originalText: String
    @Binding var editDraft: String
    let onSubmit: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $editDraft)
                    .font(.body)
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Edit Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        dismiss()
                        onSubmit()
                    }
                    .disabled(editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .adaptiveFormPresentation()
    }
}
