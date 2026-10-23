import XCTest
@testable import HermesMobile

/// Deterministic tests for the telemetry delivery path.
///
/// No real network, no sleeps that wait for a condition, no dependency on the
/// device clock: every request goes through `TelemetryURLProtocol`, which answers
/// with a scripted status or error. Time-based backoff is tested on the spool
/// directly by injecting `now`.
final class HermexLoggerDeliveryTests: XCTestCase {

    // MARK: - fixture

    final class TelemetryURLProtocol: URLProtocol {
        struct Response {
            var status: Int = 200
            var error: Error?
            /// Never answers: models a request whose completion never fires.
            var hang: Bool = false
            /// Answers late: models a callback that arrives after the client
            /// already gave up on it.
            var delay: TimeInterval = 0
        }
        static var script: [Response] = []
        static var bodies: [Data] = []
        static var lock = NSLock()

        static func reset(_ script: [Response]) {
            lock.lock(); defer { lock.unlock() }
            self.script = script
            bodies = []
        }

        static func next() -> Response {
            lock.lock(); defer { lock.unlock() }
            guard !script.isEmpty else { return Response() }
            return script.removeFirst()
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            if let data = request.httpBody ?? request.httpBodyStream.map(Self.drain) {
                Self.lock.lock(); Self.bodies.append(data); Self.lock.unlock()
            }
            let response = Self.next()
            if response.hang { return }
            if let error = response.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let http = HTTPURLResponse(url: request.url!, statusCode: response.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            let deliver = {
                self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8))
                self.client?.urlProtocolDidFinishLoading(self)
            }
            if response.delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: deliver)
            } else {
                deliver()
            }
        }

        override func stopLoading() {}

        private static func drain(_ stream: InputStream) -> Data {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }
    }

    private var directory: URL!
    private var session: URLSession!
    private var spool: TelemetrySpool!
    private var logger: HermexLogger!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("logger-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        spool = TelemetrySpool(directory: directory)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TelemetryURLProtocol.self]
        session = URLSession(configuration: config)
        TelemetryURLProtocol.reset([])
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeLogger(url: URL? = URL(string: "https://example.test"),
                            stalledTimeout: TimeInterval = 30) -> HermexLogger {
        HermexLogger(session: session, spool: spool,
                     serverURLProvider: { url }, stalledTimeout: stalledTimeout, startTimer: false)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 2,
                           _ condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("condition not met: \(description)")
    }

    // MARK: - delivery outcomes

    func testSuccessfulPostRemovesEventFromSpool() {
        TelemetryURLProtocol.reset([.init(status: 200)])
        logger = makeLogger()
        logger.log(type: "event", message: "hello")
        logger.flushNow()
        waitUntil("spool drained") { self.spool.pendingCount == 0 }
        XCTAssertEqual(logger.deliveredBatches, 1)
        XCTAssertEqual(logger.failedBatches, 0)
    }

    func testTimeoutKeepsEventAndCountsFailure() {
        TelemetryURLProtocol.reset([.init(error: URLError(.timedOut))])
        logger = makeLogger()
        logger.log(type: "event", message: "timeout")
        logger.flushNow()
        waitUntil("failure counted") { self.logger.failedBatches == 1 }
        XCTAssertEqual(spool.pendingCount, 1, "an event must survive a timeout")
    }

    func testHTTPErrorKeepsEvent() {
        TelemetryURLProtocol.reset([.init(status: 500)])
        logger = makeLogger()
        logger.log(type: "event", message: "boom")
        logger.flushNow()
        waitUntil("failure counted") { self.logger.failedBatches == 1 }
        XCTAssertEqual(spool.pendingCount, 1)
    }

    func testUnauthorizedKeepsEventInsteadOfDiscardingIt() {
        TelemetryURLProtocol.reset([.init(status: 401)])
        logger = makeLogger()
        logger.log(type: "event", message: "auth")
        logger.flushNow()
        waitUntil("failure counted") { self.logger.failedBatches == 1 }
        XCTAssertEqual(spool.pendingCount, 1, "a 401 must not silently destroy the batch")
    }

    // MARK: - server URL lifecycle

    func testMissingServerURLKeepsEventAndSendsNothing() {
        TelemetryURLProtocol.reset([])
        logger = makeLogger(url: nil)
        logger.log(type: "event", message: "no url")
        logger.flushNow()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(spool.pendingCount, 1)
        XCTAssertTrue(TelemetryURLProtocol.bodies.isEmpty)
    }

    func testServerURLAppearingLaterFlushesQueuedEvents() {
        var url: URL? = nil
        logger = HermexLogger(session: session, spool: spool,
                              serverURLProvider: { url }, startTimer: false)
        TelemetryURLProtocol.reset([.init(status: 200)])
        logger.log(type: "event", message: "queued while offline")
        logger.flushNow()
        XCTAssertEqual(spool.pendingCount, 1)

        url = URL(string: "https://example.test")
        logger.flushNow()
        waitUntil("drained after URL appeared") { self.spool.pendingCount == 0 }
    }

    // MARK: - retry semantics

    func testRetryAfterTransientErrorDeliversOnce() {
        TelemetryURLProtocol.reset([.init(error: URLError(.networkConnectionLost)),
                                    .init(status: 200)])
        logger = makeLogger()
        logger.log(type: "event", message: "retry me")
        logger.flushNow()
        waitUntil("first failure") { self.logger.failedBatches == 1 }
        XCTAssertEqual(spool.pendingCount, 1)

        // The spool holds the event until its backoff window opens.
        let readyNow = spool.ready(limit: 10)
        XCTAssertTrue(readyNow.isEmpty, "event is backing off, not sent on the same tick")

        logger.flushNow() // no-op: backoff not elapsed
        XCTAssertEqual(spool.pendingCount, 1)
    }

    func testRetriedEventKeepsTheSameEventId() {
        TelemetryURLProtocol.reset([.init(error: URLError(.timedOut)), .init(status: 200)])
        logger = makeLogger()
        logger.log(type: "event", message: "same id")
        logger.flushNow()
        waitUntil("first attempt failed") { self.logger.failedBatches == 1 }

        // Force the backoff window open and flush again.
        spool.reschedule(ids: spool.ready(limit: 10).map(\.id), now: Date(timeIntervalSinceNow: -3600))
        let firstBody = TelemetryURLProtocol.bodies.first
        logger.flushNow()
        waitUntil("second attempt succeeded") { self.spool.pendingCount == 0 }

        let ids = TelemetryURLProtocol.bodies.compactMap { body -> String? in
            let object = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]]
            return (object??.first)?["eventId"] as? String
        }
        XCTAssertEqual(ids.count, 2, "two attempts were made")
        XCTAssertEqual(ids.first, ids.last, "the retry must reuse the same eventId")
        XCTAssertNotNil(firstBody)
    }

    func testLongOutageNeverDropsEvents() {
        TelemetryURLProtocol.reset(Array(repeating: .init(error: URLError(.notConnectedToInternet)), count: 5))
        logger = makeLogger()
        for index in 0..<5 {
            logger.log(type: "event", message: "offline \(index)")
        }
        for _ in 0..<5 { logger.flushNow() }
        waitUntil("all attempts failed") { self.logger.failedBatches >= 1 }
        XCTAssertGreaterThanOrEqual(spool.pendingCount, 5,
                                    "a long outage must not delete a single event")
        XCTAssertGreaterThanOrEqual(logger.droppedEventCount, 0)
    }

    func testUnansweredRequestDoesNotWedgeTheSender() {
        TelemetryURLProtocol.reset([.init(hang: true), .init(status: 200)])
        logger = makeLogger(stalledTimeout: 0)
        logger.log(type: "event", message: "hang")
        logger.flushNow()
        waitUntil("first attempt issued") { TelemetryURLProtocol.bodies.count == 1 }
        logger.flushNow()   // stalledTimeout is 0: the sender recovers
        waitUntil("retry issued") { TelemetryURLProtocol.bodies.count >= 2 }
        waitUntil("delivered on retry") { self.spool.pendingCount == 0 }
    }

    func testLateCallbackFromAnAbandonedRequestIsIgnored() {
        // First request answers late; the sender has already timed it out and
        // started a second one. The stale callback must not touch the spool.
        TelemetryURLProtocol.reset([.init(status: 200, delay: 0.3), .init(status: 200)])
        logger = makeLogger(stalledTimeout: 0)
        logger.log(type: "event", message: "late")
        logger.flushNow()
        waitUntil("first request issued") { TelemetryURLProtocol.bodies.count == 1 }
        logger.flushNow()   // orphans the first request, sends the second
        waitUntil("second request issued") { TelemetryURLProtocol.bodies.count >= 2 }
        waitUntil("delivered once") { self.spool.pendingCount == 0 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))  // let the stale callback land
        XCTAssertEqual(spool.pendingCount, 0)
        XCTAssertEqual(logger.deliveredBatches, 1, "a stale 200 must not be counted twice")
    }

    // MARK: - restart

    func testQueueSurvivesRestart() {
        TelemetryURLProtocol.reset([.init(error: URLError(.timedOut))])
        logger = makeLogger()
        logger.log(type: "event", message: "before restart")
        logger.flushNow()
        waitUntil("stored locally") { self.spool.pendingCount == 1 }

        // A fresh spool over the same directory is what a relaunched app sees.
        let reopened = TelemetrySpool(directory: directory)
        XCTAssertEqual(reopened.pendingCount, 1, "an unsent event must survive a relaunch")
        TelemetryURLProtocol.reset([.init(status: 200)])
        let restarted = HermexLogger(session: session, spool: reopened,
                                     serverURLProvider: { URL(string: "https://example.test") },
                                     startTimer: false)
        restarted.flushNow()
        waitUntil("delivered after restart") { reopened.pendingCount == 0 }
    }

    // MARK: - overflow policy

    func testOverflowDropsOldestAndRecordsTheLoss() {
        let small = TelemetrySpool(directory: directory, eventLimit: 2, byteLimit: 4096)
        for index in 0..<4 {
            small.append(eventId: "e-\(index)", json: Data("{\"n\":\(index)}".utf8))
        }
        XCTAssertEqual(small.pendingCount, 2)
        XCTAssertEqual(small.droppedCount, 2)
        let drops = directory.appendingPathComponent("telemetry-drops.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: drops.path),
                      "a drop must leave an independent record")
    }
}

