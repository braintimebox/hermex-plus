import XCTest
@testable import HermesMobile

/// The Decisions API is an external alpha endpoint: no chat turn ever reaches it,
/// so these tests pin the wire contract itself against a response captured from a
/// real call on 2026-10-19.
final class DecisionsClientTests: XCTestCase {
    /// Verbatim response from `POST https://openrouter.ai/api/alpha/decisions`
    /// (model `typesafe/jev-1.14`, one noul + one choice question).
    static let liveResponse = """
    {"model":"typesafe/jev-1.14-20261014","answers":{"refund":{"type":"noul","noul":0.55},"team":{"type":"choice","choice":"billing","probabilities":{"billing":1,"technical":0,"account":0},"confidence":1}},"usage":{"input_tokens":372,"output_tokens":54,"cost":0.000015624},"id":"gen-dec-1792498844-BjP54KnFy5zQyJlaG1Jb","provider":"TypeSafe"}
    """

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DecisionStubURLProtocol.self]
        session = URLSession(configuration: configuration)
        DecisionStubURLProtocol.reset()
    }

    override func tearDown() {
        DecisionStubURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    func testLiveResponseDecodesIntoAnswerSummaries() throws {
        let decoded = try JSONDecoder().decode(DecisionResponse.self, from: Data(Self.liveResponse.utf8))

        XCTAssertEqual(decoded.answers["refund"]?.type, "noul")
        XCTAssertEqual(decoded.answers["refund"]?.summary, "55%")
        XCTAssertEqual(decoded.answers["team"]?.choice, "billing")
        XCTAssertEqual(decoded.answers["team"]?.summary, "billing · 100%")
        XCTAssertEqual(decoded.usage?.inputTokens, 372)
        XCTAssertEqual(decoded.provider, "TypeSafe")
        XCTAssertNotNil(decoded.id)
    }

    /// Verbatim response for a `score` question (three levels, captured live on
    /// 2026-10-20). `score` is the expected level index; `legend` names the levels.
    static let liveScoreResponse = """
    {"model":"typesafe/jev-1.14-20261014","answers":{"severity":{"type":"score","score":0.83,"legend":{"0":"Cosmetic","1":"Degraded but workaround exists","2":"Blocking"},"probabilities":{"0":0.19,"1":0.8,"2":0.01},"confidence":0.7}},"usage":{"input_tokens":319,"output_tokens":17,"cost":1.3398e-05},"id":"gen-dec-1792511629-FixtureOnly","provider":"TypeSafe"}
    """

    func testScoreAnswerMapsIndexToLegendLabel() throws {
        let decoded = try JSONDecoder().decode(DecisionResponse.self, from: Data(Self.liveScoreResponse.utf8))
        let severity = try XCTUnwrap(decoded.answers["severity"])

        XCTAssertEqual(severity.type, "score")
        XCTAssertEqual(severity.legend?["2"], "Blocking")
        // 0.83 sits closest to level 1 of {0,1,2}.
        XCTAssertEqual(severity.summary, "Degraded but workaround exists · 0.83")
    }

    func testScoreAnswerWithoutLegendFallsBackToTheNumber() throws {
        let json = #"{"answers":{"sev":{"type":"score","score":0.4}}}"#
        let decoded = try JSONDecoder().decode(DecisionResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.answers["sev"]?.summary, "0.40")
    }

    func testChoiceQuestionEncodesCriteriaAsOptionObject() throws {
        let request = DecisionRequest(
            model: "typesafe/jev-1.14",
            state: "I was charged twice.",
            questions: [
                "team": DecisionQuestion(
                    type: .choice,
                    instructions: "Which team?",
                    choices: ["billing", "technical"]
                ),
            ]
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let questions = try XCTUnwrap(json["questions"] as? [String: Any])
        let team = try XCTUnwrap(questions["team"] as? [String: Any])

        XCTAssertEqual(team["type"] as? String, "choice")
        let criteria = try XCTUnwrap(team["criteria"] as? [String: Any])
        XCTAssertEqual(Array(criteria.keys).sorted(), ["billing", "technical"])
        XCTAssertTrue(criteria["billing"] is NSNull)
    }

    func testScoreQuestionEncodesLevelsAsOrderedArray() throws {
        let request = DecisionRequest(
            model: "typesafe/jev-1.14",
            state: "Export fails.",
            questions: [
                "severity": DecisionQuestion(type: .score, instructions: "How severe?", levels: ["low", "medium", "high"]),
            ]
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let questions = try XCTUnwrap(json["questions"] as? [String: Any])
        let severity = try XCTUnwrap(questions["severity"] as? [String: Any])

        XCTAssertEqual(severity["criteria"] as? [String], ["low", "medium", "high"])
    }

    func testNoulQuestionSendsNoCriteria() throws {
        let request = DecisionRequest(
            model: "typesafe/jev-1.14",
            state: "Refund please.",
            questions: ["refund": DecisionQuestion(type: .noul, instructions: "Asking for money back?")]
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let questions = try XCTUnwrap(json["questions"] as? [String: Any])
        let refund = try XCTUnwrap(questions["refund"] as? [String: Any])

        XCTAssertNil(refund["criteria"])
    }

    func testDecidePostsAuthorizationHeaderAndDecodesAnswers() async throws {
        DecisionStubURLProtocol.respond(status: 200, body: Self.liveResponse)
        let client = DecisionsClient(session: session)

        let response = try await client.decide(
            DecisionRequest(
                model: "typesafe/jev-1.14",
                state: "I was charged twice.",
                questions: ["refund": DecisionQuestion(type: .noul, instructions: "Asking for money back?")]
            ),
            apiKey: "sk-test-key"
        )

        XCTAssertEqual(response.answers["refund"]?.noul, 0.55)
        let request = try XCTUnwrap(DecisionStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/alpha/decisions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-key")
    }

    func testMissingKeyFailsBeforeAnyNetworkCall() async {
        let client = DecisionsClient(session: session)
        do {
            _ = try await client.decide(
                DecisionRequest(model: "m", state: "s", questions: ["q": DecisionQuestion(type: .noul, instructions: "i")]),
                apiKey: "  "
            )
            XCTFail("expected missingKey")
        } catch {
            XCTAssertEqual(error as? DecisionsClient.ClientError, .missingKey)
        }
        XCTAssertNil(DecisionStubURLProtocol.lastRequest)
    }

    func testUnauthorizedMapsToReadableError() async {
        DecisionStubURLProtocol.respond(status: 401, body: #"{"error":{"message":"No auth credentials found","code":401}}"#)
        let client = DecisionsClient(session: session)
        do {
            _ = try await client.decide(
                DecisionRequest(model: "m", state: "s", questions: ["q": DecisionQuestion(type: .noul, instructions: "i")]),
                apiKey: "bad"
            )
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? DecisionsClient.ClientError, .unauthorized)
        }
    }

    func testInsufficientCreditsMapsToReadableError() async {
        DecisionStubURLProtocol.respond(status: 402, body: #"{"error":{"message":"Insufficient credits","code":402}}"#)
        let client = DecisionsClient(session: session)
        do {
            _ = try await client.decide(
                DecisionRequest(model: "m", state: "s", questions: ["q": DecisionQuestion(type: .noul, instructions: "i")]),
                apiKey: "k"
            )
            XCTFail("expected insufficientCredits")
        } catch {
            XCTAssertEqual(error as? DecisionsClient.ClientError, .insufficientCredits)
        }
    }

    func testOtherHTTPErrorSurfacesServerMessage() async {
        DecisionStubURLProtocol.respond(status: 400, body: #"{"error":{"message":"state is required","code":400}}"#)
        let client = DecisionsClient(session: session)
        do {
            _ = try await client.decide(
                DecisionRequest(model: "m", state: "", questions: ["q": DecisionQuestion(type: .noul, instructions: "i")]),
                apiKey: "k"
            )
            XCTFail("expected http error")
        } catch {
            XCTAssertEqual(error as? DecisionsClient.ClientError, .http(400, "state is required"))
        }
    }

    func testEmptyAnswersAreRejected() async {
        DecisionStubURLProtocol.respond(status: 200, body: #"{"answers":{},"id":"x"}"#)
        let client = DecisionsClient(session: session)
        do {
            _ = try await client.decide(
                DecisionRequest(model: "m", state: "s", questions: ["q": DecisionQuestion(type: .noul, instructions: "i")]),
                apiKey: "k"
            )
            XCTFail("expected emptyAnswers")
        } catch {
            XCTAssertEqual(error as? DecisionsClient.ClientError, .emptyAnswers)
        }
    }

    func testModelsEndpointParsesDecisionCatalog() async throws {
        DecisionStubURLProtocol.respond(
            status: 200,
            body: #"{"data":[{"id":"typesafe/jev-1.14","name":"TypeSafe: Jev 1.14"},{"id":"cloudflare/clef-flash","name":"Cloudflare: Clef Flash"}]}"#
        )
        let client = DecisionsClient(session: session)
        let models = try await client.availableModels(apiKey: "k")

        XCTAssertEqual(models.map(\.id), ["typesafe/jev-1.14", "cloudflare/clef-flash"])
        XCTAssertEqual(models.first?.displayName, "TypeSafe: Jev 1.14")
    }
}

final class DecisionsViewModelTests: XCTestCase {
    private final class MemoryKeychain: KeychainStoring {
        var values: [String: String] = [:]
        func save(_ value: String, forKey key: KeychainStore.Key) throws { values[key.rawValue] = value }
        func load(_ key: KeychainStore.Key) throws -> String? { values[key.rawValue] }
        func delete(_ key: KeychainStore.Key) throws { values.removeValue(forKey: key.rawValue) }
        func save(_ value: String, forKey key: KeychainStore.Key, scope: String) throws { values["\(scope)/\(key.rawValue)"] = value }
        func load(_ key: KeychainStore.Key, scope: String) throws -> String? { values["\(scope)/\(key.rawValue)"] }
        func delete(_ key: KeychainStore.Key, scope: String) throws { values.removeValue(forKey: "\(scope)/\(key.rawValue)") }
    }

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DecisionStubURLProtocol.self]
        session = URLSession(configuration: configuration)
        DecisionStubURLProtocol.reset()
    }

    override func tearDown() {
        DecisionStubURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    @MainActor
    func testRunWithoutKeyReportsMissingKeyAndSendsNothing() async {
        let viewModel = DecisionsViewModel(
            client: DecisionsClient(session: session),
            keychain: MemoryKeychain()
        )
        viewModel.state = "I was charged twice."
        viewModel.questions = [DecisionsViewModel.EditableQuestion(kind: .noul, instructions: "Asking for money back?")]

        await viewModel.run()

        XCTAssertEqual(viewModel.errorMessage, DecisionsClient.ClientError.missingKey.errorDescription)
        XCTAssertNil(DecisionStubURLProtocol.lastRequest)
        XCTAssertNil(viewModel.result)
    }

    @MainActor
    func testRunStoresAnswersAndPersistsKey() async {
        DecisionStubURLProtocol.respond(status: 200, body: DecisionsClientTests.liveResponse)
        let keychain = MemoryKeychain()
        let viewModel = DecisionsViewModel(client: DecisionsClient(session: session), keychain: keychain)
        viewModel.apiKey = "sk-live"
        viewModel.state = "I was charged twice."
        viewModel.questions = [
            DecisionsViewModel.EditableQuestion(kind: .noul, instructions: "Asking for money back?"),
            DecisionsViewModel.EditableQuestion(kind: .choice, instructions: "Which team?", choices: "billing, technical"),
        ]

        await viewModel.run()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.result?.answers["refund"]?.noul, 0.55)
        XCTAssertEqual(viewModel.result?.answers["team"]?.choice, "billing")
        XCTAssertEqual(keychain.values[KeychainStore.Key.decisionsAPIKey.rawValue], "sk-live")
        XCTAssertFalse(viewModel.isRunning)
    }

    @MainActor
    func testFailureClearsPreviousResultAndShowsError() async {
        DecisionStubURLProtocol.respond(status: 200, body: DecisionsClientTests.liveResponse)
        let viewModel = DecisionsViewModel(client: DecisionsClient(session: session), keychain: MemoryKeychain())
        viewModel.apiKey = "k"
        viewModel.state = "x"
        viewModel.questions = [DecisionsViewModel.EditableQuestion(kind: .noul, instructions: "i")]
        await viewModel.run()
        XCTAssertNotNil(viewModel.result)

        DecisionStubURLProtocol.respond(status: 500, body: #"{"error":{"message":"boom","code":500}}"#)
        await viewModel.run()

        XCTAssertNil(viewModel.result)
        XCTAssertEqual(viewModel.errorMessage, DecisionsClient.ClientError.http(500, "boom").errorDescription)
    }

    @MainActor
    func testCanRunRequiresStateAndAtLeastOneQuestion() {
        let viewModel = DecisionsViewModel(client: DecisionsClient(session: session), keychain: MemoryKeychain())
        viewModel.questions = [DecisionsViewModel.EditableQuestion(kind: .noul, instructions: "i")]

        XCTAssertFalse(viewModel.canRun)
        viewModel.state = "   "
        XCTAssertFalse(viewModel.canRun)
        viewModel.state = "text"
        XCTAssertTrue(viewModel.canRun)
        viewModel.questions = [DecisionsViewModel.EditableQuestion(kind: .noul, instructions: "  ")]
        XCTAssertFalse(viewModel.canRun)
    }

    @MainActor
    func testQuestionsWithBlankInstructionsAreNotSent() {
        let viewModel = DecisionsViewModel(client: DecisionsClient(session: session), keychain: MemoryKeychain())
        viewModel.questions = [
            DecisionsViewModel.EditableQuestion(kind: .noul, instructions: "kept"),
            DecisionsViewModel.EditableQuestion(kind: .noul, instructions: "   "),
        ]
        XCTAssertEqual(viewModel.questions.compactMap { $0.build() }.count, 1)
    }

    @MainActor
    func testSavedKeyIsRestored() {
        let keychain = MemoryKeychain()
        try? keychain.save("sk-saved", forKey: .decisionsAPIKey)
        let viewModel = DecisionsViewModel(client: DecisionsClient(session: session), keychain: keychain)

        viewModel.loadSavedKey()

        XCTAssertEqual(viewModel.apiKey, "sk-saved")
    }

    private final class FailingKeychain: KeychainStoring {
        struct SaveFailed: LocalizedError { var errorDescription: String? { "keychain is locked" } }
        func save(_ value: String, forKey key: KeychainStore.Key) throws { throw SaveFailed() }
        func load(_ key: KeychainStore.Key) throws -> String? { nil }
        func delete(_ key: KeychainStore.Key) throws {}
        func save(_ value: String, forKey key: KeychainStore.Key, scope: String) throws { throw SaveFailed() }
        func load(_ key: KeychainStore.Key, scope: String) throws -> String? { nil }
        func delete(_ key: KeychainStore.Key, scope: String) throws {}
    }

    @MainActor
    func testKeychainFailureIsSurfacedInsteadOfSwallowed() {
        let viewModel = DecisionsViewModel(client: DecisionsClient(session: session), keychain: FailingKeychain())
        viewModel.apiKey = "sk-typed"

        viewModel.saveKey()

        XCTAssertEqual(viewModel.errorMessage, "Could not save the key to Keychain: keychain is locked")
    }

    @MainActor
    func testAnswersAreTiedToTheirQuestions() async {
        // The real API echoes the request keys, so the response below does too.
        let echoed = #"{"answers":{"q1":{"type":"noul","noul":0.55},"q2":{"type":"choice","choice":"billing","confidence":1}}}"#
        DecisionStubURLProtocol.respond(status: 200, body: echoed)
        let viewModel = DecisionsViewModel(client: DecisionsClient(session: session), keychain: MemoryKeychain())
        viewModel.apiKey = "k"
        viewModel.state = "I was charged twice."
        viewModel.questions = [
            DecisionsViewModel.EditableQuestion(kind: .noul, instructions: "Asking for money back?"),
            DecisionsViewModel.EditableQuestion(kind: .choice, instructions: "Which team?", choices: "billing, technical"),
        ]

        await viewModel.run()

        // Positional keys are all the API echoes; the screen has to show the question.
        XCTAssertEqual(viewModel.questionTitles["q1"], "Asking for money back?")
        XCTAssertEqual(viewModel.questionTitles["q2"], "Which team?")
        let answeredKeys = viewModel.result.map { Set($0.answers.keys) } ?? []
        XCTAssertEqual(answeredKeys, Set(["q1", "q2"]))
    }

    @MainActor
    func testReloadModelsRefetchesWithTheCurrentKey() async {
        DecisionStubURLProtocol.respond(
            status: 200,
            body: #"{"data":[{"id":"typesafe/jev-1.14","name":"TypeSafe: Jev 1.14"}]}"#
        )
        let viewModel = DecisionsViewModel(client: DecisionsClient(session: session), keychain: MemoryKeychain())
        viewModel.apiKey = "k"

        await viewModel.reloadModels()

        XCTAssertEqual(viewModel.models.map(\.id), ["typesafe/jev-1.14"])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testEmptyModelListDoesNotFail() async {
        DecisionStubURLProtocol.respond(status: 200, body: #"{"data":[]}"#)
        let viewModel = DecisionsViewModel(client: DecisionsClient(session: session), keychain: MemoryKeychain())
        viewModel.apiKey = "k"

        await viewModel.reloadModels()

        XCTAssertTrue(viewModel.models.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }
}

/// Minimal URLProtocol stub: the app talks to a fixed OpenRouter URL, so responses
/// are keyed by nothing but the call order the test sets up.
final class DecisionStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = "{}"
    nonisolated(unsafe) private static var capturedRequest: URLRequest?

    static var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return capturedRequest
    }

    static func respond(status: Int, body: String) {
        lock.lock(); defer { lock.unlock() }
        Self.status = status
        Self.body = body
        capturedRequest = nil
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        status = 200
        body = "{}"
        capturedRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequest = request
        let status = Self.status
        let body = Self.body
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
