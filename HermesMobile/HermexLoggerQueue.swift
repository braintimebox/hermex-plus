import Foundation

/// Durable, size-bounded on-disk queue for diagnostic events that have not yet
/// been acknowledged by the ingest server.
///
/// Why this exists: `HermexLogger` used to hold pending events in a memory
/// array only. A force-quit, an app kill or a failed POST deleted them
/// permanently — the server never saw the events that mattered most (the ones
/// right before a hang). This store makes the disk the source of truth: an
/// event is written here *before* the network attempt and removed only after
/// the server confirms it.
///
/// Storage is JSON Lines, one event per line:
/// * appending is a single write at the end — the whole file is not rewritten;
/// * a torn last line (crash mid-write) costs one event, not the file;
/// * recovery parses line by line and keeps every line that parses.
///
/// Removal of confirmed events rewrites through a temp file and
/// `replaceItemAt` (atomic rename on APFS). That protects against a partial
/// file being left behind, not against hardware failure.
///
/// Identity of a queued event is the pair `correlationId:seqNo` — the same key
/// the server uses to deduplicate. `seqNo` alone is not enough: it restarts at
/// 1 in every app launch, so a queue restored after a restart holds events from
/// an older `correlationId` alongside fresh ones with overlapping numbers.
///
/// Not thread-safe by itself: `HermexLogger` owns it on its private serial
/// queue, so exactly one task touches the file at a time.
final class TelemetryEventQueue {

    /// Hard cap on queued events. Measured event size is ~1.1 KB median
    /// (a freeze carries the 100-line `lastEvents` context), so the cap bounds
    /// worst-case disk use near 11 MB in Application Support. Overridable in
    /// tests.
    static let defaultMaxEvents = 10_000

    /// A single event larger than this is refused: it would dominate the disk
    /// budget and make recovery fragile.
    static let maxEncodedEventBytes = 256 * 1024

    /// Event types that survive a flood of low-value traffic. A freeze or an
    /// error is the reason telemetry exists; an `action` event is not.
    static let priorityTypes: Set<String> = ["freeze", "error"]

    private let fileURL: URL
    private let maxEvents: Int
    private let fileManager: FileManager

    /// Events in memory, in enqueue order. Mirrors the file exactly.
    private(set) var events: [[String: Any]] = []

    // MARK: - Counters
    //
    // In memory, exposed through `snapshot()`. They never emit their own
    // diagnostic events: that would recurse into the logger.

    /// Events handed to URLSession (an attempt, not a delivery).
    private(set) var eventsSent = 0
    /// Events the server confirmed.
    private(set) var eventsConfirmed = 0
    /// Retry attempts of events already tried at least once.
    private(set) var eventsRetried = 0
    /// Events removed from the queue after confirmed delivery.
    private(set) var eventsDropped = 0
    /// Events lost because the queue was full when they arrived.
    private(set) var eventsLostToQueueFull = 0
    /// Lines on disk that could not be parsed during recovery.
    private(set) var eventsLostToCorruption = 0

    init(fileURL: URL,
         maxEvents: Int = defaultMaxEvents,
         fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.maxEvents = maxEvents
        self.fileManager = fileManager
    }

