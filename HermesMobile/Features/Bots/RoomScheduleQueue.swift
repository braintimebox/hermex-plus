import Foundation
import SwiftData

/// Scheduled sends for a room, on the same queue the chat uses.
///
/// There is one `PendingScheduledMessage` table, not two stores: the chat has had
/// scheduled sends since 3.9.x, including terminal-failure handling and attempt counts,
/// and a second implementation for rooms would drift from it exactly the way the room
/// composer drifted from the chat's.
///
/// Three invariants, each of which a naive port would lose:
///
/// - **One row is one `eventID`, created here and never changed.** `groups.send`
///   deduplicates by it, so a retry after an uncertain result reuses it; a new id per
///   attempt would post the message twice and every bot would answer twice.
/// - **`scheduleKey` is `"<sessionId>|<eventID>"`.** Chat keys are a link to the server's
///   scheduled list and keep their shape; a room has no such list, so its key comes from
///   the event id and is unique by construction.
/// - **`threadID` travels with the row**, so a reply written in a thread lands in it.
@MainActor
enum RoomScheduleQueue {
    static func sessionID(for room: BotRoomKey) -> String { "room:\(room.roomID)" }

    @discardableResult
    static func enqueue(
        room: BotRoomKey,
        roomName: String,
        threadID: String?,
        text: String,
        attachments: [ScheduledMessageAttachment] = [],
        dueAt: Date,
        serverURLString: String,
        in context: ModelContext
    ) -> PendingScheduledMessage {
        let sessionID = sessionID(for: room)
        let eventID = UUID().uuidString.lowercased()
        let row = PendingScheduledMessage(
            sessionId: sessionID,
            sessionTitle: roomName,
            draftText: text,
            scheduledAt: dueAt,
            serverURLString: serverURLString,
            attachments: attachments,
            eventID: eventID,
            threadID: threadID,
            scheduleKey: "\(sessionID)|\(eventID)"
        )
        context.insert(row)
        try? context.save()
        return row
    }

    /// The room's rows, oldest deadline first.
    static func pending(room: BotRoomKey, in context: ModelContext) -> [PendingScheduledMessage] {
        let sessionID = sessionID(for: room)
        let descriptor = FetchDescriptor<PendingScheduledMessage>(
            predicate: #Predicate { $0.sessionId == sessionID },
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Due rows that automatic delivery may still attempt.
    static func due(room: BotRoomKey, at now: Date = Date(), in context: ModelContext) -> [PendingScheduledMessage] {
        pending(room: room, in: context).filter { $0.scheduledAt <= now && !$0.isDeliveryTerminal }
    }

    /// A retry keeps the row's `eventID`; only the attempt count moves.
    static func recordFailure(
        _ row: PendingScheduledMessage,
        reason: String,
        terminal: Bool,
        at now: Date = Date(),
        in context: ModelContext
    ) {
        row.failedAttemptCount += 1
        if terminal {
            row.terminalFailureReason = reason
            row.terminalFailureAt = now
        }
        try? context.save()
    }

    static func remove(_ row: PendingScheduledMessage, in context: ModelContext) {
        context.delete(row)
        try? context.save()
    }
}
