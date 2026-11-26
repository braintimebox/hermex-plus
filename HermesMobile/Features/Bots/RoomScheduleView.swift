import SwiftUI
import SwiftData

/// The room's scheduled sends, and the ones that did not go out.
///
/// A scheduled message that failed is not a notification the user can act on: it is a
/// row that has to say what happened and offer the two things that make sense — try
/// again, or give up. Both live here, on the same screen as the pending list, because
/// "it will send later" and "it did not send" are the same subject.
struct RoomScheduleView: View {
    let room: BotRoomKey
    let roomName: String
    let serverURLString: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [PendingScheduledMessage] = []

    var body: some View {
        List {
            if rows.isEmpty {
                ContentUnavailableView(
                    "Nothing scheduled",
                    systemImage: "calendar",
                    description: Text("Long-press Send → Schedule Message.")
                )
            }
            ForEach(rows, id: \.scheduleKey) { row in
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.draftText).lineLimit(3)
                        Text(row.scheduledAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        if let reason = row.terminalFailureReason {
                            Label {
                                Text(reason)
                            } icon: {
                                Image(systemName: "exclamationmark.circle.fill")
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                        } else if row.failedAttemptCount > 0 {
                            Text("\(row.failedAttemptCount) attempt(s) failed; it will be retried.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        RoomScheduleQueue.remove(row, in: context)
                        reload()
                    }
                    if row.isDeliveryTerminal {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            // Same row, same event id: a retry must not become a second message.
                            row.terminalFailureReason = nil
                            row.terminalFailureAt = nil
                            row.scheduledAt = Date()
                            try? context.save()
                            reload()
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Scheduled")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
        }
        .task { reload() }
    }

    private func reload() {
        rows = RoomScheduleQueue.pending(room: room, in: context)
    }
}
