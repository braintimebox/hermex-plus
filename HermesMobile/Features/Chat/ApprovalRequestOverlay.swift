import SwiftUI
import UIKit

struct ApprovalRequestOverlay: View {
    let prompt: ApprovalPromptState
    let isResponding: Bool
    let errorMessage: String?
    let onChoice: (ApprovalChoice) -> Void
    let onSkipAll: () -> Void

    var body: some View {
        ZStack {
            // HERMEX-FORK: the full-screen scrim is gone. It hid the transcript
            // that gives the request its context, so a command had to be
            // approved without seeing what produced it. A clear, hit-test
            // transparent layer keeps the card centred over the same area while
            // leaving the conversation scrollable underneath.
            Color.clear
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                header
                details
                actions
            }
            .padding(16)
            .frame(maxWidth: 520, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
            .padding(.horizontal, 18)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 4) {
                Text("Approval required")
                    .font(.headline)

                Text("Pending approvals: \(prompt.pendingCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let description = nonEmpty(prompt.pending.description) {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let command = nonEmpty(prompt.pending.command) {
                // HERMEX-FORK: the command used to sit in a horizontal
                // ScrollView, so a long one could only be read by scrolling
                // sideways — which made "check it before approving" impossible
                // in practice. It now wraps, is clamped to a few lines by
                // default, and expands to the full text in place.
                ApprovalCommandBlock(command: command)
            }

            if !prompt.patternKeys.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pattern keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(prompt.patternKeys, id: \.self) { key in
                            Text(key)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
                        }
                    }
                }
            }

            if prompt.pendingCount > 1 {
                Text("1 of \(prompt.pendingCount) pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = nonEmpty(errorMessage) {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                approvalButton("Allow once", systemImage: "checkmark.circle.fill", choice: .once, prominent: true)
                approvalButton("Allow session", systemImage: "lock.open", choice: .session, prominent: false)
            }

            HStack(spacing: 8) {
                approvalButton("Always allow", systemImage: "star.fill", choice: .always, prominent: false)
                approvalButton("Deny", systemImage: "xmark.circle.fill", choice: .deny, prominent: false, role: .destructive)
            }

            Button {
                onSkipAll()
            } label: {
                Label("Skip all this session", systemImage: "bolt.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.chatDecision(.secondary))
            .disabled(isResponding)
        }
    }

    @ViewBuilder
    private func approvalButton(
        _ title: String,
        systemImage: String,
        choice: ApprovalChoice,
        prominent: Bool,
        role: ButtonRole? = nil
    ) -> some View {
        if prominent {
            Button(role: role) {
                onChoice(choice)
            } label: {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.chatDecision(.primary))
            .disabled(isResponding)
        } else {
            Button(role: role) {
                onChoice(choice)
            } label: {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.chatDecision(role == .destructive ? .destructive : .secondary))
            .disabled(isResponding)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

/// HERMEX-FORK: a pending command, readable at a glance and fully inspectable
/// before it is approved.
///
/// Collapsed it shows a few wrapped lines, which is what the eye needs to
/// recognise "this is the thing I asked for". Expanded it shows the whole
/// string with selection enabled, so a long pipeline or a heredoc can be
/// checked line by line. Nothing is ever hidden without a way to see it.
struct ApprovalCommandBlock: View {
    let command: String

    /// Lines shown while collapsed. Four keeps the card short enough that the
    /// decision buttons stay above the fold on a small phone, while still
    /// showing enough of a command to recognise it.
    private let collapsedLineLimit = 4

    @State private var isExpanded = false

    /// A command short enough to read whole needs no disclosure.
    private var isExpandable: Bool {
        command.count > 160 || command.contains("\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(command)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)

            if isExpandable {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(
                        isExpanded ? String(localized: "Show less") : String(localized: "Show full command"),
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isExpanded ? String(localized: "Show less") : String(localized: "Show full command"))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
        )
    }
}

struct ApprovalBypassStatusPill: View {
    var body: some View {
        Label("Approval bypass active", systemImage: "bolt.slash.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}
