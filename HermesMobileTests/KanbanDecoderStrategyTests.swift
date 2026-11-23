import XCTest
@testable import HermesMobile

/// The kanban models read `is_current` as `isCurrent` and nothing in the type says so:
/// it works only because the client decodes with `.convertFromSnakeCase`
/// (`APIClient.swift:56-57`) and `kanbanJSON` goes through that decoder. A second decoder
/// with a different strategy would not fail — the active board would simply stop being
/// highlighted, with no error anywhere.
final class KanbanDecoderStrategyTests: XCTestCase {
    /// The client's strategy, reproduced: `.convertFromSnakeCase` on the keys
    /// (`APIClient.swift:56-57`). If this drifts from the client, these tests stop
    /// describing the app — which is why they spell the strategy out.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    func testTheActiveBoardSurvivesSnakeCaseConversion() throws {
        let json = """
        {"boards":[{"slug":"default","name":"Default","is_current":true},
                   {"slug":"lab","name":"Lab","is_current":false}],
         "current":"default"}
        """
        let response = try Self.decoder.decode(KanbanBoardsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.current, "default")
        XCTAssertEqual(response.boards?.map(\.isCurrent), [true, false])
    }

    func testTheCamelCaseSpellingIsNotWhatTheServerSends() throws {
        // If someone "fixes" the model to expect `isCurrent` on the wire, this fails instead
        // of the highlight silently disappearing in the app.
        let json = #"{"boards":[{"slug":"default","name":"Default","isCurrent":true}],"current":"default"}"#
        let response = try Self.decoder.decode(KanbanBoardsResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.boards?.first?.isCurrent, "the server sends is_current; isCurrent must decode to nil")
    }

    func testAnEmptyStringIsNoValueAtTheBoundary() throws {
        // The plugin defaults description/icon/color to "" (kanban_db_boards.py:44-48). If the
        // model keeps "", every screen has to remember that "" means "none" — and an icon of
        // "" draws an empty square instead of nothing.
        let json = #"{"boards":[{"slug":"default","name":"Default","description":"","icon":"","color":""}],"current":"default"}"#
        let board = try XCTUnwrap(
            Self.decoder.decode(KanbanBoardsResponse.self, from: Data(json.utf8)).boards?.first)
        XCTAssertNil(board.description)
        XCTAssertNil(board.icon)
        XCTAssertNil(board.color)
    }

    func testAMissingReadOnlyFlagMeansEditable() throws {
        // There is no read-only board on the server (`grep read_only` in kanban_db_boards.py
        // and plugin_api.py: zero), so a nil here means "this cannot happen", not "unknown".
        let json = #"{"boards":[{"slug":"default","name":"Default"}],"current":"default"}"#
        let board = try XCTUnwrap(
            Self.decoder.decode(KanbanBoardsResponse.self, from: Data(json.utf8)).boards?.first)
        XCTAssertFalse(board.isReadOnly)
    }
}
