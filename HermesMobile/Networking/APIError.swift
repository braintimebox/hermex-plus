import Foundation

enum APIError: LocalizedError {
    case invalidServerURL
    case network(underlying: Error)
    case http(statusCode: Int, body: String?)
    case decoding(underlying: Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return String(localized: "Enter a valid server URL, for example https://hermes.yourdomain.com or http://192.168.1.10:1118.")
        case .network(let underlying):
            return Self.networkMessage(for: underlying)
        case .http(let statusCode, let body):
            if Self.isVanishedSession(statusCode: statusCode, body: body) {
                return String(localized: "That session no longer exists on the server. Reopen another session or create a new one.")
            }

            switch statusCode {
            case -1:
                return String(localized: "The server response could not be read. Check that the URL points to a Hermes server.")
            case 400:
                if let message = Self.displayableServerMessage(from: body) {
                    return String(localized: "The server rejected the request: \(message)")
                }
                return String(localized: "The server rejected the request.")
            case 403:
                // A 403 is a per-request refusal (read-only imported session, missing
                // permission), not a bad password: 401 owns the password copy.
                if let message = Self.displayableServerMessage(from: body) {
                    return String(localized: "The server refused the request: \(message)")
                }
                return String(localized: "The server refused the request. Check the server permissions and try again.")
            case 404:
                return String(localized: "The server endpoint was not found. Check that the URL points to a Hermes server.")
            case 408:
                return String(localized: "The server did not respond in time. Check that the server is running and the connection is available.")
            case 429:
                return String(localized: "The server is receiving too many requests. Wait a moment, then try again.")
            case 500:
                return String(localized: "The Hermes server hit an internal error. Check the server logs, then try again.")
            case 502, 503, 504:
                return String(localized: "Could not connect to the server. Check that hermes-webui is running and the tunnel is connected.")
            default:
                if let message = Self.displayableServerMessage(from: body) {
                    return String(localized: "Server returned HTTP \(statusCode): \(message)")
                }
                return String(localized: "Server returned HTTP \(statusCode).")
            }
        case .decoding:
            return String(localized: "The server response could not be read.")
        case .unauthorized:
            return String(localized: "The password was rejected. Check the server password and try again.")
        }
    }

    /// True when the request provably never reached the server, so it is safe to
    /// retry without risking a duplicate side effect (a chat-start POST is not
    /// idempotent). Deliberately excludes `.timedOut` and `.networkConnectionLost`,
    /// which can fire *after* the server has already accepted the request.
    var isRetryableConnectionFailure: Bool {
        guard case .network(let underlying) = self else { return false }
        guard let urlError = underlying as? URLError else { return false }
        switch urlError.code {
        case .cannotConnectToHost,
             .dnsLookupFailed,
             .cannotFindHost,
             .notConnectedToInternet,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    var privacySafeLogCategory: String {
        switch self {
        case .invalidServerURL:
            return "invalidServerURL"
        case .network(let underlying):
            if let urlError = underlying as? URLError {
                return "network.url.\(urlError.code.rawValue)"
            }
            return "network.other"
        case .http(let statusCode, _):
            return "http.\(statusCode)"
        case .decoding:
            return "decoding"
        case .unauthorized:
            return "unauthorized"
        }
    }

    var serverCode: String? {
        guard case .http(_, let body) = self else { return nil }
        return Self.serverErrorPayload(from: body)?.code
    }

    var serverMessage: String? {
        guard case .http(_, let body) = self else { return nil }
        return Self.serverErrorMessage(from: body)
    }

    var activeStreamID: String? {
        guard case .http(let statusCode, let body) = self, statusCode == 409 else { return nil }
        return Self.serverErrorPayload(from: body)?.activeStreamId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var indicatesMissingStream: Bool {
        guard case .http(let statusCode, let body) = self, statusCode == 404 else { return false }
        return Self.serverErrorMessage(from: body)?.localizedCaseInsensitiveContains("stream not found") == true
    }

    /// True for the documented "prompt already expired" respond rejection:
    /// HTTP 409 with `{"stale": true, …}` in the body (issue #25). Used to show
    /// a friendly expired state instead of a generic failure.
    var indicatesExpiredPendingPrompt: Bool {
        guard case .http(let statusCode, let body) = self, statusCode == 409 else { return false }
        return Self.serverErrorPayload(from: body)?.stale == true
    }

    static func privacySafeLogCategory(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.privacySafeLogCategory
        }

        if let urlError = error as? URLError {
            return "network.url.\(urlError.code.rawValue)"
        }

        if error is CancellationError {
            return "cancelled"
        }

        return "other"
    }
}

private extension APIError {
    struct ErrorPayload: Decodable {
        let error: String?
        let message: String?
        let detail: String?
        let code: String?
        let stale: Bool?
        let activeStreamId: String?

        enum CodingKeys: String, CodingKey {
            case error, message, detail, code, stale
            case activeStreamId = "active_stream_id"
        }
    }

    static func networkMessage(for error: Error) -> String {
        let underlying: Error
        if case APIError.network(let wrapped) = error {
            underlying = wrapped
        } else {
            underlying = error
        }

        guard let urlError = underlying as? URLError else {
            return String(localized: "Could not reach the server. Check the URL and network connection.")
        }

        switch urlError.code {
        case .timedOut:
            return String(localized: "The server did not respond in time. Check that the server is running and the connection is available.")
        case .cannotFindHost, .dnsLookupFailed:
            return String(localized: "Could not find that server. Check the URL and network connection.")
        case .cannotConnectToHost, .networkConnectionLost:
            return String(localized: "Could not connect to the server. Check that it's running and reachable on your network.")
        case .notConnectedToInternet, .dataNotAllowed:
            return String(localized: "This device is offline. Connect to the internet, then try again.")
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            return String(localized: "The HTTPS connection failed. Check the server URL and certificate.")
        case .appTransportSecurityRequiresSecureConnection:
            return String(localized: "iOS blocked this insecure HTTP connection. Use HTTPS instead.")
        case .cancelled:
            return String(localized: "The request was cancelled.")
        default:
            return String(localized: "Could not reach the server. Check the URL and network connection.")
        }
    }

    static func isVanishedSession(statusCode: Int, body: String?) -> Bool {
        guard statusCode == 404 else { return false }
        return serverErrorMessage(from: body)?.localizedCaseInsensitiveContains("Session not found") == true
    }

    /// Longest server-provided message we interpolate into user-facing copy.
    static let displayedServerMessageLimit = 200

    /// The structured server message, bounded for display. Shared by every HTTP
    /// branch that shows server text so an oversized body never floods an alert.
    static func displayableServerMessage(from body: String?) -> String? {
        guard let message = serverErrorMessage(from: body) else { return nil }
        guard message.count > displayedServerMessageLimit else { return message }
        return String(message.prefix(displayedServerMessageLimit)) + "…"
    }

    static func serverErrorMessage(from body: String?) -> String? {
        guard let payload = serverErrorPayload(from: body) else { return nil }
        let message = payload.error ?? payload.message ?? payload.detail
        return message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func serverErrorPayload(from body: String?) -> ErrorPayload? {
        guard let body, let data = body.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ErrorPayload.self, from: data)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}


// HERMEX-FORK: delivery telemetry — one shape for every failed delivery
// (upstream has no equivalent; the fork's rule is that nothing that fails to
// arrive may be silent).
// MARK: - Delivery failures, in one shape

/// Every path a message can fail to travel, so no path can fail invisibly.
///
/// The rule this exists for (owner, 02.10.2026): the *taxonomy* of errors does
/// not matter — five, ten, twenty different ones — what matters is that a
/// message which did not arrive is never silent, never erases the draft, and
/// never spends attention. So every delivery path reports its failure here, in
/// one shape, and that shape decides two things: the log line, and whether the
/// screen says anything at all.
enum DeliveryPath: String, CaseIterable {
    case send
    case steer
    case queue
    case scheduled
    case voiceNote
    case attachment
    case approval
    case clarification
    case share
}

/// Why the message did not arrive.
enum DeliveryReason: String {
    /// No usable network at all.
    case offline
    /// The host could not be reached (server down, wrong address, DNS).
    case unreachable
    case timeout
    case rateLimited
    case quotaExhausted
    case serverError
    case badRequest
    case unauthorized
    case decoding
    case cancelled
    case unknown

    /// The two reasons that cannot be shown any other way: with the transport
    /// down, nothing the user does will help and no amount of retrying is
    /// visible. Everything else belongs to the log.
    var isTransportDown: Bool { self == .offline || self == .unreachable }
}

struct DeliveryFailure: Equatable {
    let path: DeliveryPath
    let reason: DeliveryReason
    /// Safe to repeat the same request without risking a duplicate side effect.
    let retryable: Bool
    /// The privacy-safe grouping the network layer already computes —
    /// `http.429`, `network.url.-1009`, `decoding`. Logged verbatim so a failure
    /// type nobody anticipated shows up as its own group in the watchdog
    /// instead of collapsing into "unknown".
    let category: String

    /// The only case where the screen may say something.
    var showsToUser: Bool { reason.isTransportDown }

    private static func reason(
        for urlError: URLError,
        path: DeliveryPath
    ) -> (DeliveryReason, Bool) {
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return (.offline, true)
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return (.unreachable, true)
        case .networkConnectionLost:
            // Can fire *after* the server accepted the request, so it is a
            // failure to hear back rather than a failure to send.
            return (.timeout, false)
        case .timedOut:
            return (.timeout, false)
        case .cancelled:
            return (.cancelled, false)
        default:
            return (.unknown, false)
        }
    }

    static func classify(_ error: Error, path: DeliveryPath) -> DeliveryFailure {
        let category = APIError.privacySafeLogCategory(for: error)

        if let apiError = error as? APIError {
            switch apiError {
            case .network(let underlying):
                if let urlError = underlying as? URLError {
                    let (reason, retryable) = Self.reason(for: urlError, path: path)
                    return DeliveryFailure(path: path, reason: reason,
                                           retryable: retryable, category: category)
                }
                return DeliveryFailure(path: path, reason: .unknown,
                                       retryable: false, category: category)
            case .http(let statusCode, _):
                switch statusCode {
                case 408:
                    return DeliveryFailure(path: path, reason: .timeout,
                                           retryable: false, category: category)
                case 429:
                    return DeliveryFailure(path: path, reason: .rateLimited,
                                           retryable: true, category: category)
                case 402:
                    return DeliveryFailure(path: path, reason: .quotaExhausted,
                                           retryable: true, category: category)
                case 500...599:
                    return DeliveryFailure(path: path, reason: .serverError,
                                           retryable: true, category: category)
                case 401, 403:
                    return DeliveryFailure(path: path, reason: .unauthorized,
                                           retryable: false, category: category)
                default:
                    return DeliveryFailure(path: path, reason: .badRequest,
                                           retryable: false, category: category)
                }
            case .unauthorized:
                return DeliveryFailure(path: path, reason: .unauthorized,
                                       retryable: false, category: category)
            case .decoding:
                return DeliveryFailure(path: path, reason: .decoding,
                                       retryable: false, category: category)
            case .invalidServerURL:
                return DeliveryFailure(path: path, reason: .badRequest,
                                       retryable: false, category: category)
            }
        }

        if let urlError = error as? URLError {
            let (reason, retryable) = Self.reason(for: urlError, path: path)
            return DeliveryFailure(path: path, reason: reason,
                                   retryable: retryable, category: category)
        }

        return DeliveryFailure(path: path, reason: .unknown,
                               retryable: false, category: category)
    }
}

/// The single funnel every failed delivery goes through.
///
/// One place, so a path cannot forget to report: the failure is classified the
/// same way whether it came from a plain send, a steer, a queued message, a
/// voice note, an attachment, a scheduled send or an approval. It logs, and it
/// answers whether the caller may say anything on screen — which it may only
/// when the transport itself is down.
enum DeliveryTelemetry {
    @discardableResult
    static func record(
        _ failure: DeliveryFailure,
        screen: String,
        detail: String? = nil
    ) -> DeliveryFailure {
        var extras: [String: Any] = [
            "path": failure.path.rawValue,
            "reason": failure.reason.rawValue,
            "retryable": failure.retryable,
            "category": failure.category,
        ]
        if let detail, !detail.isEmpty {
            extras["detail"] = detail
        }
        HermexLogger.shared.log(
            type: "event",
            screen: screen,
            message: "delivery failed",
            extras: extras
        )
        return failure
    }

    /// Convenience for the call sites that hold an `Error`.
    @discardableResult
    static func record(
        _ error: Error,
        path: DeliveryPath,
        screen: String,
        detail: String? = nil
    ) -> DeliveryFailure {
        record(DeliveryFailure.classify(error, path: path),
               screen: screen, detail: detail)
    }
}
