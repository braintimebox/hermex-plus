import SwiftUI

struct ForwardMessageSheet: View {
    let content: (text: String, author: String, sessionId: String?, sessionTitle: String)?
    let onForward: (String, String, String, String) -> Void
    let onDismiss: () -> Void
    let client: APIClient

    @State private var sessions: [SessionSummary] = []
    @State private var isLoadingForwardSessions = false
    @State private var showingSchedulePicker = false
    @State private var scheduledDate: Date? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let content = content {
                    Text("🔄 Forwarded from «\(content.sessionTitle)» (\(content.author)):\n\n\(content.text)")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let sessionId = content.sessionId {
                    Text("→ \(sessionId)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                if showingSchedulePicker {
                    VStack(spacing: 20) {
                        DatePicker(
                            "Schedule for",
                            selection: $scheduledDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .frame(maxWidth: .infinity)
                        
                        Text("📝 Text preview:")
                        Text(draftMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity)
                        
                        Button("Send Now") {
                            guard let content = content else { return }
                            let forwardText = "🔄 Forwarded from \"\(content.sessionTitle)\" (\(content.author)):\n\n\(content.text)"
                            Task {
                                await sendDraftMessage(sessionId: content.sessionId, message: forwardedText)
                                showingSchedulePicker = false
                            }
                        }
                    }
                }
            }
            .navigationTitle("Forward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            if showingSchedulePicker {
                ScheduleMessageSheet(
                    sessionId: scheduledSessionId ?? "",
                    message: draftMessage,
                    onSchedule: { date in
                        saveScheduledMessage(at: date)
                        showingSchedulePicker = false
                    }
                )
            } else if let content = content {
                ForwardSessionView(
                    sessionId: content.sessionId,
                    sessionTitle: content.sessionTitle,
                    message: content.text,
                    onForward: { text, author, sessionId, sessionTitle in
                        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
                        let header = "🔄 Forwarded from «\(content.sessionTitle)» (\(content.author)):\n\n\(content.text)"
                        draftMessage = "\(header)\n\(content.text)"
                        showForwardSheet = true
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let content = content {
                    Text("🔄 Forwarded from «\(content.sessionTitle)» (\(content.author)):\n\n\(content.text)")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let sessionId = content.sessionId {
                    Text("→ \(sessionId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if showingSchedulePicker {
                    VStack(spacing: 16) {
                        Text("📅 Schedule for:")
                        DatePicker("Date & Time", selection: $scheduledDate, in: Date()...)
                            .datePickerStyle(.compact)
                        
                        Text("📝 Message preview:")
                        Text(draftMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity)
                        
                        Button("Send Now") {
                            guard let content = content else { return }
                            let forwardText = "🔄 Forwarded from «\(content.sessionTitle)» (\(content.author)):\n\n\(content.text)"
                            Task {
                                await sendDraftMessage(sessionId: content.sessionId, message: forwardedText)
                                showingSchedulePicker = false
                            }
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let content = content {
                    Text("🔄 Forwarded from «\(content.sessionTitle)» (\(content.author)):\n\n\(content.text)")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let sessionId = content.sessionId {
                    Text("→ \(sessionId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if showingSchedulePicker {
                    VStack(spacing: 20) {
                        Text("🕒 When to send:")
                        DatePicker("Date & Time", selection: $scheduledDate, in: Date()..Date().addingTimeInterval(86400))
                            .datePickerStyle(.compact)
                        
                        Text("📝 Preview:")
                        Text(draftMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity)
                        
                        Button("Send Now") {
                            guard let content = content else { return }
                            let forwardedText = "🔄 Forwarded from «\(content.sessionTitle)» (\(content.author)):\n\n\(content.text)"
                            Task {
                                await sendDraftMessage(sessionId: content.sessionId, message: forwardedText)
                                showingSchedulePicker = false
                            }
                        }
                    }
                }
            }
        }
    }

    init(
        content: (text: String, author: String, sessionId: String?, sessionTitle: String)?,
        onForward: @escaping (String, String, String, String) -> Void,
        onDismiss: @escaping () -> Void,
        client: APIClient
    ) {
        self.content = content
        self.onForward = onForward
        self.onDismiss = onDismiss
        self.client = client
        self.sessions = []
        isLoadingForwardSessions = false
        showingSchedulePicker = false
    }
}

// MARK: - Session picker
struct SessionPickerForForward: View {
    let sessions: [SessionSummary]
    let onSelect: (SessionListItem) -> Void

    @Environment(\\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredSessions: [SessionListItem] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter { $0.displayTitle.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    Button {
                        onSelect(session)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.displayTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if let lastMessage = session.lastMessagePreview {
                                Text(lastMessagePreview)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Forward To")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search sessions")
        }
    }
}

struct SessionListItem: Identifiable {
    let id: String
    let displayTitle: String
    let lastMessagePreview: String?
}