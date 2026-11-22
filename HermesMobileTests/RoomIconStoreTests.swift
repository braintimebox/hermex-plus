import XCTest
import UIKit
@testable import HermesMobile

/// The library is a contract, not a suggestion: a name that does not resolve in
/// the running system draws an empty square, and nothing else in the app can
/// notice. These tests are the only check that exists without a device.
final class RoomIconStoreTests: XCTestCase {

    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("room-icons-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("room-icons.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func key(room: String = "room-1") -> BotRoomKey {
        BotRoomKey(server: URL(string: "https://webui.example")!, connectionID: UUID(), roomID: room)
    }

    // MARK: - The allowlist

    @MainActor
    func testEveryGlyphResolvesInTheRunningSystem() {
        for glyph in RoomIconLibrary.allGlyphs {
            XCTAssertNotNil(UIImage(systemName: glyph), "SF Symbol \(glyph) does not resolve on this OS")
        }
    }

    func testLibraryIsThirtyGlyphsInSixCategoriesOfFive() {
        XCTAssertEqual(RoomIconLibrary.glyphCount, 30)
        XCTAssertEqual(RoomIconLibrary.categories.count, 6)
        for category in RoomIconLibrary.categories {
            XCTAssertEqual(category.glyphs.count, 5, "category \(category.title) lost or gained a glyph")
        }
    }

    func testNoGlyphAppearsInTwoCategories() {
        let all = RoomIconLibrary.allGlyphs
        XCTAssertEqual(all.count, Set(all).count, "a glyph is listed twice, so the picker shows a duplicate")
    }

    // MARK: - Choice

    @MainActor
    func testNoChoiceMeansFaces() {
        let store = RoomIconStore(fileURL: fileURL)
        XCTAssertNil(store.icon(for: key()))
    }

    @MainActor
    func testChosenGlyphSurvivesANewInstance() {
        let room = key()
        RoomIconStore(fileURL: fileURL).setIcon("hammer.fill", for: room)
        XCTAssertEqual(RoomIconStore(fileURL: fileURL).icon(for: room), "hammer.fill")
    }

    /// "Restore default" is a removal, not a default glyph: a room that never had
    /// a choice must look exactly the same after the feature ships.
    @MainActor
    func testClearingRemovesTheEntryRatherThanWritingADefault() {
        let store = RoomIconStore(fileURL: fileURL)
        let room = key()
        store.setIcon("leaf.fill", for: room)
        store.clearIcon(for: room)
        XCTAssertNil(store.icon(for: room))
        let raw = try? String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(raw?.contains("leaf.fill") ?? false, "the cleared glyph is still on disk")
    }

    @MainActor
    func testUnknownGlyphIsNeitherStoredNorDrawn() throws {
        let store = RoomIconStore(fileURL: fileURL)
        let room = key()
        store.setIcon("definitely.not.a.symbol", for: room)
        XCTAssertNil(store.icon(for: room))
        // A file written by a later version must degrade to faces, not to a blank square.
        try #"{"https://webui.example|\#(room.connectionID.uuidString)|room-1":"future.glyph"}"#
            .write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertNil(RoomIconStore(fileURL: fileURL).icon(for: room))
    }

    @MainActor
    func testRoomsAreIndependent() {
        let store = RoomIconStore(fileURL: fileURL)
        let a = key(room: "a"), b = key(room: "b")
        store.setIcon("star.fill", for: a)
        XCTAssertNil(store.icon(for: b))
        store.setIcon("flame.fill", for: b)
        XCTAssertEqual(store.icon(for: a), "star.fill")
    }

    /// Disbanding a connection's rooms must not leave an orphaned file that grows
    /// with every room ever created.
    @MainActor
    func testRemovingAConnectionDropsOnlyItsRooms() {
        let store = RoomIconStore(fileURL: fileURL)
        let connection = UUID()
        let mine = BotRoomKey(server: URL(string: "https://webui.example")!, connectionID: connection, roomID: "r1")
        let other = BotRoomKey(server: URL(string: "https://webui.example")!, connectionID: UUID(), roomID: "r1")
        store.setIcon("cpu.fill", for: mine)
        store.setIcon("map.fill", for: other)
        store.removeAll(server: mine.server, connectionID: connection)
        XCTAssertNil(store.icon(for: mine))
        XCTAssertEqual(store.icon(for: other), "map.fill")
    }
}
