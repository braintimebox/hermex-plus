import SwiftUI

struct SessionPickerForForward: View {
    let sessions: [SessionListItem]
    let onSelect: (SessionListItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if filteredSessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a conversation first to forward messages to it.")
                    )
                } else {
                    List(filteredSessions) { session in
                        Button {
                            onSelect(session)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.displayTitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                if let lastMessage = session.lastMessagePreview {
                                    Text(lastMessage)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Forward To")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search sessions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filteredSessions: [SessionListItem] {
        guard !searchText.isEmpty else { return sessions }
        return sessions.filter { $0.displayTitle.localizedCaseInsensitiveContains(searchText) }
    }
}

/// Minimal session info for the picker — avoids pulling the full ChatMessage model.
struct SessionListItem: Identifiable {
    let id: String
    let displayTitle: String
    let lastMessagePreview: String?
}
