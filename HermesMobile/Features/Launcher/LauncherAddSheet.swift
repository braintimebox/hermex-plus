import SwiftUI

/// Adds an **existing** object to the launcher.
///
/// It never creates anything: no new session, no new bot profile, no new room.
/// The three categories are the objects the app already has, and the one already
/// on the panel is shown as taken instead of being added twice.
struct LauncherAddSheet: View {
    let slot: Int
    let server: URL
    /// The chats the caller already loaded — the picker does not re-fetch them.
    let sessions: [SessionSummary]

    @Bindable var store: LauncherStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: LauncherObjectKind = .chat
    @State private var query = ""
    @State private var inbox: BotInbox?
    @State private var isLoadingBots = false
    @State private var botLoadFailed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Category", selection: $kind) {
                    ForEach(LauncherObjectKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if kind == .chat {
                    chatList
                } else {
                    botList
                }
            }
            .navigationTitle("Add to Launcher")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                guard kind != .chat else { return }
                await loadInboxIfNeeded()
            }
            .onChange(of: kind) { _, newValue in
                guard newValue != .chat else { return }
                Task { await loadInboxIfNeeded() }
            }
        }
    }

    // MARK: - Chats

    private var filteredSessions: [SessionSummary] {
        let sorted = sessions.sorted { ($0.lastMessageAt ?? $0.updatedAt ?? 0) > ($1.lastMessageAt ?? $1.updatedAt ?? 0) }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { ($0.title ?? "").localizedCaseInsensitiveContains(query) }
    }

    private var chatList: some View {
        List(filteredSessions) { session in
            let id = session.sessionId ?? ""
            let title = (session.title?.isEmpty == false ? session.title! : "Untitled chat")
            row(
                kind: .chat,
                objectID: id,
                title: title,
                subtitle: session.profile.map { "@\($0)" }
            )
        }
        .listStyle(.plain)
        .overlay {
            if filteredSessions.isEmpty {
                ContentUnavailableView(
                    "No chats",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a chat first — the launcher only holds shortcuts to chats that exist.")
                )
            }
        }
    }

    // MARK: - Bots and groups

    private var botList: some View {
        Group {
            if isLoadingBots {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if botLoadFailed {
                ContentUnavailableView(
                    "Bot connection unavailable",
                    systemImage: "cpu",
                    description: Text("The launcher needs the bot connection to list \(kind == .bot ? "bots" : "groups").")
                )
            } else {
                List(filteredBots) { entry in
                    row(kind: kind, objectID: entry.id, title: entry.name, subtitle: nil)
                }
                .listStyle(.plain)
                .overlay {
                    if filteredBots.isEmpty {
                        ContentUnavailableView {
                            Label(kind == .bot ? "No bots" : "No groups", systemImage: kind.systemImage)
                        }
                    }
                }
            }
        }
    }

    private struct BotEntry: Identifiable {
        let id: String
        let name: String
    }

    private var filteredBots: [BotEntry] {
        let entries: [BotEntry]
        if kind == .bot {
            entries = (inbox?.profiles ?? []).map { BotEntry(id: $0.id, name: $0.name) }
        } else {
            entries = (inbox?.rooms ?? []).map { BotEntry(id: $0.id, name: $0.name) }
        }
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func loadInboxIfNeeded() async {
        if let inbox {
            // The inbox is per scope in the host view; here one inbox answers both
            // lists because `.all` carries profiles and rooms together.
            if inbox.profiles.isEmpty && inbox.rooms.isEmpty {
                isLoadingBots = true
                await inbox.open()
                isLoadingBots = false
            }
            return
        }

        isLoadingBots = true
        botLoadFailed = false
        let created = BotInbox(server: server)
        created.scope = .all
        inbox = created
        await created.open()
        isLoadingBots = false
        botLoadFailed = created.errorMessage != nil && created.profiles.isEmpty && created.rooms.isEmpty
    }

    // MARK: - Row

    private func row(kind: LauncherObjectKind, objectID: String, title: String, subtitle: String?) -> some View {
        let target = LauncherTarget(kind: kind, objectID: objectID)
        let taken = store.contains(target)

        return Button {
            guard !taken else { return }
            guard store.add(kind: kind, objectID: objectID, objectTitle: title, slot: slot) else { return }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if taken {
                    Text("Added")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(taken || objectID.isEmpty)
    }
}
