import XCTest
import SwiftData
@testable import HermesMobile

/// The queue had an entrance and no exit. These tests are the exit's proof: a due row is
/// sent once with its own `eventID` and disappears; a failing row stays with its reason.
@MainActor
final class RoomScheduledDeliveryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(
            for: PendingScheduledMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    private func row(dueIn seconds: TimeInterval, text: String = "later") -> PendingScheduledMessage {
        let row = PendingScheduledMessage(
            sessionId: "room:room-1", sessionTitle: "Build", draftText: text,
            scheduledAt: Date().addingTimeInterval(seconds),
            serverURLString: "https://example.test",
            eventID: "evt-1", threadID: "thread-7",
            scheduleKey: "room:room-1|evt-1"
        )
        context.insert(row)
        return row
    }

    func testADueRowIsSentOnceWithItsOwnEventIDAndLeavesTheQueue() async throws {
        _ = row(dueIn: -60)
        try context.save()

        var sent: [(room: String, eventID: String, text: String, thread: String?)] = []
        await RoomScheduledDelivery.deliverDue(in: context) { room, eventID, text, thread in
            sent.append((room, eventID, text, thread))
        }

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.room, "room-1")
        XCTAssertEqual(sent.first?.eventID, "evt-1", "the retry key must be the one created at enqueue time")
        XCTAssertEqual(sent.first?.thread, "thread-7", "a reply scheduled in a thread stays in it")
        XCTAssertTrue(RoomScheduleQueue.pending(room: room, in: context).isEmpty)
    }

    func testARowThatIsNotDueYetIsLeftAlone() async throws {
        _ = row(dueIn: 600)
        try context.save()

        var sent = 0
        await RoomScheduledDelivery.deliverDue(in: context) { _, _, _, _ in sent += 1 }
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(RoomScheduleQueue.pending(room: room, in: context).count, 1)
    }

    func testAFailureKeepsTheRowWithItsReasonAndTheSameEventID() async throws {
        _ = row(dueIn: -60)
        try context.save()

        await RoomScheduledDelivery.deliverDue(in: context) { _, _, _, _ in
            throw URLError(.notConnectedToInternet)
        }

        let kept = try XCTUnwrap(RoomScheduleQueue.pending(room: room, in: context).first)
        XCTAssertEqual(kept.failedAttemptCount, 1)
        XCTAssertEqual(kept.eventID, "evt-1", "a failed attempt must not invent a new identity")
        XCTAssertFalse(kept.isDeliveryTerminal, "a network error is retryable")
    }

    func testAChatRowIsNotTouchedByTheRoomPath() async throws {
        let chat = PendingScheduledMessage(
            sessionId: "session-1", draftText: "chat", scheduledAt: Date().addingTimeInterval(-60),
            serverURLString: "https://example.test")
        context.insert(chat)
        try context.save()

        var sent = 0
        await RoomScheduledDelivery.deliverDue(in: context) { _, _, _, _ in sent += 1 }
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingScheduledMessage>()).count, 1)
    }

    private var room: BotRoomKey {
        BotRoomKey(server: URL(string: "https://example.test")!, connectionID: UUID(), roomID: "room-1")
    }
}
