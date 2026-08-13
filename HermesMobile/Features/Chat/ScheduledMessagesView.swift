import SwiftUI
import SwiftData

struct ScheduledMessagesView: View {
    @Environment(\.modelContext) private var modelContext

    let sessionId: String
    let onSendNow: (PendingScheduledMessage) async -> Void

    @State private var messages: [PendingScheduledMessage] = []
    @State private var isLoading = true
    /// Guards against double-tapping "Send Now" while a send is in flight —
    /// every extra tap used to re-send the same message (12 taps = 12 sends).
    @State private var isSending = false

    /// Show ALL scheduled messages (no sessionId filter). Used from Tasks / Chat button.
    init(onSendNow: @escaping (PendingScheduledMessage) async -> Void) {
        self.sessionId = ""
        self.onSendNow = onSendNow
    }

    init(sessionId: String, onSendNow: @escaping (PendingScheduledMessage) async -> Void) {
        self.sessionId = sessionId
        self.onSendNow = onSendNow
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if messages.isEmpty {
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
                            isSending: isSending,
                            onSendNow: {
                                guard !isSending else { return }
                                isSending = true
                                Task {
                                    await onSendNow(msg)
                                    await loadMessages()
                                    isSending = false
                                }
                            },
                            onDelete: {
                                deleteLocal(msg)
                                Task {
                                    await deleteScheduledFromServer(msg: msg)
                                    await loadMessages()
                                }
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("Scheduled")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMessages()
        }
        .onAppear {
            MainThreadWatchdog.shared.setScreen("ScheduledMessages")
            HermexLogger.shared.log(type: "event", screen: "ScheduledMessages", message: "scheduled list opened")
        }
    }

    /// Fetch off the main thread. The main ModelContext can be busy autosaving
    /// streamed chat rows; a synchronous fetch on the main actor blocked the UI
    /// for 3-4s every time the page opened (confirmed by freeze diagnostics on
    /// v1.4.5: "scheduled list opened → main thread blocked 3s"). The heavy work
    /// runs on a detached context; only the handful of IDs come back, and the
    /// models are re-resolved on the main context so row actions (delete) work.
    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        let container = modelContext.container
        let filter = sessionId
        let ids = await Task.detached(priority: .userInitiated) { () -> [PersistentIdentifier] in
            let ctx = ModelContext(container)
            let descriptor: FetchDescriptor<PendingScheduledMessage>
            if filter.isEmpty {
                descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.scheduledAt)])
            } else {
                descriptor = FetchDescriptor(
                    predicate: #Predicate<PendingScheduledMessage> { $0.sessionId == filter },
                    sortBy: [SortDescriptor(\.scheduledAt)]
                )
            }
            return (try? ctx.fetch(descriptor).map { $0.persistentModelID }) ?? []
        }.value
        messages = ids.compactMap { modelContext.model(for: $0) as? PendingScheduledMessage }
    }

    private func deleteLocal(_ msg: PendingScheduledMessage) {
        modelContext.delete(msg)
    }

    private func deleteScheduledFromServer(msg: PendingScheduledMessage) async {
        await PendingScheduledMessage.deleteFromServer(
            scheduleKey: msg.scheduleKey,
            serverURLString: msg.serverURLString
        )
    }
}

/// Shared server-side cleanup for scheduled messages. Cancels the timer on the
/// scheduled-endpoint server (DELETE /webhook/scheduled-messages) so a message
/// that was already sent manually ("Send Now") or by the client dispatch loop
/// is NOT re-sent automatically when its scheduled time arrives. Must be called
/// with SCALAR values — never pass a @Model object into an async helper that
/// outlives the delete.
extension PendingScheduledMessage {
    static func deleteFromServer(scheduleKey: String, serverURLString: String) async {
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
    let isSending: Bool
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
                    .disabled(isSending)

                Button("Delete", role: .destructive) { onDelete() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
