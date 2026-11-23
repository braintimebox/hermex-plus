import XCTest
@testable import HermesMobile

/// The dashboard mounts a plugin's API under `/api/plugins/<name>`
/// (`hermes_cli/web_server_dashboard.py:1258-1262`), and the base address may carry a
/// proxy prefix (`https://host:8443/dash`). Both facts have to hold at once, so the
/// path must be relative and under the plugin's mount point.
final class KanbanEndpointPathTests: XCTestCase {
    private let base = URL(string: "https://hermes00.duckdns.org:8443/dash")!

    func testConfigIsAskedUnderThePluginsMountPoint() {
        XCTAssertEqual(Endpoint.kanbanConfig.path, "api/plugins/kanban/config")
    }

    func testTheProxyPrefixSurvivesURLBuilding() {
        // An absolute path would resolve against the host root and drop `/dash`, which is
        // the door's only exposed subtree — that is the 404 the owner saw.
        let url = Endpoint.kanbanConfig.url(relativeTo: base)
        XCTAssertEqual(url.path, "/dash/api/plugins/kanban/config")
    }

    func testThePathIsNotAbsolute() {
        XCTAssertFalse(Endpoint.kanbanConfig.path.hasPrefix("/"))
    }
}
