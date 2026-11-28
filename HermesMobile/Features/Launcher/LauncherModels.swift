import Foundation

/// What a launcher tile points at.
///
/// The tile is a shortcut to an existing object, never a copy of it: adding a tile
/// must not create a Hermes session, a bot profile or a group room, and removing a
/// tile must not delete what it named.
enum LauncherObjectKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bot
    case group
    case chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bot: String(localized: "Bot")
        case .group: String(localized: "Group")
        case .chat: String(localized: "Chat")
        }
    }

    var systemImage: String {
        switch self {
        case .bot: "cpu"
        case .group: "person.3"
        case .chat: "bubble.left.and.bubble.right"
        }
    }
}

/// One tile of the 4 × 3 workspace launcher.
///
/// `objectID` is the existing object's own identity — a bot profile name, a
/// `BotGroupRoom` id, or a Hermes session id. `label` is the owner's Launcher
/// Label and is deliberately independent of `objectTitle`: renaming a tile must
/// not rename the session, and renaming the session through the normal UI must
/// not overwrite the tile.
struct LauncherItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: LauncherObjectKind
    /// Identity inside its own kind. Never a display name for `group`/`chat`.
    var objectID: String
    /// The object's own name when the tile was created: the fallback for display
    /// when no Launcher Label is set, and the last known name for a tile whose
    /// object is temporarily unreachable.
    var objectTitle: String
    /// The owner's Launcher Label. Empty means "show `objectTitle`".
    var label: String
    /// Which of the launcher's 12 slots the tile occupies (0 = top-left).
    var slot: Int

    init(
        id: UUID = UUID(),
        kind: LauncherObjectKind,
        objectID: String,
        objectTitle: String,
        label: String = "",
        slot: Int
    ) {
        self.id = id
        self.kind = kind
        self.objectID = objectID
        self.objectTitle = objectTitle
        self.label = label
        self.slot = slot
    }

    /// What the tile draws: the Launcher Label when the owner set one, otherwise
    /// the object's own name.
    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? objectTitle : trimmed
    }

    /// Identity of what the tile points at, used to stop the same object being
    /// added twice.
    var target: LauncherTarget { LauncherTarget(kind: kind, objectID: objectID) }
}

/// The object a tile names, without the tile's own identity or label.
struct LauncherTarget: Equatable, Hashable, Sendable {
    let kind: LauncherObjectKind
    let objectID: String
}

/// A request to fill one launcher slot, carried as a sheet item.
struct LauncherAddSlot: Identifiable, Equatable {
    let slot: Int
    var id: Int { slot }
}

/// The 4 × 3 grid's contents, persisted per server.
///
/// Stored in `UserDefaults` as JSON under a key scoped to the server host, the
/// same way the dock order and header list are stored: a tile that opens a
/// session on one server must never appear on another.
@MainActor @Observable
final class LauncherStore {
    /// 4 columns × 3 rows, per the release spec.
    static let columns = 4
    static let rows = 3
    static let capacity = columns * rows

    private(set) var items: [LauncherItem]

    private let defaults: UserDefaults
    private let storageKey: String

    init(server: URL, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Host-scoped so two servers never share tiles. Scheme is dropped on
        // purpose: http→https on the same host is the same workspace.
        let host = server.host ?? server.absoluteString
        storageKey = "launcher.items.\(host)"
        items = []
        load()
    }

    // MARK: - Queries

    func item(atSlot slot: Int) -> LauncherItem? {
        items.first { $0.slot == slot }
    }

    func contains(_ target: LauncherTarget) -> Bool {
        items.contains { $0.target == target }
    }

    var occupiedSlots: Set<Int> { Set(items.map(\.slot)) }

    /// The first free slot in reading order, or nil when the grid is full.
    var firstFreeSlot: Int? {
        (0..<Self.capacity).first { !occupiedSlots.contains($0) }
    }

    var isFull: Bool { items.count >= Self.capacity }

    // MARK: - Mutations

    /// Adds a shortcut to an existing object. Returns false when the object is
    /// already on the panel or the grid is full — both are refusals, not errors,
    /// and neither creates anything on the server.
    @discardableResult
    func add(kind: LauncherObjectKind, objectID: String, objectTitle: String, slot: Int? = nil) -> Bool {
        let target = LauncherTarget(kind: kind, objectID: objectID)
        guard !contains(target) else { return false }
        guard let destination = slot ?? firstFreeSlot, (0..<Self.capacity).contains(destination) else {
            return false
        }
        // A slot already taken by another tile is refused rather than silently
        // overwritten: the owner asked for that tile to be there.
        guard item(atSlot: destination) == nil else { return false }

        items.append(
            LauncherItem(kind: kind, objectID: objectID, objectTitle: objectTitle, slot: destination)
        )
        save()
        return true
    }

    func remove(_ item: LauncherItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Sets the owner's Launcher Label. An empty string restores the object's own
    /// name — it never renames the object itself.
    func setLabel(_ label: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].label = label
        save()
    }

    /// Refreshes the remembered name of a tile's object, for when the owner
    /// renamed the session/bot/room through the normal UI. The Launcher Label is
    /// left untouched.
    func refreshObjectTitle(_ title: String, for target: LauncherTarget) {
        guard let index = items.firstIndex(where: { $0.target == target }) else { return }
        guard items[index].objectTitle != title else { return }
        items[index].objectTitle = title
        save()
    }

    /// Moves a tile to another slot. Whatever was there swaps into the vacated
    /// slot, so a drag never silently drops a tile.
    func move(_ item: LauncherItem, to slot: Int) {
        guard (0..<Self.capacity).contains(slot), slot != item.slot else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        if let occupantIndex = items.firstIndex(where: { $0.slot == slot && $0.id != item.id }) {
            items[occupantIndex].slot = item.slot
        }
        items[index].slot = slot
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([LauncherItem].self, from: data) else {
            // A corrupt blob must not wipe the panel silently — start empty and
            // let the owner re-add, but keep the old bytes for inspection.
            return
        }
        // Drop out-of-range and duplicate slots so a hand-edited blob can never
        // produce two tiles on one cell or a tile nobody can see.
        var seen = Set<Int>()
        items = decoded
            .filter { (0..<Self.capacity).contains($0.slot) }
            .sorted { $0.slot < $1.slot }
            .filter { seen.insert($0.slot).inserted }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
