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
    /// HERMEX-FORK: the pin used to live only in a `@State` array on ChatView, so
    /// it evaporated on the way out of the chat and every pinned message had to
    /// be pinned again after a relaunch. The flag now rides on the row that
    /// already survives, so a pin can be restored on open.
    ///
    /// The default matters: a non-optional property with no default stops
    /// SwiftData's lightweight migration cold, because a row written before
    /// this column existed has nothing to fill it with. `false` is also the
    /// right answer — an old row was saved, not pinned.
    var isPinned: Bool = false

    init(
        messageId: String,
        sessionId: String,
        sessionTitle: String,
        content: String,
        author: String,
        serverURLString: String,
        sortOrder: Int = 0,
        savedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.savedKey = Self.cacheKey(messageId: messageId, serverURLString: serverURLString)
        self.messageId = messageId
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        // HERMEX-FORK: was `prefix(200)`. The truncation was fine for the Saved
        // list, where the row is a reminder that the message exists, but a pin
        // is a promise to be able to read the thing again — and 200 characters
        // cut a long answer off mid-sentence. The full text is kept now; the
        // Saved list previews with its own line limit, so nothing gets longer
        // on screen, and the only cost is the storage of text already on disk
        // once in the session cache.
        self.content = content
        self.author = author
        self.savedAt = savedAt
        self.sortOrder = sortOrder
        self.serverURLString = serverURLString
        self.isPinned = isPinned
    }

    static func cacheKey(messageId: String, serverURLString: String) -> String {
        "\(serverURLString)|saved|\(messageId)"
    }
}
