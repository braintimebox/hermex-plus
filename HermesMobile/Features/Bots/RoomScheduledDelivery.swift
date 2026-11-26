import Foundation
import SwiftData

/// Sends the room messages whose time has come.
///
/// The queue had an entrance and no exit: `enqueue` was wired to the composer, `due` was
/// called by nothing, so a scheduled room message sat in the store forever while the screen
/// promised it would go out. This is the exit.
///
/// Two rules it inherits from the model, both of which a naive loop would break:
///
/// - **One row is one `eventID`.** A retry reuses it, so `groups.send` deduplicates and the
///   room does not receive the same message twice.
/// - **It only touches room rows.** Chat rows belong to the chat dispatcher; picking one up
///   here would post a chat message into a room.
///
/// Delivery happens when the app is running. iOS gives a backgrounded app no guaranteed
/// time, and this build asks for none (`Info.plist` has no `fetch` mode and no permitted
/// `BGTaskScheduler` identifier), so a message whose time passed while the app was closed
/// goes out at the next launch. That is a platform fact to state in the notes, not a bug to
/// hide.
@MainActor
enum RoomScheduledDelivery {
    /// Sends one row. Injected so the loop can be tested without a server.
    typealias Sender = (_ roomID: String, _ eventID: String, _ text: String, _ threadID: String?) async throws -> Void

    /// Above this many failures a row stops being retried: an error that never resolves must
    /// not keep a message in flight forever.
    static let maxAttempts = 5

    static func deliverDue(
        in context: ModelContext,
        now: Date = Date(),
        sender: Sender? = nil
    ) async {
        let rows = dueRows(in: context, now: now)
        guard !rows.isEmpty else { return }
        for row in rows {
            await deliver(row, in: context, sender: sender)
        }
    }

    static func dueRows(in context: ModelContext, now: Date) -> [PendingScheduledMessage] {
        // No prefix operator in `#Predicate`; the scheduled table is small, and filtering
        // here also keeps one definition of "is a room row" (`isChatRow`).
        let descriptor = FetchDescriptor<PendingScheduledMessage>(
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.filter { !$0.isChatRow && $0.terminalFailureReason == nil && $0.scheduledAt <= now }
    }

    private static func deliver(
        _ row: PendingScheduledMessage,
        in context: ModelContext,
        sender: Sender?
    ) async {
        let roomID = String(row.sessionId.dropFirst(PendingScheduledMessage.roomSessionPrefix.count))
        // A row without an id predates the field; its schedule key is unique and stable, so
        // it can stand in without inventing a new identity per attempt.
        let eventID = row.eventID ?? row.scheduleKey
        do {
            if let sender {
                try await sender(roomID, eventID, row.draftText, row.threadID)
            } else {
                try await sendOverTheWire(row, roomID: roomID, eventID: eventID)
            }
            RoomScheduleQueue.remove(row, in: context)
        } catch {
            let attempts = row.failedAttemptCount + 1
            let terminal = attempts >= maxAttempts || !isRetryable(error)
            RoomScheduleQueue.recordFailure(
                row, reason: error.localizedDescription, terminal: terminal, in: context)
        }
    }

    private static func sendOverTheWire(
        _ row: PendingScheduledMessage,
        roomID: String,
        eventID: String
    ) async throws {
        guard let server = URL(string: row.serverURLString),
              let connection = try? BotConnectionStore().load(server: server) else {
            throw RoomScheduledDeliveryFailure.notSignedIn
        }
        let wire = BotClient(connection: connection)
        defer { wire.close() }
        try await wire.connect()
        // A room send always names a thread: the reader does the same, minting one when the
        // message is not a reply (`BotRoomReader.Send`).
        _ = try await wire.call(
            .groupsSend(roomID: roomID, eventID: eventID, text: row.draftText,
                        threadID: row.threadID ?? UUID().uuidString,
                        attachments: row.roomAttachmentManifests)
        )
    }

    private static func isRetryable(_ error: Error) -> Bool {
        // A refused sign-in or a method the host does not have will not fix itself.
        if let failure = error as? BotFailure {
            switch failure {
            case .rejected(let code): return code >= 500 || code == 429
            case .unsupported: return false
            default: return true
            }
        }
        return true
    }
}

enum RoomScheduledDeliveryFailure: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        String(localized: "Not signed in to this server any more.")
    }
}
