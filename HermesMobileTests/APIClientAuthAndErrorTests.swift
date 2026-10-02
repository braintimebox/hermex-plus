import XCTest
import AVFoundation
import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers
@testable import HermesMobile

final class APIClientAuthAndErrorTests: APIClientTestCase {
    func testOnboardingPasswordValidationOnlyRequiresKnownAuthEnabledPassword() {
        XCTAssertEqual(
            OnboardingViewModel.passwordValidationMessage(
                authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false),
                password: " \n "
            ),
            OnboardingViewModel.emptyPasswordMessage
        )
        XCTAssertNil(
            OnboardingViewModel.passwordValidationMessage(
                authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false),
                password: "secret"
            )
        )
        XCTAssertNil(
            OnboardingViewModel.passwordValidationMessage(
                authStatus: AuthStatusResponse(authEnabled: false, loggedIn: false),
                password: ""
            )
        )
        XCTAssertNil(OnboardingViewModel.passwordValidationMessage(authStatus: nil, password: ""))
    }

    @MainActor
    func testAuthManagerConnectsToNoPasswordTailscaleServerWithoutLogin() async throws {
        let keychain = InMemoryKeychainStore()
        let client = MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false, loggedIn: false))
        var requestedURLs: [URL] = []
        let manager = AuthManager(
            keychain: keychain,
            clientFactory: { url in
                requestedURLs.append(url)
                return client
            },
            serverRegistry: ServerRegistry.inMemory()
        )

        await manager.configure(serverURLString: "100.96.12.34:9119", password: "")

        let expectedURL = try XCTUnwrap(URL(string: "http://100.96.12.34:9119"))
        XCTAssertEqual(requestedURLs, [expectedURL])
        XCTAssertEqual(client.loginPasswords, [])
        XCTAssertEqual(keychain.savedValues[.serverURL], expectedURL.absoluteString)
        XCTAssertEqual(manager.state, .loggedIn(server: expectedURL))
        XCTAssertNil(manager.lastErrorMessage)
    }

    func testServerURLNormalizationDropsAccidentalWWWBeforeWebUISubdomain() throws {
        XCTAssertEqual(
            try AuthManager.normalizedServerURL(from: "https://www.webui.example.test"),
            URL(string: "https://webui.example.test")
        )
        XCTAssertEqual(
            try AuthManager.normalizedServerURL(from: "www.webui.example.test"),
            URL(string: "https://webui.example.test")
        )
        XCTAssertEqual(
            try AuthManager.normalizedServerURL(from: "https://www.example.com"),
            URL(string: "https://www.example.com")
        )
    }

    @MainActor
    func testAuthManagerPreservesPasswordRequiredEmptyPasswordBehavior() async throws {
        let keychain = InMemoryKeychainStore()
        let client = MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false))
        let manager = AuthManager(
            keychain: keychain,
            clientFactory: { _ in client },
            serverRegistry: ServerRegistry.inMemory()
        )

        await manager.configure(serverURLString: "https://example.test", password: "")

        XCTAssertEqual(client.loginPasswords, [])
        XCTAssertNil(keychain.savedValues[.serverURL])
        XCTAssertEqual(manager.state, .unconfigured)
        XCTAssertEqual(manager.lastErrorMessage, OnboardingViewModel.emptyPasswordMessage)
    }

    @MainActor
    func testAuthManagerLogsInWhenPasswordIsRequired() async throws {
        let keychain = InMemoryKeychainStore()
        let client = MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false))
        let manager = AuthManager(
            keychain: keychain,
            clientFactory: { _ in client },
            serverRegistry: ServerRegistry.inMemory()
        )

        await manager.configure(serverURLString: "https://example.test", password: "secret")

        let expectedURL = try XCTUnwrap(URL(string: "https://example.test"))
        XCTAssertEqual(client.loginPasswords, ["secret"])
        XCTAssertEqual(keychain.savedValues[.serverURL], expectedURL.absoluteString)
        XCTAssertEqual(manager.state, .loggedIn(server: expectedURL))
        XCTAssertNil(manager.lastErrorMessage)
    }

    func testUnauthorizedResponseThrowsUnauthorized() async {
        let client = makeClient { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )
            return (try XCTUnwrap(response), Data())
        }

        do {
            _ = try await client.sessions()
            XCTFail("Expected unauthorized error")
        } catch APIError.unauthorized {
            // Expected path.
        } catch {
            XCTFail("Expected unauthorized error, got \(error)")
        }
    }

    func testVanishedSessionResponseUsesRecoveryMessage() async throws {
        let client = makeClient { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            let body = Data(#"{"error":"Session not found"}"#.utf8)
            return (try XCTUnwrap(response), body)
        }

        do {
            _ = try await client.session(id: "missing-session")
            XCTFail("Expected vanished-session HTTP error")
        } catch let APIError.http(statusCode, body) {
            XCTAssertEqual(statusCode, 404)
            XCTAssertEqual(body, #"{"error":"Session not found"}"#)
            XCTAssertEqual(
                APIError.http(statusCode: statusCode, body: body).localizedDescription,
                "That session no longer exists on the server. Reopen another session or create a new one."
            )
        } catch {
            XCTFail("Expected vanished-session HTTP error, got \(error)")
        }
    }

    func testCloudflareErrorDoesNotExposeRawHTMLBody() async throws {
        let client = makeClient { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 502,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            )
            let body = Data("<html><title>Bad gateway</title><body>cloudflare</body></html>".utf8)
            return (try XCTUnwrap(response), body)
        }

        do {
            _ = try await client.sessions()
            XCTFail("Expected HTTP error")
        } catch let APIError.http(statusCode, body) {
            let message = APIError.http(statusCode: statusCode, body: body).localizedDescription
            XCTAssertEqual(
                message,
                "Could not connect to the server. Check that hermes-webui is running and the tunnel is connected."
            )
            XCTAssertFalse(message.contains("<html>"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("bad gateway"))
        } catch {
            XCTFail("Expected HTTP error, got \(error)")
        }
    }

    // MARK: - HTTP 403 (issue #333)

    func testForbiddenChatStartSurfacesServerReasonInsteadOfPasswordCopy() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/chat/start")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 403,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            let body = Data(#"{"error":"Read-only imported sessions cannot be continued from WebUI"}"#.utf8)
            return (try XCTUnwrap(response), body)
        }

        do {
            _ = try await client.startChat(
                sessionID: "20260831_041231_abc",
                message: "hello",
                workspace: nil,
                model: nil
            )
            XCTFail("Expected HTTP 403 error")
        } catch let error as APIError {
            XCTAssertEqual(
                error.localizedDescription,
                "The server refused the request: Read-only imported sessions cannot be continued from WebUI"
            )
            XCTAssertFalse(error.localizedDescription.localizedCaseInsensitiveContains("password"))
            XCTAssertEqual(error.privacySafeLogCategory, "http.403")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    func testForbiddenSurfacesMessageAndDetailPayloadShapes() {
        XCTAssertEqual(
            APIError.http(statusCode: 403, body: #"{"message":"Workspace is locked"}"#).localizedDescription,
            "The server refused the request: Workspace is locked"
        )
        XCTAssertEqual(
            APIError.http(statusCode: 403, body: #"{"detail":"Not permitted"}"#).localizedDescription,
            "The server refused the request: Not permitted"
        )
    }

    func testForbiddenWithoutStructuredBodyUsesGenericFallback() {
        let fallback = "The server refused the request. Check the server permissions and try again."
        let bodies: [String?] = [
            nil,
            "",
            "   ",
            "not json",
            #"{"error":""}"#,
            "<html><title>Forbidden</title><body>cloudflare access denied</body></html>",
        ]

        for body in bodies {
            let message = APIError.http(statusCode: 403, body: body).localizedDescription
            XCTAssertEqual(message, fallback, "body: \(String(describing: body))")
            XCTAssertFalse(message.contains("<"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("password"))
        }
    }

    func testUnauthorizedAndBadRequestCopyIsUnchangedByForbiddenHandling() {
        XCTAssertEqual(
            APIError.unauthorized.localizedDescription,
            "The password was rejected. Check the server password and try again."
        )
        XCTAssertEqual(
            APIError.http(statusCode: 400, body: #"{"error":"Missing message"}"#).localizedDescription,
            "The server rejected the request: Missing message"
        )
        XCTAssertEqual(
            APIError.http(statusCode: 400, body: "<html>nope</html>").localizedDescription,
            "The server rejected the request."
        )
    }

    func testDisplayedServerMessageIsBoundedAcrossHTTPBranches() {
        let long = String(repeating: "x", count: 500)
        let body = #"{"error":"\#(long)"}"#
        let clipped = String(repeating: "x", count: 200) + "…"

        XCTAssertEqual(
            APIError.http(statusCode: 403, body: body).localizedDescription,
            "The server refused the request: \(clipped)"
        )
        XCTAssertEqual(
            APIError.http(statusCode: 400, body: body).localizedDescription,
            "The server rejected the request: \(clipped)"
        )
        XCTAssertEqual(
            APIError.http(statusCode: 418, body: body).localizedDescription,
            "Server returned HTTP 418: \(clipped)"
        )
        // The raw body is still available to callers that inspect it programmatically.
        XCTAssertEqual(APIError.http(statusCode: 403, body: body).serverMessage, long)
    }

    func testHTTPErrorPrivacySafeLogCategoryDoesNotExposeServerBody() {
        let error = APIError.http(
            statusCode: 400,
            body: #"{"error":"password=secret prompt=private raw response"}"#
        )

        let category = error.privacySafeLogCategory

        XCTAssertEqual(category, "http.400")
        XCTAssertFalse(category.contains("secret"))
        XCTAssertFalse(category.contains("private"))
        XCTAssertFalse(category.contains("raw response"))
    }

    func testNetworkErrorPrivacySafeLogCategoryUsesOnlyURLCode() {
        let error = APIError.network(underlying: URLError(.timedOut))

        XCTAssertEqual(error.privacySafeLogCategory, "network.url.-1001")
    }

    func testNetworkTimeoutUsesSetupGuidance() async throws {
        let error = APIError.network(underlying: URLError(.timedOut))

        XCTAssertEqual(
            error.localizedDescription,
            "The server did not respond in time. Check that the server is running and the connection is available."
        )
    }

    func testAppTransportSecurityErrorUsesHTTPGuidance() async throws {
        let error = APIError.network(underlying: URLError(.appTransportSecurityRequiresSecureConnection))

        XCTAssertEqual(
            error.localizedDescription,
            "iOS blocked this insecure HTTP connection. Use HTTPS instead."
        )
    }
}


// HERMEX-FORK: delivery-failure coverage (upstream has no such suite).
/// The requirement these pin (owner, 02.10.2026): 3.9.30 has to catch *every*
/// kind of failure that means "the message did not arrive" — five, ten or more
/// different ones — and it must classify them the same way every time, so the
/// daily watchdog groups them instead of drowning in free text. Only a transport
/// that is down may reach the screen.
final class DeliveryFailureTests: XCTestCase {
    private func failure(_ error: Error, path: DeliveryPath = .send) -> DeliveryFailure {
        DeliveryFailure.classify(error, path: path)
    }

    func testTransportDownIsTheOnlyThingTheUserIsTold() {
        XCTAssertTrue(failure(APIError.network(underlying: URLError(.notConnectedToInternet))).showsToUser)
        XCTAssertTrue(failure(APIError.network(underlying: URLError(.cannotConnectToHost))).showsToUser)
        XCTAssertTrue(failure(APIError.network(underlying: URLError(.dnsLookupFailed))).showsToUser)
    }

    func testEverythingElseIsHiddenFromTheScreen() {
        let hidden: [Error] = [
            APIError.http(statusCode: 429, body: nil),
            APIError.http(statusCode: 402, body: nil),
            APIError.http(statusCode: 500, body: nil),
            APIError.http(statusCode: 503, body: nil),
            APIError.http(statusCode: 400, body: nil),
            APIError.http(statusCode: 401, body: nil),
            APIError.unauthorized,
            APIError.network(underlying: URLError(.timedOut)),
            APIError.network(underlying: URLError(.networkConnectionLost)),
            APIError.network(underlying: URLError(.cancelled)),
            APIError.decoding(underlying: NSError(domain: "test", code: 1)),
            APIError.invalidServerURL,
        ]
        for error in hidden {
            XCTAssertFalse(failure(error).showsToUser,
                           "must stay off the screen: \(APIError.privacySafeLogCategory(for: error))")
        }
    }

    func testEveryFailureTypeGetsItsOwnReason() {
        XCTAssertEqual(failure(APIError.network(underlying: URLError(.notConnectedToInternet))).reason, .offline)
        XCTAssertEqual(failure(APIError.network(underlying: URLError(.cannotConnectToHost))).reason, .unreachable)
        XCTAssertEqual(failure(APIError.network(underlying: URLError(.timedOut))).reason, .timeout)
        XCTAssertEqual(failure(APIError.http(statusCode: 408, body: nil)).reason, .timeout)
        XCTAssertEqual(failure(APIError.http(statusCode: 429, body: nil)).reason, .rateLimited)
        XCTAssertEqual(failure(APIError.http(statusCode: 402, body: nil)).reason, .quotaExhausted)
        XCTAssertEqual(failure(APIError.http(statusCode: 502, body: nil)).reason, .serverError)
        XCTAssertEqual(failure(APIError.http(statusCode: 400, body: nil)).reason, .badRequest)
        XCTAssertEqual(failure(APIError.unauthorized).reason, .unauthorized)
        XCTAssertEqual(failure(APIError.decoding(underlying: NSError(domain: "t", code: 1))).reason, .decoding)
        XCTAssertEqual(failure(APIError.network(underlying: URLError(.cancelled))).reason, .cancelled)
        XCTAssertEqual(failure(APIError.network(underlying: URLError(.badServerResponse))).reason, .unknown)
    }

    func testRetryabilityMatchesWhetherRepeatingCanDuplicateWork() {
        // A chat start is not idempotent: a timeout or a dropped connection can
        // follow a request the server already accepted, so neither is retryable.
        XCTAssertFalse(failure(APIError.network(underlying: URLError(.timedOut))).retryable)
        XCTAssertFalse(failure(APIError.network(underlying: URLError(.networkConnectionLost))).retryable)
        // A request that provably never left may be repeated.
        XCTAssertTrue(failure(APIError.network(underlying: URLError(.notConnectedToInternet))).retryable)
        XCTAssertTrue(failure(APIError.network(underlying: URLError(.cannotConnectToHost))).retryable)
        // Transient server states are worth another attempt.
        XCTAssertTrue(failure(APIError.http(statusCode: 429, body: nil)).retryable)
        XCTAssertTrue(failure(APIError.http(statusCode: 503, body: nil)).retryable)
        // A refusal is not.
        XCTAssertFalse(failure(APIError.http(statusCode: 400, body: nil)).retryable)
    }

    func testCategoryIsThePrivacySafeGroupTheLogAlreadyUses() {
        XCTAssertEqual(failure(APIError.http(statusCode: 429, body: nil)).category, "http.429")
        XCTAssertEqual(failure(APIError.network(underlying: URLError(.timedOut))).category,
                       "network.url.\(URLError.Code.timedOut.rawValue)")
        XCTAssertEqual(failure(APIError.unauthorized).category, "unauthorized")
    }

    func testEveryPathIsNameable() {
        // A path added without a case here would silently lose its grouping.
        XCTAssertEqual(Set(DeliveryPath.allCases.map(\.rawValue)).count, DeliveryPath.allCases.count)
        XCTAssertEqual(failure(APIError.http(statusCode: 500, body: nil), path: .queue).path, .queue)
    }
}
