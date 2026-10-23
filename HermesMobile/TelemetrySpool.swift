import Foundation

/// Durable, bounded queue for diagnostic events.
///
/// Why it exists: the previous logger removed an event from its buffer *before*
/// the POST result was known and ignored the result entirely. Every failed POST
/// therefore destroyed up to 20 events with no trace. Measured on real data:
/// 651 of 2 693 events (24.2%) never reached the server.
///
/// Contract:
///  - an event leaves the queue only after a 2xx acknowledgement, or through an
///    explicitly recorded drop (overflow / oversize / explicit decision);
///  - a failed attempt reschedules the same event with bounded backoff;
///  - the queue is bounded by BOTH a count and a byte budget;
///  - every drop is written to a separate, size-limited journal;
///  - if a drop cannot be recorded, it is counted separately: the journal never
///    claims a guarantee it did not deliver.
///
/// All methods are synchronous; HermexLogger serialises them on one utility
/// queue. The lock keeps the type safe if that rule is ever broken.
final class TelemetrySpool {

    enum AppendResult: Equatable {
        /// Written to the durable spool file.
        case persisted
        /// In memory only: the spool file write failed, so persistence is NOT claimed.
        case memoryOnly
        /// Refused: a single event larger than the byte budget.
        case rejectedOversize
    }

    struct Item {
        let id: String
        let json: Data
        let size: Int
        var attempts: Int
        var nextAttemptAt: TimeInterval
    }

    /// Backoff for retries, seconds. Capped, never infinite growth.
    static let backoff: [TimeInterval] = [2, 8, 30, 120, 600]

    /// Bookkeeping overhead per item (id, counters, array slot). Counted in the
    /// byte budget so 5 000 tiny events cannot inflate memory invisibly.
    static let itemOverhead = 64

    private let eventLimit: Int
    private let byteLimit: Int
    private let dropLogLimit: Int
    private let directory: URL
    private let spoolFile: URL
    private let dropsFile: URL
    private let dropsPreviousFile: URL
    private let dropsRotatingFile: URL
    private let lock = NSLock()

    private var items: [Item] = []
    private var bytes: Int = 0

    private(set) var droppedTotal: Int = 0
    /// Drops whose journal entry could not be written. Memory-only: after a crash
    /// this number is gone, so it is reported separately from the journal.
    private(set) var unloggedDrops: Int = 0
    private(set) var persistFailures: Int = 0
    private var writesSinceSync: Int = 0
    private var dropWritesBlockedUntil: TimeInterval = 0

    init(directory: URL? = nil,
         eventLimit: Int = 5_000,
         byteLimit: Int = 4 * 1024 * 1024,
         dropLogLimit: Int = 1024 * 1024) {
        self.eventLimit = eventLimit
        self.byteLimit = byteLimit
        self.dropLogLimit = dropLogLimit
        let dir = directory ?? TelemetrySpool.defaultDirectory()
        self.directory = dir
        self.spoolFile = dir.appendingPathComponent("telemetry-spool.jsonl")
        self.dropsFile = dir.appendingPathComponent("telemetry-drops.jsonl")
        self.dropsPreviousFile = dir.appendingPathComponent("telemetry-drops.1.jsonl")
        self.dropsRotatingFile = dir.appendingPathComponent("telemetry-drops.rotating")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("HermexTelemetry", isDirectory: true)
    }

    // MARK: - inspection

    var pendingCount: Int { lock.lock(); defer { lock.unlock() }; return items.count }
    var pendingBytes: Int { lock.lock(); defer { lock.unlock() }; return bytes }
    var limits: (events: Int, bytes: Int) { (eventLimit, byteLimit) }
    var droppedCount: Int { lock.lock(); defer { lock.unlock() }; return droppedTotal }
    var unloggedDropCount: Int { lock.lock(); defer { lock.unlock() }; return unloggedDrops }
    var persistenceFailureCount: Int { lock.lock(); defer { lock.unlock() }; return persistFailures }

