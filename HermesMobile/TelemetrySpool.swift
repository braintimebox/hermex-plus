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
///  - the queue is bounded by BOTH a count (5 000) and a byte budget (4 MiB);
///  - every drop is written to a separate, size-limited journal;
///  - if a drop cannot be recorded, it is counted separately: the journal never
///    claims a guarantee it did not deliver.
///
/// The file is append-only (one line per event, one line per acknowledgement) and
/// is compacted only when tombstones outnumber live events. Rewriting the whole
/// queue per event would cost O(queue) per keystroke — at the cap that is 4 MiB
/// written for every draft character.
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

    /// Bookkeeping overhead per item (id, counters, array slot), counted in the
    /// byte budget so 5 000 tiny events cannot inflate memory invisibly.
    static let itemOverhead = 64

    private let eventLimit: Int
    private let byteLimit: Int
    private let dropLogLimit: Int
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
    private var appendsSinceSync: Int = 0
    private var tombstoneCount: Int = 0
    private var dropWritesBlockedUntil: TimeInterval = 0

    /// Test seam: lets a test make `synchronize()` fail deterministically, which
    /// is the only way to exercise the fsync error path without a real disk fault.
    /// Nil in production.
    var syncFailureHook: (() throws -> Void)?

    init(directory: URL? = nil,
         eventLimit: Int = 5_000,
         byteLimit: Int = 4 * 1024 * 1024,
         dropLogLimit: Int = 1024 * 1024) {
        self.eventLimit = eventLimit
        self.byteLimit = byteLimit
        self.dropLogLimit = dropLogLimit
        let dir = directory ?? TelemetrySpool.defaultDirectory()
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

        let item = Item(id: eventId, json: json, size: size, attempts: 0, nextAttemptAt: 0)
        items.append(item)
        bytes += size
        trimOverflowLocked()

        // Durability is claimed only if this record reached the file.
        guard appendRecord(item) else {
            persistFailures += 1
            return .memoryOnly
        }
        return .persisted
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
        appendAck(removed.map(\.id))
    }

    /// Reschedules failed events with bounded backoff; nothing is dropped.
    /// `attempts` is deliberately not persisted: after a relaunch the ladder
    /// restarts, which costs a few extra attempts and never a loss.
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
        appendAck(removed.map(\.id))
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
                if let syncFailureHook { try syncFailureHook() }
                try handle.synchronize()
            }
        } catch {
            // Never retry a broken journal in a loop; count the loss instead.
            unloggedDrops += count
            dropWritesBlockedUntil = now + 30
        }
    }

    /// Keeps exactly one previous generation and never removes the current file
    /// before the new one exists.
    private func rotateDropLog() {
        do {
            try? FileManager.default.removeItem(at: dropsPreviousFile)
            if FileManager.default.fileExists(atPath: dropsFile.path) {
                try FileManager.default.moveItem(at: dropsFile, to: dropsPreviousFile)
            }
        } catch {
            // Rotation failed: keep appending rather than losing the record.
            dropWritesBlockedUntil = 0
        }
    }

    private func recoverDropLog() {
        // A crash mid-rotation leaves evidence, not garbage.
        if FileManager.default.fileExists(atPath: dropsRotatingFile.path) {
            try? FileManager.default.removeItem(at: dropsPreviousFile)
            try? FileManager.default.moveItem(at: dropsRotatingFile, to: dropsPreviousFile)
        }
    }

    // MARK: - append-only spool file

    private struct SpoolRecord: Codable {
        let id: String
        let json: Data
        let attempts: Int
        let nextAttemptAt: TimeInterval
    }

    /// One line: either a record or an acknowledgement.
    private struct SpoolEnvelope: Codable {
        let r: SpoolRecord?
        let a: [String]?
    }

    private func appendRecord(_ item: Item) -> Bool {
        let envelope = SpoolEnvelope(r: SpoolRecord(id: item.id, json: item.json,
                                                    attempts: item.attempts,
                                                    nextAttemptAt: item.nextAttemptAt), a: nil)
        return appendLine(envelope)
    }

    private func appendAck(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        tombstoneCount += ids.count
        _ = appendLine(SpoolEnvelope(r: nil, a: ids))
        if tombstoneCount > items.count {
            _ = compact()
        }
    }

    private func appendLine(_ envelope: SpoolEnvelope) -> Bool {
        guard let data = try? JSONEncoder().encode(envelope) else { return false }
        var line = data
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: spoolFile.path) {
            guard FileManager.default.createFile(atPath: spoolFile.path, contents: nil) else { return false }
        }
        guard let handle = try? FileHandle(forWritingTo: spoolFile) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            appendsSinceSync += 1
            if appendsSinceSync >= 32 {
                appendsSinceSync = 0
                if let syncFailureHook { try syncFailureHook() }
                try handle.synchronize()
            }
            return true
        } catch {
            return false
        }
    }

    /// Rewrites the file with live events only.
    private func compact() -> Bool {
        var out = Data()
        let encoder = JSONEncoder()
        for item in items {
            let envelope = SpoolEnvelope(r: SpoolRecord(id: item.id, json: item.json,
                                                        attempts: item.attempts,
                                                        nextAttemptAt: item.nextAttemptAt), a: nil)
            guard let data = try? encoder.encode(envelope) else {
                droppedTotal += 1
                recordDrop(reason: "encode_failed", count: 1)
                continue
            }
            out.append(data)
            out.append(0x0A)
        }
        do {
            try out.write(to: spoolFile, options: .atomic)
            if let handle = try? FileHandle(forWritingTo: spoolFile) { try? handle.synchronize() }
            tombstoneCount = 0
            return true
        } catch {
            persistFailures += 1
            return false
        }
    }

    /// Forces a rewrite (compaction). Exposed for tests and maintenance.
    @discardableResult
    func persist() -> Bool { compact() }

    /// Streams the file: a corrupted spool larger than the budget must not be read
    /// into memory in one allocation.
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
                if let envelope = try? decoder.decode(SpoolEnvelope.self, from: Data(line)) {
                    if let record = envelope.r {
                        let size = record.json.count + TelemetrySpool.itemOverhead
                        items.append(Item(id: record.id, json: record.json, size: size,
                                          attempts: record.attempts, nextAttemptAt: record.nextAttemptAt))
                        bytes += size
                    } else if let acked = envelope.a {
                        let gone = Set(acked)
                        let removed = items.filter { gone.contains($0.id) }
                        items.removeAll { gone.contains($0.id) }
                        bytes -= removed.reduce(0) { $0 + $1.size }
                        if bytes < 0 { bytes = 0 }
                        tombstoneCount += removed.count
                    }
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
        if beforeCount != items.count || beforeBytes != bytes || tombstoneCount > items.count {
            _ = compact()
        }
    }
}
