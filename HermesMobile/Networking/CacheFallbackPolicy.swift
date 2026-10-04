import Foundation

enum CacheFallbackPolicy {
    static func shouldUseCache(for error: Error) -> Bool {
        switch error {
        case APIError.network(let underlying):
            return isConnectivityError(underlying)
        case APIError.http(let statusCode, _):
            return isTransientUnavailableStatus(statusCode)
        default:
            return isConnectivityError(error)
        }
    }

    private static func isConnectivityError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }

        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .cannotFindHost,
             .dataNotAllowed,
             .timedOut:
            return true
        default:
            return false
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
