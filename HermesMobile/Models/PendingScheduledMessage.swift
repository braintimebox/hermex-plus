import Foundation
import SwiftData

@Model
final class PendingScheduledMessage {
    @Attribute(.unique) var scheduleKey: String
    var sessionId: String
    var sessionTitle: String?
    var draftText: String
    var scheduledAt: Date
    var createdAt: Date
    var serverURLString: String
    /// HERMEX-FORK: вложения отложенного сообщения, JSON-ом (см.
    /// `ScheduledMessageAttachment`). Опциональное поле с дефолтом — иначе
    /// SwiftData не сделает lightweight-миграцию существующей базы.
    var attachmentsJSON: String? = nil

    /// HERMEX-FORK: 3.9.65 — terminal failure state for a scheduled message.
    ///
    /// WHY: a non-retryable failure (HTTP 404 on a session the server no longer
    /// has) was retried on every delivery cycle forever — one message produced
    /// 620 failed requests over 68 hours. `retryable` was already computed by
    /// `DeliveryFailure.classify` but the caller ignored it.
    ///
    /// `terminalFailureReason` is nil while the message is still deliverable.
    /// Once set, the message is never picked up automatically again, but it is
    /// kept so the user still sees what was not delivered and why.
    /// Optional with a default — SwiftData needs that for a lightweight migration.
    var terminalFailureReason: String? = nil
    var terminalFailureAt: Date? = nil
    /// Attempts made so far. Bounds retryable errors too, so no error class can
    /// keep a message in flight forever.
    var failedAttemptCount: Int = 0

    /// HERMEX-FORK: the `event_id` a room send is deduplicated by.
    ///
    /// WHY: `groups.send` accepts an event id and drops a repeat of it. A scheduled
    /// message that is retried after an uncertain result — the request may or may not
    /// have been applied — must carry the *same* id, otherwise the retry posts the
    /// message into the room a second time and the bots answer it twice. Chat sessions
    /// have no such field because their API has no such idempotency key.
    ///
    /// Optional with a default: a row written before this column existed has nothing to
    /// fill it with, and SwiftData's lightweight migration needs that.
    var eventID: String? = nil

    /// HERMEX-FORK: the thread a room message belongs to.
    ///
    /// WHY: a scheduled reply written inside a room thread must land in that thread. The
    /// chat has no threads, so the field is unused there and nil for every chat row.
    var threadID: String? = nil

    /// True for a message addressed to a chat session, false for a room.
    ///
    /// Rooms and chats share this table, and the two delivery paths must never pick up each
    /// other's rows: the chat path would post a room message into a session that does not
    /// exist, and the chat's "Scheduled Messages" screen reconciles against the *server's*
    /// scheduled list — which can never contain a room row, so it would delete it silently.
    /// One helper, used everywhere, so the rule cannot be re-derived differently in four
    /// `#Predicate`s.
    var isChatRow: Bool { !sessionId.hasPrefix(Self.roomSessionPrefix) }

    static let roomSessionPrefix = "room:"

    /// True when automatic delivery has been given up for this message.
    var isDeliveryTerminal: Bool { terminalFailureReason != nil }

    /// Расшифрованные вложения. Пустой массив, если поле пустое или битое —
    /// отложенное сообщение без читаемых вложений должно остаться отправляемым.
    var attachments: [ScheduledMessageAttachment] {
        Self.decodeAttachments(from: attachmentsJSON)
    }

