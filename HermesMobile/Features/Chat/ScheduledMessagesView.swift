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

    /// Show ALL scheduled messages (no sessionId filter). Used from Tasks / Chat button.
    init(onSendNow: @escaping (String) -> Void) {
        self.sessionId = ""
        self.onSendNow = onSendNow
        _messages = Query(sort: \.scheduledAt)
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
                                sessionTitle: msg.sessionTitle,
                                sessionId: msg.sessionId,
                                scheduleKey: msg.scheduleKey,
                                serverURLString: msg.serverURLString,
                                scheduledAt: msg.scheduledAt,
                                onSendNow: { onSendNow(msg.draftText) },
                                onDelete: {
                                    modelContext.delete(msg)
                                    Task.detached(priority: .background) {
                                        await deleteScheduledFromServer(
                                            scheduleKey: msg.scheduleKey,
                                            serverURLString: msg.serverURLString
                                        )
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Scheduled")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func deleteScheduledFromServer(scheduleKey: String, serverURLString: String) async {
        guard !serverURLString.isEmpty,
              let serverURL = URL(string: serverURLString) else { return }
        let webhookURL = serverURL.appendingPathComponent("webhook/scheduled-messages")
        let body = ["scheduleKey": scheduleKey]
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[ScheduledMessage] deleted from server: \(scheduleKey)")
            }
        } catch {
            print("[ScheduledMessage] delete sync error: \(error.localizedDescription)")
        }
    }
}

private struct ScheduledMessageRow: View {
    let text: String
    let sessionTitle: String?
    let sessionId: String
    let scheduleKey: String
    let serverURLString: String
    let scheduledAt: Date
    let onSendNow: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = sessionTitle, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            Text(text)
                .font(.subheadline)
                .lineLimit(3)

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
