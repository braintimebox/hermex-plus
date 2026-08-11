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
        self.scheduleKey = "\(sessionId)|\(scheduledAt.timeIntervalSince1970)"
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.draftText = draftText
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
        self.serverURLString = serverURLString
    }
}
