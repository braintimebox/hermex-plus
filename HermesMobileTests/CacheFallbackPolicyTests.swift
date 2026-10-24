import XCTest
@testable import HermesMobile

/// Contract of the session-load failure policy: which failures are worth another
/// attempt, which must fall back to the cache, and which must surface as errors.
///
/// Regression context (production telemetry, 3.9.51/3.9.52): three `SessionList`
/// failures were logged with `category: network.url.-1015` and `usedCache: false`.
/// The server had already answered — the client could not read the bytes — and the
/// policy treated that as "no cache", so the list went empty.
final class CacheFallbackPolicyTests: XCTestCase {
    func testUsesCacheForConnectivityErrors() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .cannotFindHost,
            .dataNotAllowed,
            .timedOut
        ]

        for code in codes {
            XCTAssertTrue(
                CacheFallbackPolicy.shouldUseCache(for: APIError.network(underlying: URLError(code))),
                "\(code) should use cache fallback"
            )
            XCTAssertTrue(
                CacheFallbackPolicy.shouldRetry(APIError.network(underlying: URLError(code))),
                "\(code) should be retried"
            )
        }
    }

    func testUsesCacheForTransientUnavailableHTTPStatuses() {
        for statusCode in [408, 502, 503, 504] {
            let error = APIError.http(statusCode: statusCode, body: nil)
            XCTAssertTrue(CacheFallbackPolicy.shouldUseCache(for: error),
                          "HTTP \(statusCode) should use cache fallback")
            XCTAssertTrue(CacheFallbackPolicy.shouldRetry(error),
                          "HTTP \(statusCode) should be retried")
        }
    }

    /// Unreadable payloads: the bytes arrived and cannot be used. Retrying returns the
    /// same bytes, so the cache is the answer — the old policy returned an empty list.
    func testUnreadablePayloadsUseCacheWithoutRetry() {
        let cases: [(name: String, error: Error)] = [
            ("-1015 cannotDecodeRawData", APIError.network(underlying: URLError(.cannotDecodeRawData))),
            ("-1016 cannotDecodeContentData", APIError.network(underlying: URLError(.cannotDecodeContentData))),
            ("-1017 cannotParseResponse", APIError.network(underlying: URLError(.cannotParseResponse))),
            ("decoding", APIError.decoding(underlying: URLError(.badServerResponse))),
        ]

        for testCase in cases {
            XCTAssertEqual(CacheFallbackPolicy.outcome(for: testCase.error), .cacheOnly,
                           "\(testCase.name) should fall back to cache")
            XCTAssertTrue(CacheFallbackPolicy.shouldUseCache(for: testCase.error),
                          "\(testCase.name) should use cache fallback")
            XCTAssertFalse(CacheFallbackPolicy.shouldRetry(testCase.error),
                           "\(testCase.name) must not be retried")
        }
    }

    /// A rejected response from the transport is transient in practice (tunnel reset),
    /// so it earns a bounded retry and a cache fallback.
    func testBadServerResponseRetriesWithCache() {
        let error = APIError.network(underlying: URLError(.badServerResponse))
        XCTAssertEqual(CacheFallbackPolicy.outcome(for: error), .retryWithCache)
        XCTAssertTrue(CacheFallbackPolicy.shouldUseCache(for: error))
    }

    func testDoesNotUseCacheForServerApplicationErrors() {
        let cases: [(name: String, error: Error)] = [
            ("invalid server URL", APIError.invalidServerURL),
            ("unauthorized", APIError.unauthorized),
            ("bad request", APIError.http(statusCode: 400, body: nil)),
            ("forbidden", APIError.http(statusCode: 403, body: nil)),
            ("not found", APIError.http(statusCode: 404, body: nil)),
            ("rate limited", APIError.http(statusCode: 429, body: nil)),
            ("server error", APIError.http(statusCode: 500, body: nil)),
            ("bad URL", APIError.network(underlying: URLError(.badURL))),
            ("certificate", APIError.network(underlying: URLError(.secureConnectionFailed))),
            ("plain cancellation", CancellationError())
        ]

        for testCase in cases {
            XCTAssertFalse(
                CacheFallbackPolicy.shouldUseCache(for: testCase.error),
                "\(testCase.name) should not use cache fallback"
            )
            XCTAssertFalse(
                CacheFallbackPolicy.shouldRetry(testCase.error),
                "\(testCase.name) should not be retried"
            )
        }
    }

    func testRawURLErrorUsesSameConnectivityRules() {
        XCTAssertTrue(CacheFallbackPolicy.shouldUseCache(for: URLError(.timedOut)))
        XCTAssertFalse(CacheFallbackPolicy.shouldUseCache(for: URLError(.badURL)))
    }
}