    /// Application Support/HermexTelemetry/pending-events.jsonl — the container
    /// the app already uses for its outbox and caches.
    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory,
                                        in: .userDomainMask,
                                        appropriateFor: nil,
                                        create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("HermexTelemetry", isDirectory: true)
            .appendingPathComponent("pending-events.jsonl")
    }

    // MARK: - Identity

    /// `correlationId:seqNo`, matching the server's `eventId`.
    static func key(for event: [String: Any]) -> String? {
        guard let correlation = event["correlationId"] as? String,
              let seq = event["seqNo"] as? Int else { return nil }
        return "\(correlation):\(seq)"
    }

    // MARK: - Lifecycle

    /// Load whatever survived the last run. Corrupt lines are skipped one by
    /// one: a single torn write must not discard the rest of the queue.
    func load() {
        events = []
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            // Missing or unreadable: start empty, keep any file for post-mortem.
            return
        }
        // A crash mid-write can leave a truncated multibyte sequence; decoding
        // with replacement characters still lets the earlier lines parse.
        let text = String(decoding: data, as: UTF8.self)
        var parsed: [[String: Any]] = []
        parsed.reserveCapacity(64)
        var bad = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData),
                  let dict = object as? [String: Any] else {
                bad += 1
                continue
            }
            parsed.append(dict)
        }
        events = parsed
        eventsLostToCorruption = bad

        // Normalise the file before any further append. A torn tail without a
        // trailing newline would otherwise swallow the next appended event into
        // the same, unparseable line. Rewriting here also drops the garbage.
        let needsNormalisation = bad > 0 || (!text.isEmpty && !text.hasSuffix("\n"))
        if needsNormalisation {
            _ = rewrite(parsed)
        }

        enforceCapacityForLoad()
    }

    /// A restored file may exceed the cap if the limit was lowered or the app
    /// crashed while offline for a long time. Trim on load, same policy.
    private func enforceCapacityForLoad() {
        while events.count > maxEvents {
            guard let victim = evictionIndex(incomingIsPriority: false) else { break }
            events.remove(at: victim)
            eventsLostToQueueFull += 1
        }
    }

    // MARK: - Enqueue

    /// Outcome of an enqueue attempt. The caller must distinguish these: only a
    /// disk failure is worth retrying, the other two are permanent for that
    /// event and retrying would spin forever.
    enum EnqueueResult: Equatable {
        /// Written to disk — safe.
        case stored
        /// Larger than `maxEncodedEventBytes`; will never fit.
        case refusedOversized
        /// Queue full of priority events and this one is not priority.
        case refusedQueueFull
        /// Disk write failed; the event is still only in memory.
        case writeFailed

        var isDurable: Bool { self == .stored }
    }

    /// Append an event to disk.
    @discardableResult
    func enqueue(_ event: [String: Any]) -> EnqueueResult {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              data.count <= Self.maxEncodedEventBytes else {
            return .refusedOversized
        }
        guard makeRoom(for: event) else {
            // Queue full of priority events and this newcomer is not one. It is
            // refused (counted) rather than evicting a freeze/error.
            eventsLostToQueueFull += 1
            return .refusedQueueFull
        }
        events.append(event)
        guard appendToDisk(encoded: data) else {
            // Roll the in-memory mirror back: the caller keeps the event and
            // retries, so leaving it here too would enqueue it twice later.
            events.removeLast()
            return .writeFailed
        }
        return .stored
    }

    /// Evict until there is a free slot. Returns `false` when nothing may be
    /// evicted for this newcomer (queue full of priority events, newcomer is
    /// not priority).
    private func makeRoom(for incoming: [String: Any]) -> Bool {
        let incomingIsPriority = Self.isPriority(incoming)
        while events.count >= maxEvents {
            guard let victim = evictionIndex(incomingIsPriority: incomingIsPriority) else {
                return false
            }
            events.remove(at: victim)
            eventsLostToQueueFull += 1
        }
        return true
    }

    /// Eviction order:
    /// 1. quarantined events (already known-undeliverable, dead weight first);
    /// 2. the oldest non-priority event;
    /// 3. the oldest priority event, but only to make room for a priority one.
    private func evictionIndex(incomingIsPriority: Bool) -> Int? {
        if let quarantined = events.firstIndex(where: { $0["deliveryError"] != nil }) {
            return quarantined
        }
        if let firstNonPriority = events.firstIndex(where: { !Self.isPriority($0) }) {
            return firstNonPriority
        }
        return incomingIsPriority && !events.isEmpty ? 0 : nil
    }

    static func isPriority(_ event: [String: Any]) -> Bool {
        guard let type = event["type"] as? String else { return false }
        return priorityTypes.contains(type)
    }

    private func appendToDisk(encoded: Data) -> Bool {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
        } catch {
            return false
        }
        var line = encoded
        line.append(0x0A)

        if !fileManager.fileExists(atPath: fileURL.path) {
            return (try? line.write(to: fileURL, options: .atomic)) != nil
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Reading pending work

    /// Next events to send: queued, not quarantined, in order.
    func pending(limit: Int) -> [[String: Any]] {
        guard limit > 0 else { return [] }
        var batch: [[String: Any]] = []
        batch.reserveCapacity(min(limit, 32))
        for event in events where event["deliveryError"] == nil {
            batch.append(event)
            if batch.count == limit { break }
        }
        return batch
    }

    /// True when at least one event is waiting for a network attempt.
    var hasPending: Bool {
        events.contains { $0["deliveryError"] == nil }
    }

    var count: Int { events.count }

    // MARK: - Removal and quarantine

    /// Drop the events the server confirmed, matched by `correlationId:seqNo`.
    /// Rewrites the file atomically. Returns `false` if the rewrite failed — the
    /// caller retries later, so the server may see a duplicate (deduplicated
    /// there) but nothing is lost locally.
    @discardableResult
    func acknowledge(keys: Set<String>) -> Bool {
        guard !keys.isEmpty else { return true }
        let survivors = events.filter { event in
            guard let key = Self.key(for: event) else { return true }
            return !keys.contains(key)
        }
        let removed = events.count - survivors.count
        guard removed > 0 else { return true }
        guard rewrite(survivors) else { return false }
        events = survivors
        eventsDropped += removed
        return true
    }

    /// Keep an event that the server rejected permanently, but stop retrying it
    /// so one bad event cannot block the whole queue. It stays on disk with the
    /// reason attached — evidence, not a silent deletion.
    @discardableResult
    func quarantine(keys: Set<String>, reason: String) -> Bool {
        guard !keys.isEmpty else { return true }
        var changed = false
        var updated = events
        for index in updated.indices {
            guard let key = Self.key(for: updated[index]), keys.contains(key) else { continue }
            updated[index]["deliveryError"] = reason
            updated[index]["deliveryFailedAt"] = Date().timeIntervalSince1970
            changed = true
        }
        guard changed else { return true }
        guard rewrite(updated) else { return false }
        events = updated
        return true
    }

    private func rewrite(_ survivors: [[String: Any]]) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        let tmpURL = directory.appendingPathComponent("pending-events.jsonl.tmp")
        var payload = Data()
        for event in survivors {
            guard let data = try? JSONSerialization.data(withJSONObject: event) else {
                continue
            }
            payload.append(data)
            payload.append(0x0A)
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try payload.write(to: tmpURL, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: tmpURL)
            } else {
                try fileManager.moveItem(at: tmpURL, to: fileURL)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: tmpURL)
            return false
        }
    }

    // MARK: - Counters

    func noteSent(_ count: Int) { eventsSent += count }
    func noteRetried(_ count: Int) { eventsRetried += count }
    func noteConfirmed(_ count: Int) { eventsConfirmed += count }

    func snapshot() -> [String: Any] {
        [
            "pending": events.count,
            "quarantined": events.filter { $0["deliveryError"] != nil }.count,
            "eventsSent": eventsSent,
            "eventsConfirmed": eventsConfirmed,
            "eventsRetried": eventsRetried,
            "eventsDropped": eventsDropped,
            "eventsLostToQueueFull": eventsLostToQueueFull,
            "eventsLostToCorruption": eventsLostToCorruption,
        ]
    }
}
