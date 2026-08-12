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

    init(
        sessionId: String,
        sessionTitle: String? = nil,
        draftText: String,
        scheduledAt: Date,
        serverURLString: String,
        createdAt: Date = Date()
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
    }
}