/// Unit tests for the queue itself: ordering, backoff, acknowledgement.
final class TelemetrySpoolTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spool-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testAcknowledgeRemovesOnlyGivenIds() {
        let spool = TelemetrySpool(directory: directory)
        spool.append(eventId: "a", json: Data("{}".utf8))
        spool.append(eventId: "b", json: Data("{}".utf8))
        spool.acknowledge(ids: ["a"])
        XCTAssertEqual(spool.pendingCount, 1)
        XCTAssertEqual(spool.ready(limit: 10).first?.id, "b")
    }

    func testBackoffIsBoundedAndNeverDrops() {
        let spool = TelemetrySpool(directory: directory)
        spool.append(eventId: "x", json: Data("{}".utf8))
        let now = Date()
        for attempt in 1...10 {
            spool.reschedule(ids: ["x"], now: now)
            let item = spool.ready(now: now, limit: 1)
            XCTAssertTrue(item.isEmpty, "attempt \(attempt) must be deferred")
            let future = now.addingTimeInterval(TelemetrySpool.backoff.last! + 1)
            XCTAssertEqual(spool.ready(now: future, limit: 1).count, 1)
        }
        XCTAssertEqual(spool.pendingCount, 1, "retries never delete an event")
        XCTAssertEqual(spool.droppedCount, 0)
    }

    func testExplicitDropIsRecordedSeparately() {
        let spool = TelemetrySpool(directory: directory)
        spool.append(eventId: "y", json: Data("{}".utf8))
        spool.drop(ids: ["y"], reason: "server_rejected_permanently")
        XCTAssertEqual(spool.pendingCount, 0)
        XCTAssertEqual(spool.droppedCount, 1)
        let text = try? String(contentsOf: directory.appendingPathComponent("telemetry-drops.jsonl"), encoding: .utf8)
        XCTAssertTrue(text?.contains("server_rejected_permanently") == true)
    }

    func testOrderIsPreserved() {
        let spool = TelemetrySpool(directory: directory)
        for index in 0..<5 {
            spool.append(eventId: "\(index)", json: Data("{\"i\":\(index)}".utf8))
        }
        XCTAssertEqual(spool.ready(limit: 5).map(\.id), ["0", "1", "2", "3", "4"])
    }

    func testUnwritableDirectoryDoesNotCrashOrLoseTheEventFromMemory() throws {
        let readOnly = directory.appendingPathComponent("ro")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path) }

        let spool = TelemetrySpool(directory: readOnly)
        spool.append(eventId: "kept", json: Data("{}".utf8))
        XCTAssertEqual(spool.pendingCount, 1, "a persist failure must not drop the event")
    }
}


