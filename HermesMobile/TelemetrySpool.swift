import Foundation

/// Durable, bounded queue for diagnostic events.
///
/// Why it exists: the previous logger removed an event from its buffer *before*
/// the POST result was known, and ignored the result entirely. Every failed
/// POST therefore destroyed up to 20 events with no trace. Measured on real
/// data: 651 of 2 693 events (24.2%) never reached the server, and the proxy
/// log shows no request at all during the largest gaps — the loss happened
/// inside the client.
///
/// Contract:
///  - an event leaves the queue only after a 2xx acknowledgement;
///  - a failed attempt reschedules the same event with bounded backoff;
///  - nothing is deleted because of an error, ever;
///  - the only deletion path is overflow, and every dropped event is recorded
///    in a separate file so the loss remains diagnosable.
///
/// All methods are synchronous and cheap; the caller (HermexLogger) serialises
/// them on its own utility queue. A lock is kept anyway so the spool is safe if
/// a future caller forgets that rule.
final class TelemetrySpool {

    struct Item {
        let id: String
        let json: Data
        var attempts: Int
        var nextAttemptAt: TimeInterval
    }

    /// Backoff for retries, seconds. Capped, never infinite growth.
    static let backoff: [TimeInterval] = [2, 8, 30, 120, 600]

    private let memoryLimit: Int
    private let diskLimit: Int
    private let directory: URL
    private let spoolFile: URL
    private let dropsFile: URL
    private let lock = NSLock()

    private var items: [Item] = []
    private var droppedTotal: Int = 0

    init(directory: URL? = nil,
         memoryLimit: Int = 500,
         diskLimit: Int = 5_000) {
        self.memoryLimit = memoryLimit
        self.diskLimit = diskLimit
        let dir = directory ?? TelemetrySpool.defaultDirectory()
        self.directory = dir
        self.spoolFile = dir.appendingPathComponent("telemetry-spool.jsonl")
        self.dropsFile = dir.appendingPathComponent("telemetry-drops.jsonl")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("HermexTelemetry", isDirectory: true)
    }

    // MARK: - public API

    var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return items.count
    }

    var droppedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return droppedTotal
    }

    /// Adds an event. Overflow drops the OLDEST event and records why.
    @discardableResult
    func append(eventId: String, json: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        items.append(Item(id: eventId, json: json, attempts: 0, nextAttemptAt: 0))
        var overflowed = 0
        while items.count > memoryLimit {
            items.removeFirst()
            overflowed += 1
        }
        if overflowed > 0 {
            droppedTotal += overflowed
            recordDrop(reason: "overflow_memory", count: overflowed)
        }
        persist()
        return overflowed == 0
    }

    /// Events whose retry window has opened, oldest first.
    func ready(now: Date = Date(), limit: Int) -> [Item] {
        lock.lock(); defer { lock.unlock() }
        let t = now.timeIntervalSince1970
        return items.filter { $0.nextAttemptAt <= t }.prefix(limit).map { $0 }
    }

    /// Removes acknowledged events. The only successful removal path.
    func acknowledge(ids: [String]) {
        lock.lock()
        defer { lock.unlock() }
        let gone = Set(ids)
        items.removeAll { gone.contains($0.id) }
        persist()
    }

    /// Reschedules failed events with bounded backoff; nothing is dropped.
    func reschedule(ids: [String], now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        let affected = Set(ids)
        let t = now.timeIntervalSince1970
        for index in items.indices where affected.contains(items[index].id) {
            let attempts = items[index].attempts + 1
            let delay = TelemetrySpool.backoff[min(attempts - 1, TelemetrySpool.backoff.count - 1)]
            items[index].attempts = attempts
            items[index].nextAttemptAt = t + delay
        }
        // Disk cap is a hard bound: past it the oldest events go, with a record.
        var overflowed = 0
        while items.count > diskLimit {
            items.removeFirst()
            overflowed += 1
        }
        if overflowed > 0 {
            droppedTotal += overflowed
            recordDrop(reason: "overflow_disk", count: overflowed)
        }
        persist()
    }

    /// Explicit, caller-driven drop (e.g. a payload the server refuses forever).
    func drop(ids: [String], reason: String) {
        lock.lock()
        defer { lock.unlock() }
        let gone = Set(ids)
        let before = items.count
        items.removeAll { gone.contains($0.id) }
        let removed = before - items.count
        if removed > 0 {
            droppedTotal += removed
            recordDrop(reason: reason, count: removed)
        }
        persist()
    }

    /// Independent diagnosis channel: never shares a queue with the events
    /// whose loss it describes.
    private func recordDrop(reason: String, count: Int) {
        let record: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "reason": reason,
            "count": count,
            "pending": items.count,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record) else { return }
        var line = data
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: dropsFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: dropsFile, options: .atomic)
        }
    }

    // MARK: - persistence

    private func load() {
        guard let data = try? Data(contentsOf: spoolFile), !data.isEmpty else { return }
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A) {
            guard let record = try? decoder.decode(SpoolRecord.self, from: Data(line)) else { continue }
            items.append(Item(id: record.id,
                              json: record.json,
                              attempts: record.attempts,
                              nextAttemptAt: record.nextAttemptAt))
        }
        if items.count > memoryLimit {
            let overflowed = items.count - memoryLimit
            items.removeFirst(overflowed)
            droppedTotal += overflowed
            recordDrop(reason: "overflow_on_load", count: overflowed)
            persist()
        }
    }

    private struct SpoolRecord: Codable {
        let id: String
        let json: Data
        let attempts: Int
        let nextAttemptAt: TimeInterval
    }

    private func persist() {
        let records = items.map { SpoolRecord(id: $0.id, json: $0.json, attempts: $0.attempts, nextAttemptAt: $0.nextAttemptAt) }
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        // One line per record keeps the file append-friendly and diffable.
        var out = Data()
        for record in records {
            guard let one = try? JSONEncoder().encode(record) else { continue }
            out.append(one)
            out.append(0x0A)
        }
        _ = encoded
        try? out.write(to: spoolFile, options: .atomic)
    }
}
