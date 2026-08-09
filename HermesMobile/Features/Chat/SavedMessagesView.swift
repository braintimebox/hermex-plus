import SwiftUI
import SwiftData

struct SavedMessagesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedMessage.sortOrder) private var savedMessages: [SavedMessage]

    let onOpenMessage: (String, String) -> Void

    @State private var isReordering = false

    var body: some View {
        Group {
            if savedMessages.isEmpty {
                ContentUnavailableView(
                    "No Saved Messages",
                    systemImage: "bookmark.slash",
                    description: Text("Long-press any message and tap Save to add it here.")
                )
            } else {
                List {
                    ForEach(savedMessages) { saved in
                        Button {
                            onOpenMessage(saved.sessionId, saved.messageId)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(width: 3)
                                        .clipShape(Capsule())

                                    Text(saved.content)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .foregroundColor(.primary)
                                }

                                HStack(spacing: 6) {
                                    Text(saved.author)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.accentColor)

                                    Text("→")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text(saved.sessionTitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text(saved.savedAt, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteSaved)
                    .onMove(perform: moveSaved)
                }
                .toolbar {
                    if !savedMessages.isEmpty {
                        EditButton()
                    }
                }
            }
        }
        .navigationTitle("Saved")
    }

    private func deleteSaved(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(savedMessages[index])
        }
    }

    private func moveSaved(from source: IndexSet, to destination: Int) {
        var items = savedMessages
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
    }
}
