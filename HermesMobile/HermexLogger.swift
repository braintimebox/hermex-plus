import Foundation
import UIKit

/// Sends Hermex Plus diagnostics (freezes, errors, lifecycle events) to the
/// Hermes server's log ingest endpoint (`/webhook/hermex-logs` → proxy → :8912).
///
/// Fire-and-forget, never blocks UI: all work happens on a private utility
/// queue. Events are batched (up to 20 per POST) so a noisy stream doesn't
/// spam the server. The server URL is read from the Keychain at send time —
/// no configuration step needed, live server edits just work.
///
/// A ring buffer of the last `maxRecent` events is kept in memory. When a
/// `freeze` event is logged, the buffer is attached as `lastEvents` so the
/// server can see *what the user was doing right before* the main-thread hang
/// (which screen, which button, what action).
final class HermexLogger {
    static let shared = HermexLogger()

    private let queue = DispatchQueue(label: "hermex.logger", qos: .utility)
    private var buffer: [[String: Any]] = []
    private let maxBatch = 20
    private let correlationId = UUID().uuidString
    private var sequenceCounter: Int = 0

    /// Diagnostic identity of the operation currently in flight. Attached to every
    /// event so `sessionId`/`streamId` survive into the log even when the call site
    /// does not know them: the phase and frame channels are shared by every screen.
    private let diagnosticContextLock = NSLock()
    private var diagnosticSessionId: String?
    private var diagnosticStreamId: String?

    func setDiagnosticContext(sessionId: String?, streamId: String?) {
        diagnosticContextLock.lock()
        defer { diagnosticContextLock.unlock() }
        // nil clears: a stale id from a previous conversation must not be attached
        // to events of the next one. Callers pass both explicitly for that reason.
        diagnosticSessionId = sessionId
        diagnosticStreamId = streamId
    }

    private func currentDiagnosticContext() -> (sessionId: String?, streamId: String?) {
        diagnosticContextLock.lock()
        defer { diagnosticContextLock.unlock() }
        return (diagnosticSessionId, diagnosticStreamId)
    }

    /// Pure merge used by `log` and asserted by tests. Caller-supplied extras win,
    /// so an event that already names its stream is never overwritten by ambient
    /// context from a later operation.
    static func applyingDiagnosticContext(
        _ event: [String: Any],
        sessionId: String?,
        streamId: String?
    ) -> [String: Any] {
        var merged = event
        if merged["sessionId"] == nil, let sessionId, !sessionId.isEmpty {
            merged["sessionId"] = sessionId
        }
        if merged["streamId"] == nil, let streamId, !streamId.isEmpty {
            merged["streamId"] = streamId
        }
        return merged
    }

    public enum UserAction: String {
        case send, scroll, openChat, switchServer
        case schedule, pin, unpin, save, share
    }

    /// Ring buffer of recent events, attached to freeze reports for context.
    private var recentEvents: [String] = []
    private let maxRecent = 100

    private init() {}

    /// The app's short version string, attached to every event so a freeze or
    /// stutter can always be attributed to the exact build it came from.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Enqueue a diagnostic event. Never throws, never crashes.
    /// `extras` carries structured context (stack, memory, heavy op) for
    /// freeze/jank reports; merged into the event after the base fields.
    func log(
        type: String,
        durationMs: Double? = nil,
        screen: String? = nil,
        message: String,
        extras: [String: Any]? = nil
    ) {
        queue.async { [self] in
            self.sequenceCounter += 1
            let seqNo = self.sequenceCounter
            let now = Date().timeIntervalSince1970

            // Keep a compact ring buffer of recent events for freeze context.
            var recentLine = "\(Int(now)) \(type)"
            if let screen { recentLine += " [\(screen)]" }
            recentLine += " \(message)"
            recentEvents.append(recentLine)
            if recentEvents.count > maxRecent {
                recentEvents.removeFirst(recentEvents.count - maxRecent)
            }

            var event: [String: Any] = [
                "type": type,
                "ts": now,
                "message": message,
                "appVersion": appVersion,
                "correlationId": correlationId,
                "seqNo": seqNo,
            ]
            if let durationMs { event["durationMs"] = durationMs }
            if let screen { event["screen"] = screen }
            if let extras { event.merge(extras) { _, new in new } }
            let context = currentDiagnosticContext()
            event = Self.applyingDiagnosticContext(
                event,
                sessionId: context.sessionId,
                streamId: context.streamId
            )
            if type == "freeze" {
                event["lastEvents"] = recentEvents
                event["foreground"] = UIApplication.shared.applicationState == .active
            }
            buffer.append(event)
            flushIfNeeded()
        }
    }

    func logUserAction(_ action: UserAction, screen: String? = nil, extras: [String: Any]? = nil) {
        log(type: "action", screen: screen, message: "user \(action.rawValue)", extras: extras)
    }

    /// Read the configured server URL from the Keychain (same source the app
    /// uses for all API traffic). Synchronous + cheap — fine on a utility queue.
    private var serverBaseURL: URL? {
        guard let urlString = try? KeychainStore().load(.serverURL) else { return nil }
        return URL(string: urlString)
    }

    private func flushIfNeeded() {
        guard !buffer.isEmpty, let baseURL = serverBaseURL else { return }
        let batch = Array(buffer.prefix(maxBatch))
        buffer.removeFirst(batch.count)
        send(batch, to: baseURL)
    }

    private func send(_ events: [[String: Any]], to baseURL: URL) {
        let webhook = baseURL.appendingPathComponent("webhook/hermex-logs")
        var request = URLRequest(url: webhook)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Hermex-Request-ID")  // HERMEX-FORK: request-id for log correlation
        request.httpBody = try? JSONSerialization.data(withJSONObject: events)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}