/// Limits, overflow policy and the drop journal.
final class TelemetrySpoolLimitsTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("limits-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func payload(_ bytes: Int, marker: String = "x") -> Data {
        Data("{\"pad\":\"\(marker)\",\"v\":\"\(String(repeating: "a", count: max(0, bytes - 20)))\"}".utf8)
    }

    private func dropRecords() -> [[String: Any]] {
        let file = directory.appendingPathComponent("telemetry-drops.jsonl")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }
    }

    func testEventLimitDropsOldestAndRecordsRange() {
        let spool = TelemetrySpool(directory: directory, eventLimit: 3, byteLimit: 64 * 1024)
        for index in 0..<5 {
            spool.append(eventId: "e\(index)", json: payload(64))
        }
        XCTAssertEqual(spool.pendingCount, 3)
        XCTAssertEqual(spool.ready(limit: 10).map(\.id), ["e2", "e3", "e4"])
        XCTAssertEqual(spool.droppedCount, 2)
        let overflow = dropRecords().filter { ($0["reason"] as? String) == "overflow" }
        XCTAssertEqual(overflow.first?["oldest"] as? String, "e0")
        XCTAssertEqual(overflow.first?["count"] as? Int, 2)
    }

    func testByteLimitTripsBeforeEventLimit() {
        let spool = TelemetrySpool(directory: directory, eventLimit: 100, byteLimit: 1_000)
        for index in 0..<10 {
            spool.append(eventId: "b\(index)", json: payload(300))
        }
        XCTAssertLessThanOrEqual(spool.pendingCount, 4, "byte budget, not the count, must bound the queue")
        XCTAssertLessThanOrEqual(spool.pendingBytes, 1_000)
        XCTAssertGreaterThan(spool.droppedCount, 0)
    }

    func testOversizeEventIsRejectedAndRecorded() {
        let spool = TelemetrySpool(directory: directory, eventLimit: 10, byteLimit: 512)
        let result = spool.append(eventId: "huge", json: payload(2_000))
        XCTAssertEqual(result, .rejectedOversize)
        XCTAssertEqual(spool.pendingCount, 0)
        XCTAssertTrue(dropRecords().contains { ($0["reason"] as? String) == "oversize_event" })
    }

    func testLoadEnforcesBothLimits() throws {
        // Build a spool file that exceeds both budgets, as an older build might.
        var lines = ""
        for index in 0..<20 {
            let record: [String: Any] = ["r": ["id": "old\(index)",
                                                   "json": payload(200).base64EncodedString(),
                                                   "attempts": 0, "nextAttemptAt": 0.0]]
            let data = try JSONSerialization.data(withJSONObject: record)
            lines += String(decoding: data, as: UTF8.self) + "\n"
        }
        try lines.write(to: directory.appendingPathComponent("telemetry-spool.jsonl"), atomically: true, encoding: .utf8)
        let spool = TelemetrySpool(directory: directory, eventLimit: 5, byteLimit: 1_500)
        XCTAssertLessThanOrEqual(spool.pendingCount, 5)
        XCTAssertLessThanOrEqual(spool.pendingBytes, 1_500)
        XCTAssertGreaterThan(spool.droppedCount, 0, "trimming on load is a recorded loss")
    }

    func testDropCountersMatchJournal() {
        let spool = TelemetrySpool(directory: directory, eventLimit: 2, byteLimit: 8 * 1024)
        for index in 0..<6 { spool.append(eventId: "c\(index)", json: payload(80)) }
        let logged = dropRecords().reduce(0) { $0 + (($1["count"] as? Int) ?? 0) }
        XCTAssertEqual(logged, spool.droppedCount - spool.unloggedDropCount)
    }

    func testPersistFailureIsNotReportedAsPersisted() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        let spool = TelemetrySpool(directory: directory, eventLimit: 10, byteLimit: 8 * 1024)
        let result = spool.append(eventId: "ro", json: payload(64))
        XCTAssertEqual(result, .memoryOnly, "a failed write must never claim durability")
        XCTAssertEqual(spool.pendingCount, 1)
        XCTAssertGreaterThan(spool.persistenceFailureCount, 0)
    }

    func testCorruptAndTornLinesAreCounted() throws {
        let good = try JSONSerialization.data(withJSONObject:
            ["r": ["id": "ok", "json": payload(40).base64EncodedString(),
                   "attempts": 0, "nextAttemptAt": 0.0]])
        var text = String(decoding: good, as: UTF8.self) + "\n"
        text += "not-json-at-all\n"
        text += "{\"id\":\"torn\""   // no newline: crash mid-write
        try text.write(to: directory.appendingPathComponent("telemetry-spool.jsonl"), atomically: true, encoding: .utf8)
        let spool = TelemetrySpool(directory: directory, eventLimit: 10, byteLimit: 64 * 1024)
        XCTAssertEqual(spool.pendingCount, 1)
        XCTAssertEqual(spool.droppedCount, 2, "one corrupt line and one torn line")
        XCTAssertTrue(dropRecords().contains { ($0["reason"] as? String) == "corrupt_spool_line" })
    }

    func testDropJournalRotatesAndKeepsOneGeneration() {
        let spool = TelemetrySpool(directory: directory, eventLimit: 1, byteLimit: 8 * 1024, dropLogLimit: 200)
        for index in 0..<40 { spool.append(eventId: "r\(index)", json: payload(64)) }
        let current = directory.appendingPathComponent("telemetry-drops.jsonl")
        let previous = directory.appendingPathComponent("telemetry-drops.1.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.path), "rotation must keep one generation")
        let size = (try? FileManager.default.attributesOfItem(atPath: current.path)[.size] as? Int) ?? 0
        XCTAssertLessThanOrEqual(size, 200, "the journal must stay bounded")
    }

    func testDropJournalOpenFailureCountsUnloggedDrops() throws {
        // A directory where the journal file should be: opening it always fails.
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("telemetry-drops.jsonl"),
                                                withIntermediateDirectories: true)
        let spool = TelemetrySpool(directory: directory, eventLimit: 1, byteLimit: 8 * 1024)
        for index in 0..<5 { spool.append(eventId: "u\(index)", json: payload(64)) }
        XCTAssertGreaterThan(spool.droppedCount, 0)
        XCTAssertGreaterThan(spool.unloggedDropCount, 0, "an unwritable journal must surface as unlogged loss")
    }

    func testRepeatedWriteFailureDoesNotLoopOrGrow() throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("telemetry-drops.jsonl"),
                                                withIntermediateDirectories: true)
        let spool = TelemetrySpool(directory: directory, eventLimit: 1, byteLimit: 8 * 1024)
        for index in 0..<10 { spool.append(eventId: "l\(index)", json: payload(64)) }
        let unloggedAfterFirst = spool.unloggedDropCount
        for index in 10..<20 { spool.append(eventId: "l\(index)", json: payload(64)) }
        XCTAssertGreaterThanOrEqual(spool.unloggedDropCount, unloggedAfterFirst)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            directory.appendingPathComponent("telemetry-drops.1.jsonl").path),
            "a blocked journal must not spawn rotations")
    }

    func testInterruptedDropRotationIsRecovered() throws {
        let rotating = directory.appendingPathComponent("telemetry-drops.rotating")
        try "{\"reason\":\"interrupted\"}\n".write(to: rotating, atomically: true, encoding: .utf8)
        _ = TelemetrySpool(directory: directory, eventLimit: 10, byteLimit: 8 * 1024)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rotating.path))
        let previous = directory.appendingPathComponent("telemetry-drops.1.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.path))
    }

    func testConcurrentAppendsRespectBothBudgets() {
        let spool = TelemetrySpool(directory: directory, eventLimit: 20, byteLimit: 4_000)
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            spool.append(eventId: "p\(index)", json: payload(80))
        }
        XCTAssertLessThanOrEqual(spool.pendingCount, 20)
        XCTAssertLessThanOrEqual(spool.pendingBytes, 4_000)
    }
}
