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
    private let maxBatch = 20
    private let correlationId = UUID().uuidString
    private var sequenceCounter: Int = 0

    /// Injected for tests: a URLSession backed by URLProtocol, and a URL source.
    private let session: URLSession
    private let serverURLProvider: () -> URL?
    /// How long an unanswered request may block the sender before it is retried.
    private let stalledTimeout: TimeInterval

    /// Durable queue: an event survives a failed POST, a timeout and a restart.
    private let spool: TelemetrySpool
    private var flushTimer: DispatchSourceTimer?
    private var inFlight = false
    private var inFlightSince: TimeInterval = 0
    /// Counting of POST outcomes, exposed for tests and diagnostics.
    private(set) var deliveredBatches = 0
    private(set) var failedBatches = 0

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

    init(session: URLSession = .shared,
         spool: TelemetrySpool = TelemetrySpool(),
         serverURLProvider: @escaping () -> URL? = {
             (try? KeychainStore().load(.serverURL)).flatMap { URL(string: $0) }
         },
         stalledTimeout: TimeInterval = 30,
         startTimer: Bool = true) {
        self.stalledTimeout = stalledTimeout
        self.session = session
        self.spool = spool
        self.serverURLProvider = serverURLProvider
        if startTimer { startFlushTimer() }
    }

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
            let eventId = UUID().uuidString
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
                // Unique per event across launches, restarts and versions.
                // This is the only key the server deduplicates on.
                "eventId": eventId,
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
            enqueue(event, eventId: eventId)
            flushIfNeeded()
        }
    }

    // MARK: - delivery

    private func enqueue(_ event: [String: Any], eventId: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: event) else { return }
        _ = spool.append(eventId: eventId, json: data)
    }

    /// Serialises a batch and posts it. An event is removed from the spool only
    /// after a 2xx answer; every failure reschedules the same events.
    private func flushIfNeeded() {
        if inFlight {
            // A completion that never arrives (session invalidated, process
            // suspended mid-request) must not wedge the sender forever.
            let stalled = Date().timeIntervalSince1970 - inFlightSince
            guard stalled < stalledTimeout else {
                inFlight = false
                failedBatches += 1
                return
            }
            return
        }
        guard let baseURL = serverURLProvider() else {
            // No server configured yet: keep the events, retry later. They are
            // bounded by the spool, so this cannot grow without limit.
            return
        }
        let batch = spool.ready(limit: maxBatch)
        guard !batch.isEmpty else { return }

        var payload = Data("[".utf8)
        for (index, item) in batch.enumerated() {
            if index > 0 { payload.append(0x2C) }
            payload.append(item.json)
        }
        payload.append(0x5D)

        var request = URLRequest(url: baseURL.appendingPathComponent("webhook/hermex-logs"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Hermex-Request-ID")
        request.httpBody = payload
        request.timeoutInterval = 10

        inFlight = true
        inFlightSince = Date().timeIntervalSince1970
        let ids = batch.map(\.id)
        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            self.queue.async {
                self.inFlight = false
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if error == nil && (200..<300).contains(status) {
                    self.spool.acknowledge(ids: ids)
                    self.deliveredBatches += 1
                } else {
                    // Timeout, network failure, 5xx, 429 or an unreadable answer:
                    // the server may already have stored the event, and the retry
                    // is idempotent because every event carries a unique eventId.
                    self.failedBatches += 1
                    self.spool.reschedule(ids: ids)
                }
                self.flushIfNeeded()
            }
        }.resume()
    }

    /// Called when the app goes to the background: give the queue one chance to
    /// drain inside the time iOS grants.
    func flushNow() {
        queue.async { [self] in
            flushIfNeeded()
        }
    }

    /// Test seam: number of events still queued.
    var pendingEventCount: Int { spool.pendingCount }
    /// Test seam: number of events dropped by the overflow policy.
    var droppedEventCount: Int { spool.droppedCount }
    func logUserAction(_ action: UserAction, screen: String? = nil, extras: [String: Any]? = nil) {
        log(type: "action", screen: screen, message: "user \(action.rawValue)", extras: extras)
    }

    /// A periodic tick is what turns "retry eventually" into reality: without it
    /// a failed batch would wait for the next unrelated log() call.
    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            self?.flushIfNeeded()
        }
        timer.resume()
        flushTimer = timer
    }
}
