import SwiftUI

/// The 4 × 3 workspace launcher.
///
/// A panel of shortcuts to existing objects — bots, groups and chats side by side.
/// It draws twelve fixed cells in reading order so the grid never reflows as tiles
/// are added: an empty cell is an "Add" affordance, not a hole.
struct WorkspaceLauncherView: View {
    @Bindable var store: LauncherStore
    /// Opens the object a tile names. The caller decides which section to switch
    /// to and which object to show.
    let onOpen: (LauncherItem) -> Void
    /// Presents the picker that adds an existing object.
    let onAdd: (Int) -> Void

    @State private var renaming: LauncherItem?
    @State private var renameText = ""
    @State private var draggedID: UUID?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: LauncherStore.columns
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<LauncherStore.capacity, id: \.self) { slot in
                if let item = store.item(atSlot: slot) {
                    tile(item)
                } else {
                    addCell(slot: slot)
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: store.items)
        .sheet(item: $renaming) { item in
            renameSheet(item)
        }
    }

    // MARK: - Cells

    private func tile(_ item: LauncherItem) -> some View {
        Button {
            onOpen(item)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)

                    // The kind marker: three kinds share one panel, so the tile
                    // says which one it is without relying on the icon alone.
                    Image(systemName: kindBadge(item.kind))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Text(item.displayLabel)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(height: 86)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(item.kind.title): \(item.displayLabel)"))
        .contextMenu {
            Button {
                renameText = item.label
                renaming = item
            } label: {
                Label("Rename Tile", systemImage: "pencil")
            }
            Button(role: .destructive) {
                store.remove(item)
            } label: {
                Label("Remove Tile", systemImage: "minus.circle")
            }
        }
        .draggable(item.id.uuidString) {
            Text(item.displayLabel)
                .font(.caption)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .dropDestination(for: String.self) { payload, _ in
            guard let raw = payload.first,
                  let id = UUID(uuidString: raw),
                  let source = store.items.first(where: { $0.id == id })
            else { return false }
            store.move(source, to: item.slot)
            return true
        }
    }

    private func addCell(slot: Int) -> some View {
        Button {
            onAdd(slot)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 28)
                Text("Add")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.10),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add a shortcut to slot \(slot + 1)"))
        .dropDestination(for: String.self) { payload, _ in
            guard let raw = payload.first,
                  let id = UUID(uuidString: raw),
                  let source = store.items.first(where: { $0.id == id })
            else { return false }
            store.move(source, to: slot)
            return true
        }
    }

    /// A short glyph that tells the kinds apart at a glance.
    private func kindBadge(_ kind: LauncherObjectKind) -> String {
        switch kind {
        case .bot: "circle.fill"
        case .group: "square.fill"
        case .chat: "bubble.fill"
        }
    }

    // MARK: - Rename

    private func renameSheet(_ item: LauncherItem) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField(item.objectTitle, text: $renameText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("Launcher Label")
                } footer: {
                    Text("The name on this tile only. It does not rename \(item.kind.title.lowercased()) “\(item.objectTitle)”.")
                }

                Section {
                    Button("Use the object’s own name") {
                        renameText = ""
                    }
                    .disabled(renameText.isEmpty)
                }
            }
            .navigationTitle("Rename Tile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { renaming = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setLabel(renameText, for: item.id)
                        renaming = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
