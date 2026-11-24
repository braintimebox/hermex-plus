import XCTest
import SwiftData
@testable import HermesMobile

@MainActor
final class RoomScheduleQueueTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(
            for: PendingScheduledMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    private var room: BotRoomKey {
        BotRoomKey(server: URL(string: "https://example.test")!, connectionID: UUID(), roomID: "room-1")
    }

    func testARowCarriesOneEventIDCreatedAtEnqueueTime() {
        let row = RoomScheduleQueue.enqueue(
            room: room, roomName: "Build", threadID: nil, text: "later",
            dueAt: Date().addingTimeInterval(600), serverURLString: "https://example.test", in: context
        )
        let eventID = try? XCTUnwrap(row.eventID)
        XCTAssertNotNil(eventID)
        // The key is derived from the id, so it is unique by construction and does not
        // depend on the minute the user happened to pick.
        XCTAssertEqual(row.scheduleKey, "room:room-1|\(eventID ?? "")")
        XCTAssertEqual(row.sessionId, "room:room-1")
    }

    func testARetryKeepsTheSameEventIDAndOnlyCountsTheAttempt() throws {
        let row = RoomScheduleQueue.enqueue(
            room: room, roomName: "Build", threadID: "thread-7", text: "reply",
            dueAt: Date().addingTimeInterval(60), serverURLString: "https://example.test", in: context
        )
        let before = try XCTUnwrap(row.eventID)

        RoomScheduleQueue.recordFailure(row, reason: "outcome unknown", terminal: false, in: context)
        XCTAssertEqual(row.eventID, before, "a retry must reuse the id or the room gets two messages")
        XCTAssertEqual(row.failedAttemptCount, 1)
        XCTAssertNil(row.terminalFailureReason)
        XCTAssertEqual(row.threadID, "thread-7")
    }

    func testATerminalFailureKeepsTheRowWithItsReason() throws {
        let row = RoomScheduleQueue.enqueue(
            room: room, roomName: "Build", threadID: nil, text: "x",
            dueAt: Date().addingTimeInterval(60), serverURLString: "https://example.test", in: context
        )
        RoomScheduleQueue.recordFailure(row, reason: "room disbanded", terminal: true, in: context)
        XCTAssertTrue(row.isDeliveryTerminal)
        XCTAssertEqual(row.terminalFailureReason, "room disbanded")
        // Terminal rows are no longer picked up automatically, but they are still shown.
        XCTAssertEqual(RoomScheduleQueue.pending(room: room, in: context).count, 1)
        XCTAssertTrue(RoomScheduleQueue.due(room: room, at: Date().addingTimeInterval(3_600), in: context).isEmpty)
    }

    func testOneRoomsRowsAreNotAnothers() {
        let other = BotRoomKey(server: room.server, connectionID: room.connectionID, roomID: "room-2")
        RoomScheduleQueue.enqueue(room: room, roomName: "A", threadID: nil, text: "one",
                                  dueAt: Date(), serverURLString: "https://example.test", in: context)
        RoomScheduleQueue.enqueue(room: other, roomName: "B", threadID: nil, text: "two",
                                  dueAt: Date(), serverURLString: "https://example.test", in: context)

        XCTAssertEqual(RoomScheduleQueue.pending(room: room, in: context).map(\.draftText), ["one"])
        XCTAssertEqual(RoomScheduleQueue.pending(room: other, in: context).map(\.draftText), ["two"])
    }
}

/// The two delivery paths share one table, so each must be able to say which rows are not
/// its own. The failure this prevents is silent: the chat's "Scheduled Messages" screen
/// reconciles against the server's list, a room row is never on it, and the row would be
/// deleted before it was ever sent.
@MainActor
final class ScheduledRowOwnershipTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(
            for: PendingScheduledMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func testARoomRowIsNotAChatRow() {
        let room = PendingScheduledMessage(
            sessionId: "room:room-1", draftText: "x", scheduledAt: Date(),
            serverURLString: "https://example.test")
        let chat = PendingScheduledMessage(
            sessionId: "session-1", draftText: "y", scheduledAt: Date(),
            serverURLString: "https://example.test")
        XCTAssertFalse(room.isChatRow)
        XCTAssertTrue(chat.isChatRow)
    }

    func testTheChatPredicateDoesNotSeeRoomRows() throws {
        context.insert(PendingScheduledMessage(
            sessionId: "room:room-1", draftText: "room", scheduledAt: Date(),
            serverURLString: "https://example.test"))
        context.insert(PendingScheduledMessage(
            sessionId: "session-1", draftText: "chat", scheduledAt: Date(),
            serverURLString: "https://example.test"))
        try context.save()

        // Exactly the rule the chat's list and its reconcile now use.
        let visible = try context.fetch(FetchDescriptor<PendingScheduledMessage>()).filter(\.isChatRow)
        XCTAssertEqual(visible.map(\.draftText), ["chat"])

        // And the room row is still there afterwards: nothing this view does not show can
        // be deleted by it.
        let all = try context.fetch(FetchDescriptor<PendingScheduledMessage>())
        XCTAssertEqual(Set(all.map(\.draftText)), ["chat", "room"])
    }
}
