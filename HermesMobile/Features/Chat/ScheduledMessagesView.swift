import SwiftUI
import SwiftData

struct ScheduledMessagesView: View {
    @Environment(\.modelContext) private var modelContext

    let sessionId: String
    let onSendNow: (PendingScheduledMessage) -> Void

    @State private var messages: [PendingScheduledMessage] = []
    @State private var isLoading = true

    /// Show ALL scheduled messages (no sessionId filter). Used from Tasks / Chat button.
    init(onSendNow: @escaping (PendingScheduledMessage) -> Void) {
        self.sessionId = ""
        self.onSendNow = onSendNow
    }

    init(sessionId: String, onSendNow: @escaping (PendingScheduledMessage) -> Void) {
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
                            onSendNow: { onSendNow(msg) },
                            onDelete: {
                                deleteLocal(msg)
                                Task { await deleteScheduledFromServer(msg: msg) }
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

    /// Fetch on the main actor AFTER the view has appeared, so opening the page
    /// never blocks on a synchronous SwiftData fetch (this was the 3-4s freeze
    /// when opening Tasks → Scheduled Messages).
    private func loadMessages() async {
        defer { isLoading = false }
        let descriptor: FetchDescriptor<PendingScheduledMessage>
        if sessionId.isEmpty {
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.scheduledAt)])
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PendingScheduledMessage> { $0.sessionId == sessionId },
                sortBy: [SortDescriptor(\.scheduledAt)]
            )
        }
        do {
            messages = try modelContext.fetch(descriptor)
        } catch {
            messages = []
        }
    }

    private func deleteLocal(_ msg: PendingScheduledMessage) {
        modelContext.delete(msg)
    }

    private func deleteScheduledFromServer(msg: PendingScheduledMessage) async {
        // Capture scalar values BEFORE any await — the model object must not
        // be touched from a background task after deletion.
        let scheduleKey = msg.scheduleKey
        let serverURLString = msg.serverURLString
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
