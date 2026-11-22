import Foundation

/// A room message the user asked to send later.
///
/// The defining decision: this holds **references to local files, never uploaded
/// bytes**. An uncommitted upload expires after an hour
/// (`UNCOMMITTED_TTL_SECONDS`, `session_rules/hosted_attachments.py:27`), so a
/// message scheduled for tomorrow whose file was uploaded today would reach
/// `groups.send` on an attachment that no longer exists, and the user would be told
/// "it didn't send" with nothing to act on. The upload therefore happens at send
/// time, in the same run that appends the event.
///
/// `id` doubles as the `event_id` of the eventual send, which is what makes a retry
/// after an uncertain result idempotent on the gateway: the same message cannot be
/// appended twice.
struct RoomScheduledSend: Codable, Equatable, Identifiable {
    /// One file, by reference.
    struct Attachment: Codable, Equatable {
        let name: String
        let byteCount: Int
        /// Path inside this app's container. Kept as a fallback for when a bookmark
        /// cannot be made (a file that stays in our own documents directory).
        let path: String
        /// Security-scoped bookmark for a file the picker handed us, which lives
        /// outside our container and would otherwise disappear with the session.
        let bookmark: Data?

        var fileURL: URL { URL(fileURLWithPath: path) }
    }

    let id: String
    let server: String
    let connectionID: String
    let roomID: String
    let roomName: String
    let threadID: String?
    let text: String
    let attachments: [Attachment]
    let dueAt: Date
    private(set) var attempts: Int
    private(set) var lastFailure: String?

    /// The room this message belongs to, rebuilt from the stored strings.
    var roomKey: BotRoomKey? {
        guard let url = URL(string: server), let id = UUID(uuidString: connectionID) else { return nil }
        return BotRoomKey(server: url, connectionID: id, roomID: roomID)
    }

    var byteCount: Int { attachments.reduce(0) { $0 + $1.byteCount } }

    func isDue(at now: Date) -> Bool { dueAt <= now }

    mutating func recordFailure(_ reason: String) {
        attempts += 1
        lastFailure = reason
    }
}

/// Why a message could not be scheduled. Each case says what to do next.
enum RoomScheduleFailure: LocalizedError, Equatable {
    case nothingToSend
    case inThePast
    case refused(RoomAttachmentFailure)

    var errorDescription: String? {
        switch self {
        case .nothingToSend:
            String(localized: "Write something, or attach a file, before scheduling.")
        case .inThePast:
            String(localized: "Pick a time in the future, or send it now.")
        case let .refused(failure):
            failure.errorDescription
        }
    }
}

/// Scheduled messages for rooms, stored on this device.
///
/// Same shape as `RoomIconStore`: a JSON file in Application Support, written on
/// every change, so a scheduled message survives the app being killed — which is
/// the whole point of scheduling it.
@MainActor
final class RoomScheduledStore {
    static let shared = RoomScheduledStore()

    private let directory: URL
    private let fileURL: URL
    private(set) var items: [RoomScheduledSend] = []
    /// Set when a write failed, so the composer can warn instead of promising a
    /// delivery that will not happen after a restart.
    private(set) var lastPersistFailure: String?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomScheduled", isDirectory: true)
        self.directory = base
        self.fileURL = base.appendingPathComponent("scheduled.json")
        load()
    }

    /// Queues a message, validating the whole selection before anything is uploaded.
    @discardableResult
    func enqueue(
        room: BotRoomKey,
        roomName: String,
        threadID: String?,
        text: String,
        budget: RoomAttachmentBudget,
        dueAt: Date,
        now: Date = Date()
    ) throws -> RoomScheduledSend {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !budget.isEmpty else { throw RoomScheduleFailure.nothingToSend }
        guard dueAt > now else { throw RoomScheduleFailure.inThePast }

        let attachments = budget.uploads.compactMap { upload -> RoomScheduledSend.Attachment? in
            guard let url = upload.sourceURL else { return nil }
            return RoomScheduledSend.Attachment(
                name: upload.name,
                byteCount: upload.byteCount,
                path: url.path,
                bookmark: try? url.bookmarkData()
            )
        }

        let item = RoomScheduledSend(
            id: UUID().uuidString.lowercased(),
            server: room.server.absoluteString,
            connectionID: room.connectionID.uuidString,
            roomID: room.roomID,
            roomName: roomName,
            threadID: threadID,
            text: trimmed,
            attachments: attachments,
            dueAt: dueAt,
            attempts: 0,
            lastFailure: nil
        )
        items.append(item)
        persist()
        return item
    }

    func due(at now: Date = Date()) -> [RoomScheduledSend] {
        items.filter { $0.isDue(at: now) }.sorted { $0.dueAt < $1.dueAt }
    }

    func complete(_ id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    func fail(_ id: String, reason: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].recordFailure(reason)
        persist()
    }

    func removeAll(for room: BotRoomKey) {
        items.removeAll { $0.roomKey == room }
        persist()
    }

    func count(for room: BotRoomKey) -> Int {
        items.filter { $0.roomKey == room }.count
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        // The decoder has to match the encoder below: dates are written as ISO-8601, and
        // a default decoder would fail on them and silently empty the queue.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([RoomScheduledSend].self, from: data)) ?? []
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            // Scheduling is not worth crashing over: the message stays in memory for
            // this session, and the composer can say it will not survive a restart.
            lastPersistFailure = error.localizedDescription
        }
    }
}
