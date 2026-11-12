import Foundation
import UIKit

/// Sends Hermex Plus diagnostics (freezes, errors, lifecycle events) to the
/// Hermes server's log ingest endpoint (`/webhook/hermex-logs` → proxy → :8912).
///
/// Never blocks the UI: all work happens on a private utility queue.
///
/// ## Delivery guarantee
///
/// An event is written to a durable on-disk queue (`TelemetryEventQueue`)
/// *before* the first network attempt and removed only after the server
/// confirms it. Consequences:
/// * a force-quit or a crash loses at most the events that could not be written
///   to disk at all (broken disk, not a normal path);
/// * a failed POST, a timeout or a 5xx leaves events on disk for the retry;
/// * an ambiguous result (request sent, response lost) keeps the events queued,
///   and the retry is deduplicated server-side by `correlationId` + `seqNo`.
///
/// Retries use exponential backoff (1 → 2 → 4 → 8 → 16 → 30 s, then one
/// attempt per 30 s). Permanent rejections (malformed/unauthorised/unknown
/// route) are quarantined in place — kept on disk as evidence with the reason
/// attached — so one bad event cannot block the queue.
///
/// A ring buffer of the last `maxRecent` events is kept in memory. When a
/// `freeze` event is logged, the buffer is attached as `lastEvents` so the
/// server can see *what the user was doing right before* the main-thread hang.
final class HermexLogger {
    static let shared = HermexLogger()

    // MARK: - Identity and constants

    /// Identifies this app launch. Combined with `seqNo` it forms the dedup key
    /// the server uses, so it must change on every launch (a fresh UUID) and
    /// stay stable within one launch.
    private let correlationId = UUID().uuidString
    private var sequenceCounter: Int = 0

    private let queue = DispatchQueue(label: "hermex.logger", qos: .utility)
    private let maxBatch = 20
    private let maxRecent = 100

    /// Debounce before a flush, so a burst of events becomes one request.
    private let flushDebounce: TimeInterval

    /// 1 → 2 → 4 → 8 → 16 → 30 s, then the last value repeats forever.
    private let retryDelays: [TimeInterval]
    static let defaultRetryDelays: [TimeInterval] = [1, 2, 4, 8, 16, 30]

    // MARK: - State (touched only on `queue`)

    private let store: TelemetryEventQueue
    private let session: URLSession
    private let serverURLProvider: () -> URL?

    /// Ring buffer of recent events, attached to freeze reports for context.
    private var recentEvents: [String] = []

    /// Events that could not be written to disk. They are NOT considered safe;
    /// they stay here and are retried on the next flush. Bounded so a broken
    /// disk cannot grow this without limit.
    private var undeliveredInMemory: [[String: Any]] = []

    private var isSending = false
    private var retryAttempt = 0
    private var pendingFlush: DispatchWorkItem?
    private var pendingRetry: DispatchWorkItem?
    /// Current send batch size; shrinks on 413 and recovers on success.
    private var batchLimit = 20
    private var activationObserver: NSObjectProtocol?

    public enum UserAction: String {
        case send, scroll, openChat, switchServer
        case schedule, pin, unpin, save, share
    }

    // MARK: - Init

    private convenience init() {
        self.init(
            store: TelemetryEventQueue(fileURL: TelemetryEventQueue.defaultFileURL()),
            session: .shared,
            serverURLProvider: {
                guard let urlString = try? KeychainStore().load(.serverURL) else { return nil }
                return URL(string: urlString)
            },
            flushDebounce: 0.5,
            retryDelays: HermexLogger.defaultRetryDelays
        )
    }

