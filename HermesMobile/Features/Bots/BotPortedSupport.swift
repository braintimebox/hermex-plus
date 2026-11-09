import Foundation
import SwiftUI

// MARK: - Send choice card

/// The card a busy composer shows instead of sending straight away: it lists
/// what a send can mean right now and hands the pick back to the caller.
///
/// The chat composer's own card lives upstream with its own layout; this one is
/// written for this fork so the Bots screens, which pass `BotPromptMode`, do not
/// have to reach into the chat layer for a view.
struct SendChoiceCard<Choice: SendChoice>: View {
    let choices: [Choice]
    let onPick: (Choice) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element) { index, choice in
                if index > 0 {
                    Divider()
                        .padding(.leading, 44)
                }
                Button {
                    onPick(choice)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: choice.systemImage)
                            .font(.body.weight(.medium))
                            .frame(width: 24)
                            .foregroundStyle(.tint)
                        Text(choice.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("send-choice-\(choice.title)")
            }
        }
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .shadow(radius: 12, y: 4)
        .onTapGesture { }          // swallow taps so the card never dismisses itself
        .accessibilityAddTraits(.isModal)
        .background(
            // A tap outside the card closes it without touching the keyboard.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
        )
    }
}

// MARK: - File path search

/// Debounced file-path lookups for the composer's `@` panel.
///
/// The chat layer's search knows how to talk to an API client; a bot conversation
/// answers through its own transport, so it hands this controller a closure and
/// the controller owns the cancellation and the latest-query-wins rule.
@MainActor
@Observable
final class BotFilePathSearchController {
    private(set) var matches: [ComposerFilePathSearch.Match] = []
    private(set) var isLoading = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func search(
        _ query: String,
        complete: @escaping (String) async throws -> [ComposerFilePathSearch.Match]
    ) {
        generation += 1
        let owner = generation
        task?.cancel()

        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            matches = []
            isLoading = false
            return
        }

        isLoading = true
        task = Task { [weak self] in
            do {
                let rows = try await complete(query)
                guard !Task.isCancelled, let self, owner == self.generation else { return }
                self.matches = rows
                self.isLoading = false
            } catch {
                guard let self, owner == self.generation else { return }
                self.matches = []
                self.isLoading = false
            }
        }
    }

    /// Forgets the rows: the workspace they described has moved.
    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        matches = []
        isLoading = false
    }
}

// MARK: - Approval scope

/// What an approval covers, in one line under its title.
///
/// The host names the subject (`toolName`, else `command`, else the rule key) and
/// what "Allow session" and "Always allow" would remember; this only phrases it.
enum ApprovalScope {
    /// The host whose approval this is. Only Hermes exists here; the case carries
    /// whether the two remember choices are on offer.
    enum Host: Equatable {
        case hermes(offersSession: Bool, offersAlways: Bool)
    }

    static func line(
        keys: [String],
        description: String?,
        command: String?,
        toolName: String?,
        host: Host
    ) -> AttributedString? {
        let subject = toolName ?? command ?? keys.first
        guard let subject, !subject.isEmpty else { return nil }

        var text = AttributedString(subject)
        text.font = .caption.monospaced()

        switch host {
        case let .hermes(offersSession, offersAlways):
            var suffix = ""
            if offersSession && offersAlways {
                suffix = " — session or always"
            } else if offersSession {
                suffix = " — this session"
            } else if offersAlways {
                suffix = " — always"
            }
            if !suffix.isEmpty {
                var tail = AttributedString(suffix)
                tail.font = .caption
                tail.foregroundColor = .secondary
                text.append(tail)
            }
        }

        if let description, !description.isEmpty, description != subject {
            var note = AttributedString(" \(description)")
            note.font = .caption
            note.foregroundColor = .secondary
            text.append(note)
        }

        return text
    }
}

// MARK: - Recall

/// The text the composer's up-arrow puts back: the last thing this conversation
/// sent, as the user typed it, never the attachment references the send appended.
enum ComposerRecall {
    static func lastSentText(in messages: [ChatMessage], typedText: (String) -> String) -> String? {
        for message in messages.reversed() where message.role == "user" {
            guard let content = message.content else { continue }
            let text = typedText(content)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }
}
