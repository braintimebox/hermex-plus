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

    /// Расшифрованные вложения. Пустой массив, если поле пустое или битое —
    /// отложенное сообщение без читаемых вложений должно остаться отправляемым.
    var attachments: [ScheduledMessageAttachment] {
        guard let attachmentsJSON, let data = attachmentsJSON.data(using: .utf8) else { return [] }
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
        attachments: [ScheduledMessageAttachment] = []
    ) {
        // Unique key: sessionId + timestamp + UUID. Timestamp alone collides
        // when two messages are scheduled for the same minute (DatePicker wheel
        // zeroes seconds), which made SwiftData's @Attribute(.unique) drop the
        // second insert silently — the "message disappears" bug.
        self.scheduleKey = "\(sessionId)|\(scheduledAt.timeIntervalSince1970)|\(UUID().uuidString)"
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.draftText = draftText
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
        self.serverURLString = serverURLString
        setAttachments(attachments)
    }
}

/// HERMEX-FORK: вложение отложенного сообщения в том виде, в котором оно
/// переживает перезапуск приложения. `draftFileName` указывает на файл в
/// `ChatDraftAttachmentStore` — тот же стор, что и у черновиков, поэтому копию
/// не дублируем; вместо этого имя файла обязано попадать в `keepingReferenced`
/// при уборке (иначе sweep удалит вложение как осиротевшее).
struct ScheduledMessageAttachment: Codable, Equatable, Sendable {
    var name: String
    var path: String
    var mime: String
    var size: Int?
    var isImage: Bool
    var draftFileName: String?

    init(name: String, path: String, mime: String, size: Int?, isImage: Bool, draftFileName: String?) {
        self.name = name
        self.path = path
        self.mime = mime
        self.size = size
        self.isImage = isImage
        self.draftFileName = draftFileName
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