    /// Injectable initialiser: tests supply their own store file, transport and
    /// retry timings. Production uses the Keychain-backed URL and the spec
    /// delays.
    init(store: TelemetryEventQueue,
         session: URLSession,
         serverURLProvider: @escaping () -> URL?,
         flushDebounce: TimeInterval = 0.5,
         retryDelays: [TimeInterval] = HermexLogger.defaultRetryDelays) {
        self.store = store
        self.session = session
        self.serverURLProvider = serverURLProvider
        self.flushDebounce = flushDebounce
        self.retryDelays = retryDelays
        // Restore whatever the last run failed to deliver.
        queue.async { [self] in
            store.load()
            if store.hasPending { scheduleFlush(after: 0) }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // Back in the foreground: a network that was gone may be back. Uses
            // the app's existing lifecycle notification — no new reachability
            // infrastructure.
            self?.queue.async { self?.retryNow() }
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    /// The app's short version string, attached to every event so a freeze or
    /// stutter can always be attributed to the exact build it came from.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    // MARK: - Public API

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
            if type == "freeze" {
                event["lastEvents"] = recentEvents
                event["foreground"] = UIApplication.shared.applicationState == .active
            }

            // Persist first, then attempt delivery. Only a disk failure leaves
            // the event in memory for another attempt; an oversized event or a
            // queue full of priority events is refused permanently (counted in
            // the store), because retrying those would spin forever.
            if store.enqueue(event) == .writeFailed {
                undeliveredInMemory.append(event)
                if undeliveredInMemory.count > maxBatch {
                    undeliveredInMemory.removeFirst(undeliveredInMemory.count - maxBatch)
                }
            }
            scheduleFlush(after: flushDebounce)
        }
    }

    func logUserAction(_ action: UserAction, screen: String? = nil, extras: [String: Any]? = nil) {
        log(type: "action", screen: screen, message: "user \(action.rawValue)", extras: extras)
    }

    // MARK: - Flush scheduling

    private func scheduleFlush(after delay: TimeInterval) {
        pendingFlush?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingFlush = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Move memory-only events onto disk, then send the next batch.
    private func flush() {
        guard !isSending else { return }
        drainMemoryIntoStore()
        guard store.hasPending, let baseURL = serverURLProvider() else { return }
        let batch = store.pending(limit: min(batchLimit, maxBatch))
        guard !batch.isEmpty else { return }
        send(batch, to: baseURL)
    }

    private func drainMemoryIntoStore() {
        guard !undeliveredInMemory.isEmpty else { return }
        var stillFailing: [[String: Any]] = []
        for event in undeliveredInMemory {
            if store.enqueue(event) == .writeFailed { stillFailing.append(event) }
        }
        undeliveredInMemory = stillFailing
    }

    // MARK: - Network

    private func send(_ events: [[String: Any]], to baseURL: URL) {
        isSending = true
        store.noteSent(events.count)
        if retryAttempt > 0 { store.noteRetried(events.count) }

        let webhook = baseURL.appendingPathComponent("webhook/hermex-logs")
        var request = URLRequest(url: webhook)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Hermex-Request-ID")  // HERMEX-FORK: request-id for log correlation
        request.httpBody = try? JSONSerialization.data(withJSONObject: events)
        request.timeoutInterval = 10

        // Ordered keys: partial confirmation removes the head of the batch, so
        // order matters here.
        let orderedKeys = events.compactMap { TelemetryEventQueue.key(for: $0) }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let outcome = Self.classify(data: data, response: response,
                                        error: error, batchCount: events.count)
            self.queue.async {
                self.handle(outcome, orderedKeys: orderedKeys,
                            batchCount: events.count, baseURL: baseURL)
            }
        }.resume()
    }

    enum SendOutcome: Equatable {
        /// Server accounted for this many events from the head of the batch.
        case confirmed(Int)
        /// Batch was too large; send fewer events next time.
        case batchTooLarge
        /// Worth retrying after a delay. `nil` delay means "use the backoff".
        case retryable(retryAfter: TimeInterval?)
        /// Never going to succeed with this payload. Keep it, stop retrying it.
        case permanent(reason: String)
    }

    /// Interpret the server's reply.
    ///
    /// Contract (server.py `do_POST` → `/webhook/hermex-logs`):
    /// `200 {"ok": true, "received": N, "stored": M, "batchId": ...}`.
    /// `received` counts every item the server processed — including ones it
    /// dropped as duplicates — so a retried batch legitimately answers
    /// `stored: 0` with `received: N`. Only `received` may be used to decide
    /// what to remove.
    static func classify(data: Data?,
                         response: URLResponse?,
                         error: Error?,
                         batchCount: Int) -> SendOutcome {
        if error != nil {
            // Transport-level failure (offline, DNS, timeout, connection reset).
            // The server may still have written the events before the reply was
            // lost — hence a retry, deduplicated server-side.
            return .retryable(retryAfter: nil)
        }
        guard let http = response as? HTTPURLResponse else {
            return .retryable(retryAfter: nil)
        }
        switch http.statusCode {
        case 200...299:
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let payload = object as? [String: Any],
                  payload["ok"] as? Bool == true else {
                // 2xx with an unreadable or unexpected body: we cannot tell what
                // was stored. Keep everything and retry.
                return .retryable(retryAfter: nil)
            }
            let received = payload["received"] as? Int ?? 0
            if received >= batchCount { return .confirmed(batchCount) }
            if received > 0 { return .confirmed(received) }
            // ok:true but nothing accepted — ambiguous, retry.
            return .retryable(retryAfter: nil)

        case 413:
            // Payload too large: shrink the batch, the events themselves are fine.
            return .batchTooLarge

        case 429:
            return .retryable(retryAfter: Self.retryAfter(from: http))

        case 408:
            return .retryable(retryAfter: nil)

        case 500...599:
            return .retryable(retryAfter: nil)

        case 400, 401, 403, 404, 405, 410, 422:
            // Malformed payload, bad auth, wrong route: repeating cannot help.
            return .permanent(reason: "http \(http.statusCode)")

        default:
            if (400...499).contains(http.statusCode) {
                return .permanent(reason: "http \(http.statusCode)")
            }
            return .retryable(retryAfter: nil)
        }
    }

