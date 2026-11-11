import XCTest
@testable import HermesMobile

@MainActor final class BotDraftTests: XCTestCase {
    private let one = URL(string: "https://one.example")!
    private let two = URL(string: "https://two.example")!

    func testDiskRoundTripSeparatesServersConnectionsProfilesAndWebui() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ChatDraftFilePersistence(directoryURL: directory)
        let connection = UUID()
        let keys: [ChatDraftKey] = [
            .bot(server: one, connectionID: connection, profile: "same"),
            .bot(server: two, connectionID: connection, profile: "same"),
            .bot(server: one, connectionID: UUID(), profile: "same"),
            .bot(server: one, connectionID: connection, profile: "other"),
            .session(server: one, sessionID: "same"), .newChat(server: one)
        ]
        let drafts = ChatDraftStore(persistence: persistence, debounceDuration: .seconds(60))
        for (index, key) in keys.enumerated() { drafts.setDraft("draft \(index)", for: key) }
        drafts.setBotSubmissionUncertain(true, for: keys[0])
        try await drafts.flush()
        let restored = await persistence.load()
        XCTAssertEqual(restored.count, keys.count)
        for (index, key) in keys.enumerated() {
            XCTAssertEqual(restored[key]?.text, "draft \(index)")
            XCTAssertEqual(restored[key]?.botSubmissionUncertain, index == 0)
        }
        await drafts.discardBotDrafts(server: one, connectionID: connection)
        try await drafts.flush()
        let afterConnectionRemoval = await persistence.load()
        XCTAssertNil(afterConnectionRemoval[keys[0]])
        XCTAssertNil(afterConnectionRemoval[keys[3]])
        XCTAssertNotNil(afterConnectionRemoval[keys[1]])
        XCTAssertNotNil(afterConnectionRemoval[keys[2]])
        XCTAssertNotNil(afterConnectionRemoval[keys[4]])
        await drafts.discardDrafts(for: one)
        try await drafts.flush()
        let afterServerRemoval = await persistence.load()
        XCTAssertEqual(Set(afterServerRemoval.keys), [keys[1]])
    }

    func testOlderDraftCodecAndMalformedBotRecordsPreserveWebui() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let draftDirectory = directory.appendingPathComponent("ChatDrafts")
        try FileManager.default.createDirectory(at: draftDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let json = """
        {"version": 3, "drafts": [
          {"serverID":"https://one.example", "context":"session", "sessionID":"same", "text":"old webui"},
          {"serverID":"https://one.example", "context":"bot", "connectionID":"\(id)", "profile":"same", "text":"held", "botSubmissionUncertain":"malformed"},
          {"serverID":"https://one.example", "context":"bot", "connectionID":"not-uuid", "profile":"same", "text":"bad identity"},
          {"serverID":"https://one.example", "context":"future", "text":"unknown"}
        ]}
        """
        try Data(json.utf8).write(to: draftDirectory.appendingPathComponent("drafts.json"))
        let restored = await ChatDraftFilePersistence(directoryURL: directory).load()
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[.session(server: one, sessionID: "same")]?.text, "old webui")
        XCTAssertTrue(restored[.bot(server: one, connectionID: id, profile: "same")]?.botSubmissionUncertain == true)
    }

    func testConnectionKeychainScopesAndRemoval() throws {
        let keychain = InMemoryKeychainStore()
        let store = BotConnectionStore(keychain: keychain)
        let first = BotConnection(id: UUID(), name: "One", address: try BotConnection.address("http://hermes.local:9120"), username: "first", password: "fixture-one")
        let second = BotConnection(id: UUID(), name: "Two", address: first.address, username: "second", password: "fixture-two")
        try store.save(first, server: one)
        try store.save(second, server: two)
        XCTAssertEqual(try store.load(server: one), first)
        XCTAssertEqual(try store.load(server: two), second)
        try store.remove(server: one)
        XCTAssertNil(try store.load(server: one))
        XCTAssertEqual(try store.load(server: two), second)
    }

    func testAddressValidationAndOptionalRosterMetadata() throws {
        for text in ["https://user:password@host", "https://host?ticket=x", "file:///tmp/host", "https://host#x", "https://host/dash//api"] {
            XCTAssertThrowsError(try BotConnection.address(text))
        }
        XCTAssertEqual(try BotConnection.address(" HTTP://HERMES.LOCAL:9120/ ").absoluteString, "http://hermes.local:9120")
        // A reverse-proxy prefix is the one path form the form now keeps.
        XCTAssertEqual(try BotConnection.address("https://host/dash").absoluteString, "https://host/dash")
        let profile = try XCTUnwrap(BotProfile(.object(["name": .string("same"), "future": .array([])])))
        XCTAssertEqual(profile.name, "same")
        XCTAssertNil(profile.preview)
        XCTAssertNil(profile.lastActive)
    }
}

