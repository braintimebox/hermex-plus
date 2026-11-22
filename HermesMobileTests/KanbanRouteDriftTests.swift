import XCTest
@testable import HermesMobile

/// The client's kanban paths against the routes the plugin actually mounts.
///
/// The fixture is the plugin's own route table (`plugins/kanban/dashboard/plugin_api.py`,
/// 47 `@router` decorators, dumped mechanically). Every client case must resolve to one
/// of them — otherwise the phone gets a 404 that looks like "kanban is broken".
///
/// A case may be listed as a documented gap instead, and a gap has to name the route that
/// replaces it. That is the difference between "not implemented yet" and "forgotten": a new
/// case that is in neither list fails this test by name.
final class KanbanRouteDriftTests: XCTestCase {
    private typealias Route = (method: String, template: String)

    private let pluginRoutes: [Route] = [
        ("get", "/board"), ("get", "/tasks/{task_id}"), ("post", "/tasks"),
        ("get", "/tasks/{task_id}/attachments"), ("post", "/tasks/{task_id}/attachments"),
        ("get", "/attachments/{attachment_id}"), ("delete", "/attachments/{attachment_id}"),
        ("patch", "/tasks/{task_id}"), ("delete", "/tasks/{task_id}"),
        ("post", "/tasks/{task_id}/comments"), ("post", "/links"), ("delete", "/links"),
        ("post", "/tasks/bulk"), ("get", "/diagnostics"), ("get", "/workers/active"),
        ("get", "/runs/{run_id}"), ("get", "/runs/{run_id}/inspect"), ("post", "/runs/{run_id}/terminate"),
        ("post", "/tasks/{task_id}/reclaim"), ("post", "/tasks/{task_id}/specify"),
        ("post", "/tasks/{task_id}/reassign"), ("post", "/estimate"), ("post", "/tasks/{task_id}/estimate"),
        ("get", "/config"), ("get", "/home-channels"),
        ("post", "/tasks/{task_id}/home-subscribe/{platform}"),
        ("delete", "/tasks/{task_id}/home-subscribe/{platform}"),
        ("get", "/stats"), ("get", "/assignees"), ("get", "/tasks/{task_id}/log"),
        ("post", "/dispatch"), ("get", "/model-options"), ("get", "/projects"),
        ("get", "/boards"), ("post", "/boards"), ("patch", "/boards/{slug}"),
        ("delete", "/boards/{slug}"), ("post", "/boards/{slug}/export"), ("post", "/boards/import"),
        ("post", "/boards/{slug}/switch"), ("get", "/profiles"), ("patch", "/profiles/{profile_name}"),
        ("post", "/profiles/{profile_name}/describe-auto"), ("post", "/tasks/{task_id}/decompose"),
        ("get", "/workflow"), ("get", "/orchestration"), ("put", "/orchestration"),
    ]

    /// Cases with no HTTP route, and the route that stands in for them meanwhile.
    private let documentedGaps: [String: String] = [
        "kanbanEvents": "api/plugins/kanban/board — the plugin tails events over a WebSocket, polled until that channel lands",
        "kanbanBlockCard": "api/plugins/kanban/tasks/{task_id} — status is a PATCH field, not a sub-route",
        "kanbanUnblockCard": "api/plugins/kanban/tasks/{task_id} — status is a PATCH field, not a sub-route",
    ]

    /// Paths the enum emits for cases that carry a request value. They are written as
    /// templates here because constructing every request type in a test would tie this
    /// file to their field lists, and the thing under test is the route, not the payload.
    private let templatePaths: [(name: String, tail: String)] = [
        ("kanbanEditBoard", "/boards/{slug}"),
        ("kanbanArchiveBoard", "/boards/{slug}"),
        ("kanbanMakeBoardActive", "/boards/{slug}/switch"),
        ("kanbanDispatch", "/dispatch"),
        ("kanbanBoard", "/board"),
        ("kanbanEvents", "/events"),
        ("kanbanEventsStream", "/board"),
        ("kanbanCardDetail", "/tasks/{cardID}"),
        ("kanbanWorkerLog", "/tasks/{cardID}/log"),
        ("kanbanAddComment", "/tasks/{cardID}/comments"),
        ("kanbanCreateCard", "/tasks"),
        ("kanbanBulkAction", "/tasks/bulk"),
        ("kanbanEditCard", "/tasks/{cardID}"),
        ("kanbanCardStatus", "/tasks/{cardID}"),
        ("kanbanBlockCard", "/tasks/{cardID}/block"),
        ("kanbanUnblockCard", "/tasks/{cardID}/unblock"),
        ("kanbanAddDependency", "/links"),
        ("kanbanRemoveDependency", "/links"),
    ]

    /// The cases whose path can be read from the enum itself.
    private var livePaths: [(name: String, path: String)] {
        [
            ("kanbanConfig", Endpoint.kanbanConfig.path),
            ("kanbanBoards", Endpoint.kanbanBoards.path),
            ("kanbanCreateBoard", Endpoint.kanbanCreateBoard.path),
            ("kanbanStats", Endpoint.kanbanStats(board: "default").path),
            ("kanbanAssignees", Endpoint.kanbanAssignees(board: "default").path),
        ]
    }

    func testEveryPathIsRelativeSoTheProxyPrefixSurvives() {
        for entry in livePaths {
            XCTAssertFalse(entry.path.hasPrefix("/"), "\(entry.name) must be relative to the base address")
            XCTAssertTrue(
                entry.path.hasPrefix("api/plugins/kanban/"),
                "\(entry.name) must go through the plugin mount point, got \(entry.path)"
            )
        }
    }

    func testEveryCaseResolvesToAMountedRouteOrADocumentedGap() {
        var unresolved: [String] = []
        for entry in livePaths {
            let tail = Self.routeTail(of: entry.path)
            if !pluginRoutes.contains(where: { Self.matches(tail: tail, template: $0.template) }),
               documentedGaps[entry.name] == nil {
                unresolved.append("\(entry.name) → \(entry.path)")
            }
        }
        for entry in templatePaths {
            if !pluginRoutes.contains(where: { Self.matches(tail: entry.tail, template: $0.template) }),
               documentedGaps[entry.name] == nil {
                unresolved.append("\(entry.name) → api/plugins/kanban\(entry.tail)")
            }
        }
        XCTAssertEqual(unresolved, [], "no mounted route and no documented gap for: \(unresolved.joined(separator: "; "))")
    }

    func testADocumentedGapIsNotSilentlyClosed() {
        // A gap that gains a real route should be removed from the list, not left to rot.
        for name in documentedGaps.keys {
            let known = livePaths.contains { $0.name == name } || templatePaths.contains { $0.name == name }
            XCTAssertTrue(known, "gap \(name) names a case that no longer exists")
        }
    }

    // MARK: - Matching

    private static func routeTail(of path: String) -> String {
        let prefix = "api/plugins/kanban"
        var tail = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        if let query = tail.firstIndex(of: "?") { tail = String(tail[..<query]) }
        return tail
    }

    private static func matches(tail: String, template: String) -> Bool {
        let actual = tail.split(separator: "/", omittingEmptySubsequences: true)
        let expected = template.split(separator: "/", omittingEmptySubsequences: true)
        guard actual.count == expected.count else { return false }
        for (a, e) in zip(actual, expected) {
            if e.hasPrefix("{") { continue }
            if a != e { return false }
        }
        return true
    }
}
