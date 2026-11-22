import Foundation
import SwiftUI
import UIKit

/// The built-in glyph set a group room can wear instead of the faces of its
/// first members.
///
/// The identifier is the SF Symbol name verbatim: a made-up id would need a
/// mapping table nothing could verify, and a name that does not exist in the
/// running system draws an empty square — the worst failure mode for an icon,
/// because it looks like a loading error. `RoomIconStoreTests` resolves every
/// name through `UIImage(systemName:)`, which is the only check available
/// without a device.
enum RoomIconLibrary {
    struct Category: Identifiable, Equatable {
        let title: String
        let glyphs: [String]

        var id: String { title }
    }

    /// Five per category on purpose: every category has the same weight in the
    /// picker, so "let me add one more" is never a safe-looking edit.
    static let categories: [Category] = [
        Category(title: "Work and build", glyphs: [
            "hammer.fill", "wrench.and.screwdriver.fill", "terminal.fill",
            "shippingbox.fill", "gearshape.fill",
        ]),
        Category(title: "Research and thought", glyphs: [
            "magnifyingglass", "books.vertical.fill", "lightbulb.fill",
            "brain.head.profile", "chart.bar.fill",
        ]),
        Category(title: "Code and data", glyphs: [
            "chevron.left.forwardslash.chevron.right", "cpu.fill",
            "externaldrive.fill", "tablecells", "network",
        ]),
        Category(title: "People and talk", glyphs: [
            "person.fill", "person.2.fill", "person.3.fill",
            "bubble.left.and.bubble.right.fill", "hand.raised.fill",
        ]),
        Category(title: "Nature and signs", glyphs: [
            "leaf.fill", "flame.fill", "moon.stars.fill", "sun.max.fill", "star.fill",
        ]),
        Category(title: "Places and motion", glyphs: [
            "house.fill", "building.2.fill", "cart.fill", "map.fill", "figure.run",
        ]),
    ]

    static var allGlyphs: [String] { categories.flatMap(\.glyphs) }

    static var glyphCount: Int { allGlyphs.count }

    static func contains(_ glyph: String) -> Bool { allGlyphs.contains(glyph) }
}

/// Which glyph a room wears, stored on this device only.
///
/// `nil` means "no choice": the room draws the faces of its participants, which
/// is what every room looked like before this release. That is why clearing a
/// choice **removes** the entry instead of writing a default glyph — a written
/// default would change the appearance of rooms nobody customised, and "restore
/// default" would stop being a restore.
///
/// A glyph string read back from disk that this build does not know (written by
/// a later version, or a symbol removed from iOS) is treated as absent rather
/// than drawn: `icon(for:)` returns nil, the room falls back to faces.
@MainActor
final class RoomIconStore {
    static let shared = RoomIconStore()

    private var icons: [String: String] = [:]
    private var didLoad = false
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = base.appendingPathComponent("HermexRoomIcons", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("room-icons.json")
        }
    }

    /// The chosen glyph, or nil when the room should draw its members' faces.
    func icon(for key: BotRoomKey) -> String? {
        loadIfNeeded()
        guard let glyph = icons[storageKey(key)], RoomIconLibrary.contains(glyph) else { return nil }
        return glyph
    }

    /// Sets a glyph, or removes the choice when `glyph` is nil. Unknown names are
    /// refused rather than stored, so the file cannot accumulate entries that
    /// nothing can draw.
    func setIcon(_ glyph: String?, for key: BotRoomKey) {
        loadIfNeeded()
        let storage = storageKey(key)
        if let glyph, RoomIconLibrary.contains(glyph) {
            icons[storage] = glyph
        } else {
            icons.removeValue(forKey: storage)
        }
        persist()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Posted after any change, so a badge already on screen re-reads its glyph
    /// instead of waiting for the room to be reopened.
    static let didChange = Notification.Name("RoomIconStoreDoChange")

    /// The picker's "restore default": the entry goes away, the room draws faces.
    func clearIcon(for key: BotRoomKey) { setIcon(nil, for: key) }

    /// Rooms that no longer exist leave nothing behind.
    func removeAll(server: URL, connectionID: UUID) {
        loadIfNeeded()
        let prefix = "\(server.absoluteString)|\(connectionID.uuidString)|"
        let kept = icons.filter { !$0.key.hasPrefix(prefix) }
        guard kept.count != icons.count else { return }
        icons = kept
        persist()
    }

    private func storageKey(_ key: BotRoomKey) -> String {
        "\(key.server.absoluteString)|\(key.connectionID.uuidString)|\(key.roomID)"
    }

    // MARK: - Disk

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        // Drop anything this build cannot draw, so a file written by a later
        // version degrades to faces per room instead of one blank square.
        icons = decoded.filter { RoomIconLibrary.contains($0.value) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(icons) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// One glyph as the room draws it: a rounded container and a monochrome symbol.
///
/// No colour coding and no gradients: rooms sit next to bot photographs, and any
/// tint either fights the photo or turns to mud in dark mode. Shape alone
/// distinguishes them, so light and dark both work with one asset.
struct RoomIconGlyph: View {
    let glyph: String
    let size: CGFloat

    private var radius: CGFloat { (size * 0.28).rounded() }
    private var symbolSize: CGFloat { (size * 0.56).rounded() }

    var body: some View {
        Image(systemName: glyph)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A room's face: the chosen glyph, or the faces of its first members.
///
/// Every place that used to draw `BotRoomAvatars` for a room goes through this,
/// so a room with no choice looks exactly as it always did, and a room that has
/// one shows it in the list, the header and the profile without three copies of
/// the lookup.
struct BotRoomBadge: View {
    let key: BotRoomKey
    let room: BotGroupRoom
    let roster: [BotProfile]
    let avatars: [String: UIImage]
    let size: CGFloat

    @State private var glyph: String?

    var body: some View {
        Group {
            if let glyph {
                RoomIconGlyph(glyph: glyph, size: size)
            } else {
                BotRoomAvatars(room: room, roster: roster, avatars: avatars, size: size)
            }
        }
        .task(id: key) { glyph = RoomIconStore.shared.icon(for: key) }
        .onReceive(NotificationCenter.default.publisher(for: RoomIconStore.didChange)) { _ in
            glyph = RoomIconStore.shared.icon(for: key)
        }
    }
}

/// The picker: six labelled rows of five glyphs plus the restore action.
///
/// Lives in the room profile rather than the chat header: changing a room's face
/// is a settings action, and the header is the place the owner taps to open this
/// screen, not a place to edit.
struct RoomIconPickerSection: View {
    let roomKey: BotRoomKey

    @State private var selected: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        Section("Room icon") {
            ForEach(RoomIconLibrary.categories) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.title).font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(category.glyphs, id: \.self) { glyph in
                            Button { choose(glyph) } label: { RoomIconGlyph(glyph: glyph, size: 44) }
                                .buttonStyle(.plain)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.accentColor, lineWidth: selected == glyph ? 2 : 0)
                                )
                                .accessibilityLabel(Text(glyph))
                                .accessibilityAddTraits(selected == glyph ? [.isSelected] : [])
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Button("Restore default") { choose(nil) }
                .disabled(selected == nil)
        }
        .task { selected = RoomIconStore.shared.icon(for: roomKey) }
        .onReceive(NotificationCenter.default.publisher(for: RoomIconStore.didChange)) { _ in
            selected = RoomIconStore.shared.icon(for: roomKey)
        }
    }

    private func choose(_ glyph: String?) {
        RoomIconStore.shared.setIcon(glyph, for: roomKey)
        selected = glyph
    }
}
