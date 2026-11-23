import Foundation
import SwiftData

/// A pinned message in a room, carried by the row the chat already uses.
///
/// There is no `groups.pin` on the gateway, so a room pin cannot be a server fact. It is
/// still not a new store: `SavedMessage` already survives a relaunch and already carries
/// `isPinned`, and a second table would drift from it the way the room composer drifted
/// from the chat's.
///
/// The room is identified by `sessionId = "room:<roomID>"`. That matters for one
/// non-obvious reason: the chat rewrites pins for *its* rows on every toggle, with the
/// predicate `sessionId == sessionID && serverURLString == serverKey`
/// (`ChatView.persistPinnedState`). Because the room's id never equals a session id,
/// opening a chat cannot clear a room's pins — and `RoomPinsTests` pins that behaviour so
/// a future edit to either side fails loudly instead of silently unpinning rooms.
@MainActor
enum RoomPins {
    static func sessionID(for room: BotRoomKey) -> String { "room:\(room.roomID)" }

    static func pinned(room: BotRoomKey, serverURLString: String, in context: ModelContext) -> [SavedMessage] {
        let sessionID = sessionID(for: room)
        let descriptor = FetchDescriptor<SavedMessage>(
            predicate: #Predicate { $0.sessionId == sessionID && $0.serverURLString == serverURLString && $0.isPinned }
        )
        return ((try? context.fetch(descriptor)) ?? []).sorted { $0.savedAt > $1.savedAt }
    }

    static func isPinned(messageID: String, room: BotRoomKey, serverURLString: String, in context: ModelContext) -> Bool {
        row(messageID: messageID, serverURLString: serverURLString, in: context)?.isPinned ?? false
    }

    /// Pins or unpins one message. A pin without a prior save writes the row, which is
    /// what makes the pin survive the app being killed.
    static func setPinned(
        _ pinned: Bool,
        messageID: String,
        room: BotRoomKey,
        roomName: String,
        content: String,
        author: String,
        serverURLString: String,
        in context: ModelContext
    ) {
        if let existing = row(messageID: messageID, serverURLString: serverURLString, in: context) {
            // A row saved by the chat for the same message is the same row: the unique key
            // is server + message, not session + message.
            existing.isPinned = pinned
        } else if pinned {
            context.insert(
                SavedMessage(
                    messageId: messageID,
                    sessionId: sessionID(for: room),
                    sessionTitle: roomName,
                    content: content,
                    author: author,
                    serverURLString: serverURLString,
                    isPinned: true
                )
            )
        }
        try? context.save()
    }

    private static func row(messageID: String, serverURLString: String, in context: ModelContext) -> SavedMessage? {
        let key = SavedMessage.cacheKey(messageId: messageID, serverURLString: serverURLString)
        var descriptor = FetchDescriptor<SavedMessage>(predicate: #Predicate { $0.savedKey == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
