import SwiftUI
import SwiftData

struct ScheduledMessagesView: View {
    @Environment(\.modelContext) private var modelContext

    let sessionId: String
    let onSendNow: (String) -> Void

    @Query private var messages: [PendingScheduledMessage]

    init(sessionId: String, onSendNow: @escaping (String) -> Void) {
        self.sessionId = sessionId
        self.onSendNow = onSendNow
        let predicate = #Predicate<PendingScheduledMessage> { $0.sessionId == sessionId }
        _messages = Query(filter: predicate, sort: \.scheduledAt)
    }

    var body: some View {
        NavigationStack {
            Group {
                if messages.isEmpty {
                    ContentUnavailableView(
                        "No Scheduled Messages",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Long-press the send button and pick a delivery time.")
                    )
                } else {
                    List {
                        ForEach(messages) { msg in
                            ScheduledMessageRow(
                                text: msg.draftText,
                                scheduledAt: msg.scheduledAt,
                                onSendNow: { onSendNow(msg.draftText) },
                                onDelete: { modelContext.delete(msg) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Scheduled")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ScheduledMessageRow: View {
    let text: String
    let scheduledAt: Date
    let onSendNow: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.subheadline)
                .lineLimit(2)

            Text("Scheduled for \(scheduledAt, style: .date) at \(scheduledAt, style: .time)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Send Now") { onSendNow() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Delete", role: .destructive) { onDelete() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
