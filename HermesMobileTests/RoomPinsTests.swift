import XCTest
import SwiftData
@testable import HermesMobile

@MainActor
final class RoomPinsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let server = "https://example.test"

    override func setUp() async throws {
        container = try ModelContainer(
            for: SavedMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    private var room: BotRoomKey {
        BotRoomKey(server: URL(string: server)!, connectionID: UUID(), roomID: "room-1")
    }

    func testAPinIsWrittenSoItSurvivesARelaunch() {
        RoomPins.setPinned(true, messageID: "msg-1", room: room, roomName: "Build",
                           content: "hello", author: "Hermes", serverURLString: server, in: context)

        XCTAssertTrue(RoomPins.isPinned(messageID: "msg-1", room: room, serverURLString: server, in: context))
        XCTAssertEqual(RoomPins.pinned(room: room, serverURLString: server, in: context).map(\.messageId), ["msg-1"])
        // The row, not a `@State` array: the pin is a property of something on disk.
        XCTAssertEqual(RoomPins.pinned(room: room, serverURLString: server, in: context).first?.sessionId, "room:room-1")
    }

    func testUnpinningKeepsTheRowButDropsTheFlag() {
        RoomPins.setPinned(true, messageID: "msg-1", room: room, roomName: "Build",
                           content: "hello", author: "Hermes", serverURLString: server, in: context)
        RoomPins.setPinned(false, messageID: "msg-1", room: room, roomName: "Build",
                           content: "hello", author: "Hermes", serverURLString: server, in: context)

        XCTAssertFalse(RoomPins.isPinned(messageID: "msg-1", room: room, serverURLString: server, in: context))
        XCTAssertTrue(RoomPins.pinned(room: room, serverURLString: server, in: context).isEmpty)
        // Still saved: unpinning a message must not delete it from the Saved list.
        XCTAssertNotNil(try? context.fetch(FetchDescriptor<SavedMessage>()).first)
    }

    func testAChatCannotClearARoomsPins() throws {
        RoomPins.setPinned(true, messageID: "msg-room", room: room, roomName: "Build",
                           content: "room pin", author: "Hermes", serverURLString: server, in: context)
        // A chat row in the same server, pinned by the chat.
        context.insert(SavedMessage(messageId: "msg-chat", sessionId: "session-9", sessionTitle: "Chat",
                                    content: "chat pin", author: "Hermes", serverURLString: server, isPinned: true))
        try context.save()

        // What `ChatView.persistPinnedState` does: rewrite the flags of its own rows only.
        let chatSession = "session-9"
        let descriptor = FetchDescriptor<SavedMessage>(
            predicate: #Predicate { $0.sessionId == chatSession && $0.serverURLString == server }
        )
        for row in try context.fetch(descriptor) { row.isPinned = false }
        try context.save()

        XCTAssertTrue(
            RoomPins.isPinned(messageID: "msg-room", room: room, serverURLString: server, in: context),
            "the chat's predicate is scoped to its own sessionId; a room pin must survive it"
        )
        XCTAssertFalse(RoomPins.isPinned(messageID: "msg-chat", room: room, serverURLString: server, in: context))
    }

    func testOneRoomsPinsAreNotAnothers() {
        let other = BotRoomKey(server: room.server, connectionID: room.connectionID, roomID: "room-2")
        RoomPins.setPinned(true, messageID: "msg-1", room: room, roomName: "A",
                           content: "a", author: "Hermes", serverURLString: server, in: context)
        XCTAssertTrue(RoomPins.pinned(room: other, serverURLString: server, in: context).isEmpty)
    }
}