/// A Hermes dashboard may be served under a reverse-proxy prefix: the host publishes that
/// form as `dashboard.public_url` (`https://host:8443/dash`), the browser signs in there, and
/// the cookies it receives carry `Path=/dash`. Every Bot request is built by appending its own
/// route to the connection's address, so the prefix has to survive parsing and appear exactly
/// once per request. This pins that contract for the REST routes and the gateway socket.
final class BotDashboardPrefixTests: XCTestCase {
    private func root() throws -> URL { try BotConnection.address("https://example.com:9119") }
    private func prefixed() throws -> URL { try BotConnection.address("https://example.com:8443/dash") }

    // MARK: Parsing

    func testPrefixIsKeptAndTrailingSlashesGo() throws {
        XCTAssertEqual(try BotConnection.address("https://example.com:8443/dash/").absoluteString,
                       "https://example.com:8443/dash")
        XCTAssertEqual(BotConnection.prefix(try prefixed()), "/dash")
    }

    func testRootDashboardStillHasNoPath() throws {
        XCTAssertEqual(try BotConnection.address("https://example.com:9119/").absoluteString,
                       "https://example.com:9119")
        XCTAssertEqual(BotConnection.prefix(try root()), "")
    }

    func testPageLinkReducesToThePrefix() throws {
        XCTAssertEqual(try BotConnection.address("https://example.com:8443/dash/login").absoluteString,
                       "https://example.com:8443/dash")
        XCTAssertEqual(try BotConnection.address("https://example.com:8443/dash/sessions/abc").absoluteString,
                       "https://example.com:8443/dash")
        XCTAssertEqual(try BotConnection.address("https://example.com:8443/api").absoluteString,
                       "https://example.com:8443")
    }

    func testDoubledPrefixCollapses() throws {
        XCTAssertEqual(try BotConnection.address("https://example.com:8443/dash/dash").absoluteString,
                       "https://example.com:8443/dash")
    }

    func testEmptySegmentIsRefused() {
        XCTAssertThrowsError(try BotConnection.address("https://example.com:8443/dash//api")) { error in
            XCTAssertTrue(error is BotAddressError, "expected a BotAddressError, got \(error)")
        }
    }

    // MARK: Requests

    func testEveryRESTRouteInheritsThePrefix() throws {
        let base = try prefixed()
        func url(_ rest: HermesREST) throws -> String {
            try XCTUnwrap(try rest.request(base: base).url?.absoluteString)
        }
        XCTAssertEqual(try url(.status), "https://example.com:8443/dash/api/status")
        XCTAssertEqual(try url(.login(username: "u", password: "p")),
                       "https://example.com:8443/dash/auth/password-login")
        XCTAssertEqual(try url(.identity), "https://example.com:8443/dash/api/auth/me")
        XCTAssertEqual(try url(.ticket), "https://example.com:8443/dash/api/auth/ws-ticket")
        XCTAssertEqual(try url(.pluginsHub), "https://example.com:8443/dash/api/dashboard/plugins/hub")
        XCTAssertEqual(try url(.setEnvironment(key: "K", value: "V")),
                       "https://example.com:8443/dash/api/env")
        XCTAssertEqual(try url(.deleteProfile(name: "work")),
                       "https://example.com:8443/dash/api/profiles/work")
    }

    func testRootRoutesAreUnchanged() throws {
        let base = try root()
        XCTAssertEqual(try HermesREST.status.request(base: base).url?.absoluteString,
                       "https://example.com:9119/api/status")
        XCTAssertEqual(try HermesREST.ticket.request(base: base).url?.absoluteString,
                       "https://example.com:9119/api/auth/ws-ticket")
    }

    func testGatewaySocketInheritsThePrefix() throws {
        let request = try HermesREST.gatewayUpgrade(base: try prefixed(), ticket: "abc")
        XCTAssertEqual(request.url?.absoluteString, "wss://example.com:8443/dash/api/ws")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"),
                       "hermes-gateway-v1, hermes-gateway-ticket.abc")
    }

    func testNoRequestGainsADoubledDash() throws {
        let base = try BotConnection.address("https://example.com:8443/dash/dash/")
        let url = try XCTUnwrap(try HermesREST.status.request(base: base).url?.absoluteString)
        XCTAssertEqual(url, "https://example.com:8443/dash/api/status")
        XCTAssertFalse(url.contains("/dash/dash/"))
    }

    // MARK: Artifacts

    func testPastedDownloadURLKeepsOnlyItsPath() throws {
        let prefixedLink = "https://example.com:8443/dash/api/fs/download?path=%2Ftmp%2Fa.png&profile=work&session_id=s1"
        XCTAssertEqual(try BotArtifactReference.path(prefixedLink, address: try prefixed()), "/tmp/a.png")

        // A root install still recognises its own link, which carries no prefix.
        let rootLink = "https://example.com:8443/api/fs/download?path=%2Ftmp%2Fb.png&profile=work&session_id=s1"
        let rootOnSameDoor = try BotConnection.address("https://example.com:8443")
        XCTAssertEqual(try BotArtifactReference.path(rootLink, address: rootOnSameDoor), "/tmp/b.png")

        // And a path that belongs to another door is refused rather than guessed at.
        XCTAssertThrowsError(try BotArtifactReference.path(prefixedLink, address: rootOnSameDoor))
    }
}