    /// `Retry-After` is either delta-seconds or an HTTP date. Accept only sane
    /// values, so a broken header cannot park the queue for hours.
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) {
            return min(max(seconds, 1), 600)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        return min(max(date.timeIntervalSinceNow, 1), 600)
    }

    // MARK: - Outcome handling

    private func handle(_ outcome: SendOutcome,
                        orderedKeys: [String],
                        batchCount: Int,
                        baseURL: URL) {
        isSending = false
        switch outcome {
        case .confirmed(let count):
            let confirmedKeys = count >= batchCount
                ? Set(orderedKeys)
                : Set(orderedKeys.prefix(count))
            if !store.acknowledge(keys: confirmedKeys) {
                // Could not rewrite the file: retry soon. A duplicate on the
                // server is harmless (dedup), a lost local event is not.
                scheduleRetry(after: 5)
                return
            }
            // Count only what actually left the queue, so a failed rewrite can
            // never inflate the confirmed counter.
            store.noteConfirmed(count)
            retryAttempt = 0
            batchLimit = maxBatch
            if store.hasPending { scheduleFlush(after: 0) }

        case .batchTooLarge:
            // Retrying the same oversized batch can only fail. Halve it.
            batchLimit = max(1, batchCount / 2)
            retryAttempt = 0
            scheduleRetry(after: 1)

        case .retryable(let retryAfter):
            scheduleRetry(after: retryAfter ?? nextBackoff())

        case .permanent(let reason):
            // Keep the events on disk with the reason, stop retrying this batch,
            // and let the rest of the queue through.
            _ = store.quarantine(keys: Set(orderedKeys), reason: reason)
            retryAttempt = 0
            if store.hasPending { scheduleFlush(after: 0) }
        }
    }

    private func nextBackoff() -> TimeInterval {
        let delay = Self.backoffDelay(attempt: retryAttempt, delays: retryDelays)
        retryAttempt += 1
        return delay
    }

    /// 1 → 2 → 4 → 8 → 16 → 30 s, then the last value forever. Pure function so
    /// the sequence is testable without waiting.
    static func backoffDelay(attempt: Int, delays: [TimeInterval]) -> TimeInterval {
        guard !delays.isEmpty else { return 30 }
        let index = min(max(attempt, 0), delays.count - 1)
        return delays[index]
    }

    private func scheduleRetry(after delay: TimeInterval) {
        pendingRetry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingRetry = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func retryNow() {
        guard !isSending else { return }
        retryAttempt = 0
        flush()
    }

    // MARK: - Test hooks

    /// Force a flush on the logger's queue and wait for it (tests only).
    func flushNowForTesting() {
        queue.sync { self.flush() }
    }

    /// Current queue counters.
    func countersSnapshot() -> [String: Any] {
        queue.sync { store.snapshot() }
    }

    /// Events currently waiting on disk, in order (tests only).
    func pendingEventsForTesting() -> [[String: Any]] {
        queue.sync { store.events }
    }

    /// Blocks until the logger's queue is idle (tests only).
    func drainForTesting() {
        queue.sync {}
    }

    /// Events that failed to reach the disk and are only in memory (tests only).
    func undeliveredInMemoryCountForTesting() -> Int {
        queue.sync { undeliveredInMemory.count }
    }

    /// True when no request is in flight (tests only). Lets a test wait for a
    /// settled state before requesting another flush.
    func isIdleForTesting() -> Bool {
        queue.sync { !isSending }
    }
}