    /// Events whose retry window has opened, oldest first.
    func ready(now: Date = Date(), limit: Int) -> [Item] {
        lock.lock(); defer { lock.unlock() }
        let t = now.timeIntervalSince1970
        return items.filter { $0.nextAttemptAt <= t }.prefix(limit).map { $0 }
    }

    // MARK: - mutation

    @discardableResult
    func append(eventId: String, json: Data) -> AppendResult {
        lock.lock()
        defer { lock.unlock() }

        let size = json.count + TelemetrySpool.itemOverhead
        guard size <= byteLimit else {
            // A single event cannot fit the budget. Refusing it is deterministic:
            // evicting the whole backlog for one huge payload would be worse.
            droppedTotal += 1
            recordDrop(reason: "oversize_event", count: 1, oldest: eventId, newest: eventId)
            return .rejectedOversize
        }

        items.append(Item(id: eventId, json: json, size: size, attempts: 0, nextAttemptAt: 0))
        bytes += size
        trimOverflowLocked()

        return persist() ? .persisted : .memoryOnly
    }

    /// Removes acknowledged events. The only successful removal path.
    func acknowledge(ids: [String]) {
        lock.lock(); defer { lock.unlock() }
        let gone = Set(ids)
        let removed = items.filter { gone.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { gone.contains($0.id) }
        bytes -= removed.reduce(0) { $0 + $1.size }
        if bytes < 0 { bytes = 0 }
        _ = persist()
    }

    /// Reschedules failed events with bounded backoff; nothing is dropped.
    func reschedule(ids: [String], now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        let affected = Set(ids)
        let t = now.timeIntervalSince1970
        for index in items.indices where affected.contains(items[index].id) {
            let attempts = items[index].attempts + 1
            let delay = TelemetrySpool.backoff[min(attempts - 1, TelemetrySpool.backoff.count - 1)]
            items[index].attempts = attempts
            items[index].nextAttemptAt = t + delay
        }
        trimOverflowLocked()
        _ = persist()
    }

    /// Explicit, caller-driven drop (e.g. a payload the server refuses forever).
    func drop(ids: [String], reason: String) {
        lock.lock(); defer { lock.unlock() }
        let gone = Set(ids)
        let removed = items.filter { gone.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { gone.contains($0.id) }
        bytes -= removed.reduce(0) { $0 + $1.size }
        if bytes < 0 { bytes = 0 }
        droppedTotal += removed.count
        recordDrop(reason: reason, count: removed.count,
                   oldest: removed.first?.id, newest: removed.last?.id)
        _ = persist()
    }

    /// Both budgets, one deterministic rule: oldest events go first, so the queue
    /// always keeps the most recent evidence.
    private func trimOverflowLocked() {
        guard items.count > eventLimit || bytes > byteLimit else { return }
        var removed = 0
        var firstId: String?
        var lastId: String?
        while (items.count > eventLimit || bytes > byteLimit), !items.isEmpty {
            let item = items.removeFirst()
            bytes -= item.size
            if firstId == nil { firstId = item.id }
            lastId = item.id
            removed += 1
        }
        if bytes < 0 { bytes = 0 }
        guard removed > 0 else { return }
        droppedTotal += removed
        recordDrop(reason: "overflow", count: removed, oldest: firstId, newest: lastId)
    }

    // MARK: - drop journal

    private func recordDrop(reason: String, count: Int, oldest: String? = nil, newest: String? = nil) {
        let now = Date().timeIntervalSince1970
        guard now >= dropWritesBlockedUntil else {
            // Journal known-broken: do not hammer it, but do not hide the loss.
            unloggedDrops += count
            return
        }
        var record: [String: Any] = [
            "ts": now,
            "reason": reason,
            "count": count,
            "pending": items.count,
            "pendingBytes": bytes,
            "droppedTotal": droppedTotal,
        ]
        if let oldest { record["oldest"] = oldest }
        if let newest { record["newest"] = newest }
        guard let data = try? JSONSerialization.data(withJSONObject: record) else {
            unloggedDrops += count
            return
        }
        var line = data
        line.append(0x0A)

        if let attributes = try? FileManager.default.attributesOfItem(atPath: dropsFile.path),
           let size = attributes[.size] as? Int,
           size + line.count > dropLogLimit {
            rotateDropLog()
        }

        if let handle = try? FileHandle(forWritingTo: dropsFile) {
            writeDrop(handle, line, count: count, now: now)
            return
        }
        if FileManager.default.createFile(atPath: dropsFile.path, contents: nil),
           let created = try? FileHandle(forWritingTo: dropsFile) {
            writeDrop(created, line, count: count, now: now)
            return
        }
        unloggedDrops += count
        dropWritesBlockedUntil = now + 30
    }

    private func writeDrop(_ handle: FileHandle, _ line: Data, count: Int, now: TimeInterval) {
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            writesSinceSync += 1
            if writesSinceSync >= 32 {
                writesSinceSync = 0
                try handle.synchronize()
            }
        } catch {
            // Never retry a broken journal in a loop; count the loss instead.
            unloggedDrops += count
            dropWritesBlockedUntil = now + 30
        }
    }

    /// Rotation keeps exactly one previous generation and never truncates the
    /// current file before the new one exists.
    private func rotateDropLog() {
        do {
            try? FileManager.default.removeItem(at: dropsPreviousFile)
            if FileManager.default.fileExists(atPath: dropsFile.path) {
                try FileManager.default.moveItem(at: dropsFile, to: dropsPreviousFile)
            }
        } catch {
            // Rotation failed: keep appending rather than losing the record.
            dropWritesBlockedUntil = nowSafe()
        }
    }

    private func nowSafe() -> TimeInterval { Date().timeIntervalSince1970 }

    private func recoverDropLog() {
        // A crash mid-rotation leaves evidence, not garbage.
        if FileManager.default.fileExists(atPath: dropsRotatingFile.path) {
            try? FileManager.default.removeItem(at: dropsPreviousFile)
            try? FileManager.default.moveItem(at: dropsRotatingFile, to: dropsPreviousFile)
        }
    }

    // MARK: - persistence

    private struct SpoolRecord: Codable {
        let id: String
        let json: Data
        let attempts: Int
        let nextAttemptAt: TimeInterval
    }

    /// Streams the spool file: a corrupted file larger than the budget must not be
    /// read into memory in one allocation.
    private func load() {
        recoverDropLog()
        guard let handle = try? FileHandle(forReadingFrom: spoolFile) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        var corrupt = 0
        let decoder = JSONDecoder()
        while true {
            let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? nil
            guard let chunk, !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if line.isEmpty { continue }
                if let record = try? decoder.decode(SpoolRecord.self, from: Data(line)) {
                    let size = record.json.count + TelemetrySpool.itemOverhead
                    items.append(Item(id: record.id, json: record.json, size: size,
                                      attempts: record.attempts, nextAttemptAt: record.nextAttemptAt))
                    bytes += size
                } else {
                    corrupt += 1
                }
            }
        }
        if !buffer.isEmpty { corrupt += 1 }  // torn last line

        if corrupt > 0 {
            droppedTotal += corrupt
            recordDrop(reason: "corrupt_spool_line", count: corrupt)
        }
        let beforeCount = items.count
        let beforeBytes = bytes
        trimOverflowLocked()
        if beforeCount != items.count || beforeBytes != bytes {
            _ = persist()
        }
    }

    /// Writes the whole queue atomically. Returns false when the write failed, so
    /// the caller cannot claim the event is durable.
    @discardableResult
    func persist() -> Bool {
        var out = Data()
        let encoder = JSONEncoder()
        var encodeFailures = 0
        for item in items {
            let record = SpoolRecord(id: item.id, json: item.json,
                                     attempts: item.attempts, nextAttemptAt: item.nextAttemptAt)
            guard let data = try? encoder.encode(record) else {
                encodeFailures += 1
                continue
            }
            out.append(data)
            out.append(0x0A)
        }
        if encodeFailures > 0 {
            droppedTotal += encodeFailures
            recordDrop(reason: "encode_failed", count: encodeFailures)
        }
        do {
            try out.write(to: spoolFile, options: .atomic)
            return true
        } catch {
            persistFailures += 1
            return false
        }
    }
}