    /// Decodes the stored manifest. One helper for the model's computed `attachments`
    /// and for the delivery path, which only carries the JSON string across an actor
    /// boundary (a SwiftData object must not outlive its context).
    static func decodeAttachments(from json: String?) -> [ScheduledMessageAttachment] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ScheduledMessageAttachment].self, from: data)) ?? []
    }

    func setAttachments(_ items: [ScheduledMessageAttachment]) {
        guard !items.isEmpty else { attachmentsJSON = nil; return }
        let encoder = JSONEncoder()
        attachmentsJSON = (try? encoder.encode(items)).flatMap { String(data: $0, encoding: .utf8) }
    }

    init(
        sessionId: String,
        sessionTitle: String? = nil,
        draftText: String,
        scheduledAt: Date,
        serverURLString: String,
        createdAt: Date = Date(),
        attachments: [ScheduledMessageAttachment] = [],
        eventID: String? = nil,
        threadID: String? = nil,
        scheduleKey: String? = nil
    ) {
        // Unique key: sessionId + timestamp + UUID. Timestamp alone collides
        // when two messages are scheduled for the same minute (DatePicker wheel
        // zeroes seconds), which made SwiftData's @Attribute(.unique) drop the
        // second insert silently — the "message disappears" bug.
        // A chat row's key is its link to the server's scheduled list
        // (`ScheduledMessagesView` deletes rows the server no longer has), so its shape
        // must not change. A room has no server-side list, so its key is derived from the
        // event id instead: stable across launches, unique by construction, and it cannot
        // collide the way two messages scheduled in the same minute once did.
        self.scheduleKey = scheduleKey
            ?? "\(sessionId)|\(scheduledAt.timeIntervalSince1970)|\(UUID().uuidString)"
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.draftText = draftText
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
        self.serverURLString = serverURLString
        self.eventID = eventID
        self.threadID = threadID
        setAttachments(attachments)
    }
}

/// HERMEX-FORK: вложение отложенного сообщения в том виде, в котором оно
/// переживает перезапуск приложения. `draftFileName` указывает на файл в
/// `ChatDraftAttachmentStore` — тот же стор, что и у черновиков, поэтому копию
/// не дублируем; вместо этого имя файла обязано попадать в `keepingReferenced`
/// при уборке (иначе sweep удалит вложение как осиротевшее).
struct ScheduledMessageAttachment: Codable, Equatable, Hashable, Sendable {
    var name: String
    var path: String
    var mime: String
    var size: Int?
    var isImage: Bool
    var draftFileName: String?
    /// The gateway's upload key (`^[A-Za-z0-9][A-Za-z0-9._:-]*$`, no hyphens). Same value on
    /// a retry means the host deduplicates instead of storing a second blob.
    var uploadID: String?
    /// What the message manifest names; returned by the upload response.
    var attachmentID: String?

    init(name: String, path: String, mime: String, size: Int?, isImage: Bool, draftFileName: String?,
         uploadID: String? = nil, attachmentID: String? = nil) {
        self.uploadID = uploadID
        self.attachmentID = attachmentID
        self.name = name
        self.path = path
        self.mime = mime
        self.size = size
        self.isImage = isImage
        self.draftFileName = draftFileName
    }

    /// Payload shape the chat API expects for a sent attachment. Mirrors
    /// `PendingAttachment.toJSONValue()` exactly, so a scheduled send carries the
    /// same fields an immediate send carries.
    func toJSONValue() -> JSONValue {
        var object: [String: JSONValue] = [
            "name": .string(name),
            "path": .string(path),
            "mime": .string(mime),
        ]
        if let size {
            object["size"] = .number(Double(size))
        }
        object["is_image"] = .bool(isImage)
        return .object(object)
    }

    /// Rebuild a composer attachment for the same-chat delivery path, which sends
    /// through the normal machinery. The upload already happened when the message
    /// was scheduled, so only the server-side `path` matters here.
    func toPendingAttachment() -> PendingAttachment {
        PendingAttachment(
            name: name,
            path: path,
            mime: mime,
            size: size,
            isImage: isImage,
            thumbnailData: nil,
            draftFileName: draftFileName
        )
    }

    init(pending: PendingAttachment) {
        self.init(
            name: pending.name,
            path: pending.path,
            mime: pending.mime,
            size: pending.size,
            isImage: pending.isImage,
            draftFileName: pending.draftFileName
        )
    }
}

extension PendingScheduledMessage {
    /// Вложения строки в том виде, в котором их ждёт `groups.send`: ровно пять полей.
    ///
    /// Строка, чья загрузка не завершилась, манифеста не даёт. Отправить текст без файла
    /// честнее, чем манифест без `attachment_id`: такой хост отвергает целиком, и
    /// отложенное сообщение потерялось бы из-за одного вложения.
    var roomAttachmentManifests: [RoomAttachmentManifest] {
        attachments.compactMap { item in
            guard let attachmentID = item.attachmentID, !attachmentID.isEmpty else { return nil }
            return RoomAttachmentManifest(
                attachmentID: attachmentID,
                kind: RoomAttachmentUpload.kind(forMIME: item.mime),
                name: item.name,
                size: item.size ?? 0,
                mime: item.mime
            )
        }
    }
}
