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
