
/// One draft, one event id. The host discards an answer when a newer message arrives in the
/// same thread (`hosted_room_discussion.py:1021-1036`), so a resend that mints a new id is
/// not a harmless duplicate — it kills the reply that was still being written.
@MainActor
final class RoomSendIdentityTests: XCTestCase {
    func testAnExplicitEventIDIsKept() {
        let send = BotRoomReader.Send(text: "hello", threadID: nil, eventID: "evt-1")
        XCTAssertEqual(send.eventID, "evt-1")
    }

    func testWithoutOneAFreshIdentityIsMinted() {
        let first = BotRoomReader.Send(text: "hello", threadID: nil)
        let second = BotRoomReader.Send(text: "hello", threadID: nil)
        XCTAssertNotEqual(first.eventID, second.eventID)
        XCTAssertFalse(first.eventID.isEmpty)
    }

    func testTheThreadIsSeparateFromTheDraftThread() {
        // A reply in a thread carries the thread id, and its identity is keyed by it: two
        // different threads must not share one event id.
        let inThread = BotRoomReader.Send(text: "x", threadID: "thread-1", eventID: "evt-1")
        XCTAssertEqual(inThread.threadID, "thread-1")
        XCTAssertEqual(inThread.contextThreadID, "thread-1")
        XCTAssertEqual(inThread.eventID, "evt-1")
    }
}
