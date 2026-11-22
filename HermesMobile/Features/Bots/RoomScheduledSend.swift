import Foundation

/// A room message the user asked to send later.
///
/// The defining decision: this holds **a copy of each file inside our own
/// container**, never a reference to where the picker found it and never uploaded
/// bytes. Two reasons, both learned the hard way:
///
/// - An uncommitted upload expires after an hour (`UNCOMMITTED_TTL_SECONDS`,
///   `session_rules/hosted_attachments.py:27`), so a message scheduled for tomorrow
///   would reach `groups.send` on an attachment that no longer exists. The upload
///   therefore happens in the same run that appends the event.
/// - A URL from the system picker points into a FileProvider or another app's
///   temporary directory. It is not ours, it is not guaranteed after a relaunch, and
///   a security-scoped bookmark would have to be started and stopped around every
///   read. A copy has none of those problems: the bytes are ours, so the file is
///   still there tomorrow.
///
/// `id` doubles as the `event_id` of the eventual send, which is what makes a retry
/// after an uncertain result idempotent on the gateway: the same message cannot be
/// appended twice.
struct RoomScheduledSend: Codable, Equatable, Identifiable {
    /// One file, as a path relative to the store's attachments directory.
    struct Attachment: Codable, Equatable {
        let name: String
        let byteCount: Int
        /// `"<message id>/<file name>"` — relative on purpose: the container path
        /// changes between installs, the relative path does not.
        let relativePath: String
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
    case copyFailed(name: String, reason: String)
    case refused(RoomAttachmentFailure)

    var errorDescription: String? {
        switch self {
        case .nothingToSend:
            String(localized: "Write something, or attach a file, before scheduling.")
        case .inThePast:
            String(localized: "Pick a time in the future, or send it now.")
        case let .copyFailed(name, reason):
            String(localized: "\(name) couldn't be kept for later: \(reason)")
        case let .refused(failure):
            failure.errorDescription
        }
    }
}

/// Scheduled messages for rooms, stored on this device.
///
/// Same shape as `RoomIconStore`: a JSON file in Application Support, written on
/// every change, so a scheduled message survives the app being killed — which is
/// the whole point of scheduling it. Each message owns a directory of file copies
/// beside that JSON, and the directory goes away with the message.
@MainActor
final class RoomScheduledStore {
    static let shared = RoomScheduledStore()

    private let directory: URL
    private let attachmentsDirectory: URL
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
        self.attachmentsDirectory = base.appendingPathComponent("attachments", isDirectory: true)
        self.fileURL = base.appendingPathComponent("scheduled.json")
        load()
    }

    /// The copy a message owns, resolved against today's container path.
    func url(for attachment: RoomScheduledSend.Attachment) -> URL {
        attachmentsDirectory.appendingPathComponent(attachment.relativePath)
    }

    /// Queues a message: validates the selection, copies each file into the
    /// container, then writes the queue. Nothing is uploaded here.
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

        let id = UUID().uuidString.lowercased()
        var attachments: [RoomScheduledSend.Attachment] = []
        for upload in budget.uploads {
            let destination = attachmentsDirectory
                .appendingPathComponent(id, isDirectory: true)
                .appendingPathComponent(upload.name)
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try upload.data.write(to: destination, options: .atomic)
            } catch {
                // A file we could not keep is a refusal with a reason, never a silently
                // dropped attachment: a message that loses its photo and sends anyway is
                // worse than one that says it cannot be scheduled.
                removeCopies(for: id)
                throw RoomScheduleFailure.copyFailed(name: upload.name, reason: error.localizedDescription)
            }
            attachments.append(
                RoomScheduledSend.Attachment(
                    name: upload.name,
                    byteCount: upload.byteCount,
                    relativePath: "\(id)/\(upload.name)"
                )
            )
        }

        let item = RoomScheduledSend(
            id: id,
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

    /// Delivered: the copies have no further use.
    func complete(_ id: String) {
        items.removeAll { $0.id == id }
        removeCopies(for: id)
        persist()
    }

    func fail(_ id: String, reason: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].recordFailure(reason)
        persist()
    }

    /// Terminal refusal: the message will not be retried, so its copies go too.
    func discard(_ id: String) {
        items.removeAll { $0.id == id }
        removeCopies(for: id)
        persist()
    }

    func removeAll(for room: BotRoomKey) {
        let doomed = items.filter { $0.roomKey == room }
        items.removeAll { $0.roomKey == room }
        for item in doomed { removeCopies(for: item.id) }
        persist()
    }

    func count(for room: BotRoomKey) -> Int {
        items.filter { $0.roomKey == room }.count
    }

    private func removeCopies(for id: String) {
        try? FileManager.default.removeItem(
            at: attachmentsDirectory.appendingPathComponent(id, isDirectory: true))
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
            lastPersistFailure = nil
        } catch {
            // Scheduling is not worth crashing over: the message stays in memory for
            // this session, and the composer can say it will not survive a restart.
            lastPersistFailure = error.localizedDescription
        }
    }
}
