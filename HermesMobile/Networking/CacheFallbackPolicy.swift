import Foundation

/// What a failed session load should do next.
///
/// Three outcomes, not two: retrying and falling back to cache are different
/// decisions. A transport hiccup is worth a bounded retry; a payload the client
/// cannot decode comes back identical on every attempt, so retrying only spends the
/// user's time and the cached list is the better answer.
enum CacheFailureOutcome: Equatable {
    /// Worth retrying with backoff; fall back to cache if every attempt fails.
    case retryWithCache
    /// Never retry — use the cache now.
    case cacheOnly
    /// Surface the error; a real server refusal must not hide behind stale rows.
    case fail
}

enum CacheFallbackPolicy {
    /// Backwards-compatible question: may the cached list be shown at all?
    static func shouldUseCache(for error: Error) -> Bool {
        outcome(for: error) != .fail
    }

    /// May this failure be retried? Only transport-level failures.
    static func shouldRetry(_ error: Error) -> Bool {
        outcome(for: error) == .retryWithCache
    }

    /// Was the server never heard from at all?
    ///
    /// The session list uses this to decide whether the offline banner is enough
    /// or the real error has to stay visible: a decode failure or an HTTP refusal
    /// means the server DID answer, so hiding it would leave a stale list that
    /// looks live. Kept separate from `outcome`, which also decides about retries.
    static func isTransportFailure(_ error: Error) -> Bool {
        switch error {
        case APIError.network:
            return true
        case APIError.decoding, APIError.http:
            return false
        default:
            return error is URLError
        }
    }

    static func outcome(for error: Error) -> CacheFailureOutcome {
        switch error {
        case APIError.network(let underlying):
            return urlOutcome(underlying)
        case APIError.decoding:
            // The response arrived but did not match the model: same request, same bytes.
            return .cacheOnly
        case APIError.http(let statusCode, _):
            return isTransientUnavailableStatus(statusCode) ? .retryWithCache : .fail
        default:
            // URLErrors can also reach us unwrapped (not wrapped in APIError.network).
            return urlOutcome(error)
        }
    }

    private static func urlOutcome(_ error: Error) -> CacheFailureOutcome {
        guard let urlError = error as? URLError else { return .fail }

        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .cannotFindHost,
             .dataNotAllowed,
             .timedOut,
             .badServerResponse,
             .zeroByteResource:
            return .retryWithCache

        // -1015 cannotDecodeRawData, -1016 cannotDecodeContentData,
        // -1017 cannotParseResponse: the bytes arrived and are unusable. A tunnel that
        // truncates a response reproduces this on every attempt, so no retry — but the
        // cache is a legitimate answer, and returning an empty list for it is the bug.
        case .cannotDecodeRawData,
             .cannotDecodeContentData,
             .cannotParseResponse:
            return .cacheOnly

        default:
            return .fail
        }
    }

    private static func isTransientUnavailableStatus(_ statusCode: Int) -> Bool {
        switch statusCode {
        case 408, 502, 503, 504:
            return true
        default:
            return false
        }
    }
}

/// HERMEX-FORK: the exponential backoff both loaders use before retrying a
/// connectivity failure, in one place.
///
/// Production keeps the real schedule — 1, 2, 4, 8 s, ~15 s total, which exists so a
/// tunnel still coming up on cold start has time to connect. Tests set `scale` to 0:
/// a case that simulates a connectivity failure otherwise pays those 15 seconds of
/// wall clock for nothing. Measured on 3.9.36: eight such cases, ~121 s of the Test
/// step — 19% of a 640 s suite that itself is ~70% of the run.
enum HermesRetryBackoff {
    private static let lock = NSLock()
    private static var storedScale: Double = 1

    /// Multiplier applied to the production schedule. 1 in the app, 0 in tests.
    static var scale: Double {
        get { lock.lock(); defer { lock.unlock() }; return storedScale }
        set { lock.lock(); defer { lock.unlock() }; storedScale = newValue }
    }

    /// Sleeps the schedule for `attempt` (1-based), scaled. A zero scale is a no-op,
    /// so the retry loop still runs all five attempts — only the waiting is removed.
    static func sleep(attempt: Int) async {
        let seconds = Double(1 << (attempt - 1)) * scale
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
