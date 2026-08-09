import Foundation
import SwiftData

@Model
final class PendingScheduledMessage {
    @Attribute(.unique) var scheduleKey: String
    var sessionId: String
    var draftText: String
    var scheduledAt: Date
    var createdAt: Date
    var serverURLString: String

    init(
        sessionId: String,
        draftText: String,
        scheduledAt: Date,
        serverURLString: String,
        createdAt: Date = Date()
    ) {
        self.scheduleKey = "\(sessionId)|\(scheduledAt.timeIntervalSince1970)"
        self.sessionId = sessionId
        self.draftText = draftText
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
        self.serverURLString = serverURLString
    }
}
