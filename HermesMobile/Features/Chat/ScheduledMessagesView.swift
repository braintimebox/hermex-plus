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
    /// Message currently being edited in the sheet.
    @State private var editingMessage: PendingScheduledMessage?

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
                            },
                            onEdit: {
                                editingMessage = msg
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
        .sheet(item: $editingMessage) { msg in
            EditScheduledMessageSheet(message: msg) {
                Task { await loadMessages() }
            }
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
        await reconcileWithServer()
    }

    /// Drop local rows whose delivery time has already passed AND that the
    /// server no longer tracks. When the scheduled-endpoint server dispatches
    /// a message it removes it from its own state but never tells the client,
    /// so those rows would otherwise linger in the list forever ("scheduled
    /// message from yesterday still stuck"). Rows still known to the server
    /// are kept (the server may still be retrying).
    private func reconcileWithServer() async {
        let now = Date()
        let stale = messages.filter { $0.scheduledAt < now }
        guard !stale.isEmpty else { return }
        let byServer = Dictionary(grouping: stale) { $0.serverURLString }
        var toDelete: [PendingScheduledMessage] = []
        for (serverURLString, rows) in byServer {
            guard let serverKeys = await PendingScheduledMessage.serverScheduleKeys(
                serverURLString: serverURLString
            ) else {
                // Server unreachable — do NOT delete anything this pass.
                continue
            }
            toDelete += rows.filter { !serverKeys.contains($0.scheduleKey) }
        }
        guard !toDelete.isEmpty else { return }
        for msg in toDelete {
            modelContext.delete(msg)
        }
        try? modelContext.save()
        await loadMessages()
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

    /// GET the server's current scheduled-message keys for reconciliation.
    /// Returns nil when the server is unreachable so the caller can skip
    /// deletion rather than assume an empty remote state.
    static func serverScheduleKeys(serverURLString: String) async -> Set<String>? {
        guard !serverURLString.isEmpty,
              let serverURL = URL(string: serverURLString) else { return nil }
        let webhookURL = serverURL.appendingPathComponent("webhook/scheduled-messages")
        var request = URLRequest(url: webhookURL)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(ScheduledServerResponse.self, from: data)
            return Set(decoded.messages.compactMap { $0.scheduleKey })
        } catch {
            return nil
        }
    }

    /// POST an (edited) scheduled message to the server. The server upserts by
    /// scheduleKey and reschedules its dispatch timer.
    static func syncToServer(
        scheduleKey: String,
        text: String,
        scheduledAt: Double,
        sessionId: String,
        sessionTitle: String? = nil,
        serverURLString: String
    ) async {
        guard !serverURLString.isEmpty,
              let serverURL = URL(string: serverURLString) else { return }
        let webhookURL = serverURL.appendingPathComponent("webhook/scheduled-messages")
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "scheduleKey": scheduleKey,
            "text": text,
            "scheduledAt": scheduledAt,
            "sessionId": sessionId,
        ]
        if let sessionTitle, !sessionTitle.isEmpty {
            payload["sessionTitle"] = sessionTitle
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 10
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
        } catch {
            print("[ScheduledMessage] edit sync error: \(error.localizedDescription)")
        }
    }
}

private struct ScheduledServerResponse: Decodable {
    let messages: [ScheduledServerMessage]
}

private struct ScheduledServerMessage: Decodable {
    let scheduleKey: String?
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
    let onEdit: () -> Void

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

                Button("Edit") { onEdit() }
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

/// Edit sheet for a scheduled message: change text and/or delivery time, then
/// persist locally and POST to the scheduled-endpoint server (which upserts by
/// scheduleKey and reschedules its dispatch timer).
fileprivate struct EditScheduledMessageSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let message: PendingScheduledMessage
    let onSaved: () -> Void

    @State private var text: String = ""
    @State private var scheduledAt: Date = Date()
    @State private var sessionTitle: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    TextField("Message text", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                }
                // The chat title only matters for messages destined for a brand-new
                // chat (sessionId empty) — those the server creates on delivery and
                // renames to this title. Attached-to-existing-chat messages have no
                // editable title of their own.
                if message.sessionId.isEmpty {
                    Section("New chat title (optional)") {
                        TextField("Chat title", text: $sessionTitle)
                            .textInputAutocapitalization(.sentences)
                    }
                }
                Section("Scheduled time") {
                    DatePicker("Deliver at", selection: $scheduledAt)
                }
            }
            .navigationTitle("Edit Scheduled Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                text = message.draftText
                scheduledAt = message.scheduledAt
                sessionTitle = message.sessionTitle ?? ""
            }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        message.draftText = trimmed
        message.scheduledAt = scheduledAt
        message.sessionTitle = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()

        let key = message.scheduleKey
        let sid = message.sessionId
        let sURL = message.serverURLString
        let ts = scheduledAt.timeIntervalSince1970
        Task {
            await PendingScheduledMessage.syncToServer(
                scheduleKey: key,
                text: trimmed,
                scheduledAt: ts,
                sessionId: sid,
                sessionTitle: message.sessionTitle,
                serverURLString: sURL
            )
        }
        onSaved()
        dismiss()
    }
}
