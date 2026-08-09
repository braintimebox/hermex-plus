import Foundation
import SwiftData

@Model
final class SavedMessage {
    @Attribute(.unique) var savedKey: String
    var messageId: String
    var sessionId: String
    var sessionTitle: String
    var content: String
    var author: String
    var savedAt: Date
    var sortOrder: Int
    var serverURLString: String

    init(
        messageId: String,
        sessionId: String,
        sessionTitle: String,
        content: String,
        author: String,
        serverURLString: String,
        sortOrder: Int = 0,
        savedAt: Date = Date()
    ) {
        self.savedKey = Self.cacheKey(messageId: messageId, serverURLString: serverURLString)
        self.messageId = messageId
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.content = String(content.prefix(200))
        self.author = author
        self.savedAt = savedAt
        self.sortOrder = sortOrder
        self.serverURLString = serverURLString
    }

    static func cacheKey(messageId: String, serverURLString: String) -> String {
        "\(serverURLString)|saved|\(messageId)"
    }
}
