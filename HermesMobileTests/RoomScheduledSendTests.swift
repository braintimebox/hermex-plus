import XCTest
@testable import HermesMobile

@MainActor
final class RoomScheduledSendTests: XCTestCase {
    private var directory: URL!
    private var store: RoomScheduledStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = RoomScheduledStore(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var room: BotRoomKey {
        BotRoomKey(server: URL(string: "https://mac.example")!, connectionID: connectionID, roomID: "room-1")
    }

    private let connectionID = UUID()

    private func file(_ name: String, bytes: Int) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 4, count: bytes).write(to: url)
        return url
    }

    private func budget(files: [(String, Int)]) throws -> RoomAttachmentBudget {
        var budget = RoomAttachmentBudget()
        for (name, bytes) in files {
            try budget.add(contentsOf: try file(name, bytes: bytes))
        }
        return budget
    }

    func testAScheduledMessageKeepsReferencesNotBytes() throws {
        let ready = try budget(files: [("photo.jpg", 12_000)])
        let item = try store.enqueue(
            room: room,
            roomName: "Build",
            threadID: nil,
            text: "later",
            budget: ready,
            dueAt: Date().addingTimeInterval(3_600)
        )

        // The point of the design: an upload expires in an hour, so nothing is uploaded
        // at enqueue time and the file is remembered by path.
        XCTAssertEqual(item.attachments.count, 1)
        XCTAssertEqual(item.attachments[0].name, "photo.jpg")
        XCTAssertEqual(item.attachments[0].byteCount, 12_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.attachments[0].path))
        XCTAssertEqual(item.byteCount, 12_000)
        XCTAssertEqual(item.attempts, 0)
        XCTAssertNil(item.lastFailure)
    }

    func testEmptyMessageAndPastTimeAreRefusedBeforeAnythingIsStored() throws {
        XCTAssertThrowsError(
            try store.enqueue(room: room, roomName: "Build", threadID: nil, text: "   ",
                              budget: RoomAttachmentBudget(), dueAt: Date().addingTimeInterval(60))
        ) { error in
            XCTAssertEqual(error as? RoomScheduleFailure, .nothingToSend)
        }

        XCTAssertThrowsError(
            try store.enqueue(room: room, roomName: "Build", threadID: nil, text: "hi",
                              budget: RoomAttachmentBudget(), dueAt: Date().addingTimeInterval(-60))
        ) { error in
            XCTAssertEqual(error as? RoomScheduleFailure, .inThePast)
        }
        XCTAssertTrue(store.items.isEmpty)
    }

    func testTheWholeSelectionIsValidatedBeforeItIsQueued() throws {
        var over = RoomAttachmentBudget()
        for index in 1...8 {
            try over.add(contentsOf: try file("f\(index).bin", bytes: 3_000_000))
        }
        XCTAssertThrowsError(try over.add(contentsOf: try file("f9.bin", bytes: 10)))

        // A refused file never reaches the queue, so a scheduled send cannot be born
        // in a state `groups.send` would reject.
        XCTAssertEqual(over.uploads.count, 8)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testDueMessagesComeBackInTimeOrderAndNotBefore() throws {
        let now = Date()
        let early = try store.enqueue(room: room, roomName: "A", threadID: nil, text: "early",
                                      budget: RoomAttachmentBudget(), dueAt: now.addingTimeInterval(60))
        let late = try store.enqueue(room: room, roomName: "A", threadID: nil, text: "late",
                                     budget: RoomAttachmentBudget(), dueAt: now.addingTimeInterval(120))

        XCTAssertTrue(store.due(at: now).isEmpty)
        let due = store.due(at: now.addingTimeInterval(90))
        XCTAssertEqual(due.map(\.id), [early.id])
        XCTAssertEqual(store.due(at: now.addingTimeInterval(300)).map(\.id), [early.id, late.id])
    }

    func testAFailureIsRememberedAndADeliveryRemovesTheItem() throws {
        let item = try store.enqueue(room: room, roomName: "A", threadID: nil, text: "x",
                                     budget: RoomAttachmentBudget(), dueAt: Date().addingTimeInterval(60))
        store.fail(item.id, reason: "attachment expired")
        XCTAssertEqual(store.items.first?.attempts, 1)
        XCTAssertEqual(store.items.first?.lastFailure, "attachment expired")

        store.complete(item.id)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testAQueueSurvivesTheAppBeingKilled() throws {
        try store.enqueue(room: room, roomName: "A", threadID: "t1", text: "survive",
                          budget: RoomAttachmentBudget(), dueAt: Date().addingTimeInterval(600))

        let reopened = RoomScheduledStore(directory: directory)
        XCTAssertEqual(reopened.items.count, 1)
        XCTAssertEqual(reopened.items.first?.text, "survive")
        XCTAssertEqual(reopened.items.first?.threadID, "t1")
        XCTAssertEqual(reopened.count(for: room), 1)
    }

    func testClearingOneRoomLeavesOtherRoomsAlone() throws {
        let other = BotRoomKey(server: URL(string: "https://mac.example")!, connectionID: connectionID, roomID: "room-2")
        try store.enqueue(room: room, roomName: "A", threadID: nil, text: "one",
                          budget: RoomAttachmentBudget(), dueAt: Date().addingTimeInterval(60))
        try store.enqueue(room: other, roomName: "B", threadID: nil, text: "two",
                          budget: RoomAttachmentBudget(), dueAt: Date().addingTimeInterval(60))

        store.removeAll(for: room)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.roomID, "room-2")
    }

    func testTheBudgetSummaryNamesTheRemainderForThePicker() throws {
        let ready = try budget(files: [("a.bin", 10_000_000)])
        let summary = ready.remainingSummary
        XCTAssertTrue(summary.contains("10"), summary)
        XCTAssertTrue(summary.contains("25"), summary)
        XCTAssertEqual(ready.remainingBytes, RoomAttachmentLimit.messageBytes - 10_000_000)
        XCTAssertEqual(ready.remainingFiles, RoomAttachmentLimit.filesPerMessage - 1)
    }
}
