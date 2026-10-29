// HERMEX-FORK: tests for reliable telemetry delivery (HermexLogger.swift).
//
// The logger used to be fire-and-forget: it removed an event from its memory
// buffer before the POST resolved and ignored the reply, so a network error, a
// 5xx or a force-quit lost diagnostics permanently. These tests pin the new
// contract:
//
//   an event leaves the durable queue only after the server confirms it,
//   an ambiguous reply keeps it, a retry reuses the same identifiers,
//   one bad event cannot block the queue, and the queue cannot grow forever.
//
// Delivery is async (URLSession callback → logger queue), so every assertion
// waits with `waitUntil` instead of assuming a synchronous outcome.

import XCTest
@testable import HermesMobile

final class HermexTelemetryDeliveryTests: XCTestCase {

    private var temp: TempQueueFile!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        temp = TempQueueFile()
        session = makeStubSession()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        temp.cleanup()
        temp = nil
        session = nil
        super.tearDown()
    }

    /// Logger with a long retry delay, so automatic retries never race the
    /// assertions; tests drive delivery explicitly with `flushNowForTesting()`.
    private func makeLogger(maxEvents: Int = 500,
                            retryDelays: [TimeInterval] = [60]) -> HermexLogger {
        let store = TelemetryEventQueue(fileURL: temp.fileURL, maxEvents: maxEvents)
        return HermexLogger(store: store,
                            session: session,
                            serverURLProvider: { URL(string: "http://stub.local")! },
                            flushDebounce: 0,
                            retryDelays: retryDelays)
    }

    private func noNetworkError() -> NSError {
        NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
    }

    // MARK: - 1. Successful send

    func testEventIsRemovedOnlyAfterServerConfirms() {
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 1, stored: 1))
        let logger = makeLogger()

        logger.log(type: "action", message: "tap")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 },
                      "the event should reach the transport")
        XCTAssertTrue(waitUntil { logger.pendingEventsForTesting().isEmpty },
                      "confirmed event must leave the queue")

        let counters = logger.countersSnapshot()
        XCTAssertEqual(counters["eventsConfirmed"] as? Int, 1)
        XCTAssertEqual(counters["eventsDropped"] as? Int, 1)
        XCTAssertEqual(counters["pending"] as? Int, 0)
    }

    /// A confirmed batch is also removed from the file, not just from memory, so
    /// a restart cannot resurrect it.
    func testConfirmedEventIsRemovedFromDisk() {
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 1, stored: 1))
        let logger = makeLogger()

        logger.log(type: "action", message: "tap")
        XCTAssertTrue(waitUntil { logger.pendingEventsForTesting().isEmpty })

        XCTAssertEqual(temp.readRaw().trimmingCharacters(in: .whitespacesAndNewlines), "",
                       "the queue file must be empty after confirmation")
    }

    // MARK: - 2. No network

    func testEventSurvivesWhenNetworkIsDown() {
        StubURLProtocol.fallback = .init(error: noNetworkError())
        let logger = makeLogger()

        logger.log(type: "error", message: "boom")
        logger.log(type: "action", message: "tap")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count >= 1 })
        logger.flushNowForTesting()   // drain any leftovers of the first batch
        logger.drainForTesting()

        XCTAssertEqual(logger.pendingEventsForTesting().count, 2,
                       "nothing may be dropped while offline")
        let lines = temp.readRaw().split(separator: "\n")
        XCTAssertEqual(lines.count, 2, "both events must be on disk")
    }

    // MARK: - 3. Network restored

    func testDeliveryResumesWhenNetworkReturns() {
        StubURLProtocol.fallback = .init(error: noNetworkError())
        let logger = makeLogger()

        logger.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 })
        XCTAssertTrue(waitUntil { logger.isIdleForTesting() })
        XCTAssertTrue(waitUntil { !logger.pendingEventsForTesting().isEmpty })

        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 1, stored: 1))
        logger.flushNowForTesting()

        XCTAssertTrue(waitUntil { logger.pendingEventsForTesting().isEmpty },
                      "the queued event must be delivered once the server answers")
        XCTAssertEqual(StubURLProtocol.receivedBodies.count, 2)
    }

    // MARK: - 4. App restart

    func testQueueIsRestoredAfterRestart() {
        StubURLProtocol.fallback = .init(error: noNetworkError())
        let first = makeLogger()
        first.log(type: "freeze", message: "hang")
        first.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count >= 1 })
        first.drainForTesting()
        let queuedBeforeRestart = first.pendingEventsForTesting().count
        XCTAssertEqual(queuedBeforeRestart, 2)

        // A second logger over the same file stands in for a fresh launch.
        StubURLProtocol.receivedBodies.removeAll()
        StubURLProtocol.reset()
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 2, stored: 2))
        let second = makeLogger()

        XCTAssertTrue(waitUntil { second.pendingEventsForTesting().isEmpty },
                      "restored events must be delivered on the next launch")
        XCTAssertEqual(StubURLProtocol.receivedEventCount, 2,
                       "both restored events go out in one batch")
    }

    /// Restored identifiers are untouched: the same correlationId:seqNo reaches
    /// the server, so its dedup key still matches.
    func testRestorePreservesIdentifiers() {
        StubURLProtocol.fallback = .init(error: noNetworkError())
        let first = makeLogger()
        first.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 })
        first.drainForTesting()

        let before = first.pendingEventsForTesting()
        let originalKey = TelemetryEventQueue.key(for: before[0])
        XCTAssertNotNil(originalKey)

        let second = makeLogger()
        let after = second.pendingEventsForTesting()
        XCTAssertEqual(TelemetryEventQueue.key(for: after[0]), originalKey)
    }

    // MARK: - 5. Killed during a send

    func testEventStaysQueuedWhileTheRequestIsInFlight() {
        // Slow success: the event must still be on disk until the ack lands.
        StubURLProtocol.fallback = .init(status: 200,
                                         body: ackBody(received: 1, stored: 1),
                                         delay: 0.6)
        let logger = makeLogger()

        logger.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 })
        XCTAssertEqual(logger.pendingEventsForTesting().count, 1,
                       "in-flight is not delivered; a kill here must not lose it")

        XCTAssertTrue(waitUntil { logger.pendingEventsForTesting().isEmpty },
                      "after the ack it is removed")
    }

    // MARK: - 6. Server stored it, the reply was lost

    func testLostResponseRetriesWithTheSameIdentifiers() {
        // First attempt: the server "wrote" the event but the client saw a
        // transport error. Second attempt: the server reports it as a duplicate.
        StubURLProtocol.replies = [
            .init(error: noNetworkError()),
            .init(status: 200, body: ackBody(received: 1, stored: 0)),
        ]
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 1, stored: 0))
        let logger = makeLogger(retryDelays: [0.05])

        logger.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil { logger.pendingEventsForTesting().isEmpty },
                      "a duplicate ack still confirms the event")

        let keys = StubURLProtocol.receivedKeys
        XCTAssertGreaterThanOrEqual(keys.count, 2, "must have retried")
        XCTAssertEqual(Set(keys).count, 1,
                       "the retry must reuse correlationId:seqNo or the server would store a duplicate")
    }

    // MARK: - 7. HTTP 5xx

    func testServerErrorIsRetried() {
        StubURLProtocol.replies = [
            .init(status: 500, body: Data()),
            .init(status: 503, body: Data()),
            .init(status: 200, body: ackBody(received: 1, stored: 1)),
        ]
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 1, stored: 1))
        let logger = makeLogger(retryDelays: [0.02, 0.02, 0.02])

        logger.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil(timeout: 8) { logger.pendingEventsForTesting().isEmpty })

        XCTAssertEqual(StubURLProtocol.receivedBodies.count, 3,
                       "two failures then a success")
        XCTAssertEqual(logger.countersSnapshot()["eventsRetried"] as? Int, 2)
    }

    /// The backoff sequence itself, without waiting for real seconds.
    func testBackoffSequenceIsExponentialThenCapped() {
        let delays: [TimeInterval] = [1, 2, 4, 8, 16, 30]
        XCTAssertEqual(HermexLogger.backoffDelay(attempt: 0, delays: delays), 1)
        XCTAssertEqual(HermexLogger.backoffDelay(attempt: 1, delays: delays), 2)
        XCTAssertEqual(HermexLogger.backoffDelay(attempt: 2, delays: delays), 4)
        XCTAssertEqual(HermexLogger.backoffDelay(attempt: 3, delays: delays), 8)
        XCTAssertEqual(HermexLogger.backoffDelay(attempt: 4, delays: delays), 16)
        XCTAssertEqual(HermexLogger.backoffDelay(attempt: 5, delays: delays), 30)
        XCTAssertEqual(HermexLogger.backoffDelay(attempt: 6, delays: delays), 30,
                       "must stay capped at 30 s")
        XCTAssertEqual(HermexLogger.backoffDelay(attempt: 99, delays: delays), 30)
    }

    // MARK: - 8. HTTP 429

    func testRateLimitHonoursRetryAfterHeader() {
        let ok = HTTPURLResponse(url: URL(string: "http://stub.local")!,
                                 statusCode: 429, httpVersion: nil,
                                 headerFields: ["Retry-After": "7"])!
        XCTAssertEqual(HermexLogger.retryAfter(from: ok), 7)

        let clampedLow = HTTPURLResponse(url: URL(string: "http://stub.local")!,
                                         statusCode: 429, httpVersion: nil,
                                         headerFields: ["Retry-After": "0"])!
        XCTAssertEqual(HermexLogger.retryAfter(from: clampedLow), 1,
                       "a zero delay must not turn into a hot loop")

        let clampedHigh = HTTPURLResponse(url: URL(string: "http://stub.local")!,
                                          statusCode: 429, httpVersion: nil,
                                          headerFields: ["Retry-After": "99999"])!
        XCTAssertEqual(HermexLogger.retryAfter(from: clampedHigh), 600,
                       "an absurd delay must not park the queue for hours")

        let garbage = HTTPURLResponse(url: URL(string: "http://stub.local")!,
                                      statusCode: 429, httpVersion: nil,
                                      headerFields: ["Retry-After": "soon"])!
        XCTAssertNil(HermexLogger.retryAfter(from: garbage),
                     "unparseable header falls back to the normal backoff")

        let none = HTTPURLResponse(url: URL(string: "http://stub.local")!,
                                   statusCode: 429, httpVersion: nil,
                                   headerFields: nil)!
        XCTAssertNil(HermexLogger.retryAfter(from: none))
    }

    func testRateLimitIsRetriedNotDropped() {
        StubURLProtocol.replies = [
            .init(status: 429, body: Data(), headers: ["Retry-After": "1"]),
            .init(status: 200, body: ackBody(received: 1, stored: 1)),
        ]
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 1, stored: 1))
        let logger = makeLogger(retryDelays: [0.01])

        logger.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil(timeout: 8) { logger.pendingEventsForTesting().isEmpty })
        XCTAssertEqual(StubURLProtocol.receivedBodies.count, 2,
                       "retried after the server-imposed delay")
    }

    // MARK: - 9. Permanent 4xx

    func testPermanentErrorQuarantinesInsteadOfLooping() {
        StubURLProtocol.fallback = .init(status: 400,
                                         body: Data(#"{"ok":false,"error":"invalid JSON"}"#.utf8))
        let logger = makeLogger(retryDelays: [0.01])

        logger.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 })
        // Give a would-be retry loop time to misbehave.
        logger.drainForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        XCTAssertEqual(StubURLProtocol.receivedBodies.count, 1,
                       "a 400 must not be retried forever")
        let pending = logger.pendingEventsForTesting()
        XCTAssertEqual(pending.count, 1, "the event is kept, not deleted")
        XCTAssertNotNil(pending.first?["deliveryError"],
                        "the rejection reason stays attached as evidence")
        XCTAssertEqual(logger.countersSnapshot()["quarantined"] as? Int, 1)
    }

    /// A quarantine must be recoverable, otherwise a 404 from a deploy in
    /// progress parks the event until eviction, with no way back.
    func testQuarantinedEventGetsAnotherChanceOnTheNextLaunch() {
        StubURLProtocol.fallback = .init(status: 400,
                                         body: Data(#"{"ok":false,"error":"invalid JSON"}"#.utf8))
        let first = makeLogger(retryDelays: [0.01])

        first.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 })
        first.drainForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNotNil(first.pendingEventsForTesting().first?["deliveryError"],
                        "precondition: the event is quarantined")

        // Fix the cause, then relaunch: the event must be attempted again.
        StubURLProtocol.reset()
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 1, stored: 1))
        let second = makeLogger()

        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 },
                      "a quarantined event is retried on the next launch")
        XCTAssertTrue(waitUntil { second.pendingEventsForTesting().isEmpty },
                      "and leaves the queue once the server accepts it")
    }

    /// A quarantined event must not block the rest of the queue.
    func testQuarantinedEventDoesNotBlockTheQueue() {
        // First batch → 400 (quarantined). Everything after → success.
        StubURLProtocol.replies = [
            .init(status: 400, body: Data(#"{"ok":false,"error":"bad"}"#.utf8)),
        ]
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 5, stored: 5))
        let logger = makeLogger(retryDelays: [0.01])

        logger.log(type: "action", message: "poison")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 })
        logger.drainForTesting()

        logger.log(type: "error", message: "good")
        XCTAssertTrue(waitUntil(timeout: 8) {
            let pending = logger.pendingEventsForTesting()
            return pending.count == 1 && pending.first?["type"] as? String == "action"
        }, "the healthy event must get through, leaving only the quarantined one")
    }

    // MARK: - 10. Queue overflow

    func testQueueDropsOldestNonPriorityFirst() {
        let store = TelemetryEventQueue(fileURL: temp.fileURL, maxEvents: 3)
        store.load()

        for index in 1...3 {
            XCTAssertEqual(store.enqueue(event(type: "action", seq: index)), .stored)
        }
        XCTAssertEqual(store.enqueue(event(type: "error", seq: 4)), .stored)

        XCTAssertEqual(store.count, 3, "the cap holds")
        XCTAssertEqual(store.eventsLostToQueueFull, 1)
        let types = store.events.compactMap { $0["type"] as? String }
        XCTAssertEqual(types, ["action", "action", "error"],
                       "the oldest non-priority event was evicted, the error kept")
    }

    func testPriorityEventsSurviveAFloodOfLowValueEvents() {
        let store = TelemetryEventQueue(fileURL: temp.fileURL, maxEvents: 3)
        store.load()

        XCTAssertEqual(store.enqueue(event(type: "freeze", seq: 1)), .stored)
        XCTAssertEqual(store.enqueue(event(type: "error", seq: 2)), .stored)
        XCTAssertEqual(store.enqueue(event(type: "freeze", seq: 3)), .stored)
        for seq in 4...6 {
            XCTAssertEqual(store.enqueue(event(type: "action", seq: seq)), .stored)
        }

        let types = store.events.compactMap { $0["type"] as? String }
        XCTAssertEqual(types, ["freeze", "error", "freeze"],
                       "priority events must never be evicted for action events")
    }

    func testQueueFullOfPriorityRefusesANonPriorityEvent() {
        let store = TelemetryEventQueue(fileURL: temp.fileURL, maxEvents: 2)
        store.load()

        XCTAssertEqual(store.enqueue(event(type: "freeze", seq: 1)), .stored)
        XCTAssertEqual(store.enqueue(event(type: "error", seq: 2)), .stored)
        XCTAssertEqual(store.enqueue(event(type: "action", seq: 3)), .refusedQueueFull)

        XCTAssertEqual(store.count, 2, "both priority events are intact")
        XCTAssertEqual(store.eventsLostToQueueFull, 1)
    }

    func testQueueFullOfPriorityEvictsOldestPriorityForNewPriority() {
        let store = TelemetryEventQueue(fileURL: temp.fileURL, maxEvents: 2)
        store.load()

        XCTAssertEqual(store.enqueue(event(type: "freeze", seq: 1)), .stored)
        XCTAssertEqual(store.enqueue(event(type: "freeze", seq: 2)), .stored)
        XCTAssertEqual(store.enqueue(event(type: "freeze", seq: 3)), .stored)

        let seqs = store.events.compactMap { $0["seqNo"] as? Int }
        XCTAssertEqual(seqs, [2, 3], "oldest priority event goes last")
        XCTAssertEqual(store.eventsLostToQueueFull, 1)
    }

    func testOversizedEventIsRefused() {
        let store = TelemetryEventQueue(fileURL: temp.fileURL, maxEvents: 10)
        store.load()

        let huge = String(repeating: "x", count: TelemetryEventQueue.maxEncodedEventBytes + 1024)
        let result = store.enqueue([
            "type": "error", "seqNo": 1, "correlationId": "c",
            "message": huge,
        ])
        XCTAssertEqual(result, .refusedOversized)
        XCTAssertEqual(store.count, 0)
    }

    // MARK: - 11. Corrupt storage

    func testCorruptLineDoesNotDestroyTheQueue() {
        let good1 = #"{"type":"error","seqNo":1,"correlationId":"c","message":"one"}"#
        let good2 = #"{"type":"freeze","seqNo":2,"correlationId":"c","message":"two"}"#
        // Second line is a torn write: a truncated JSON object.
        temp.writeRaw("\(good1)\n{\"type\":\"error\",\"seqNo\":9,\"correl\n\(good2)\n")

        let store = TelemetryEventQueue(fileURL: temp.fileURL)
        store.load()

        XCTAssertEqual(store.count, 2, "both intact lines must survive")
        XCTAssertEqual(store.eventsLostToCorruption, 1, "the torn line is counted, not silently ignored")
        XCTAssertEqual(store.events.compactMap { $0["seqNo"] as? Int }, [1, 2])
    }

    func testMissingQueueFileIsNotAnError() {
        let store = TelemetryEventQueue(
            fileURL: temp.directory.appendingPathComponent("does-not-exist.jsonl"))
        store.load()
        XCTAssertEqual(store.count, 0)
    }

    /// A queue restored after a crash mid-append must still accept new events.
    func testQueueIsWritableAfterRecoveryFromTornLine() {
        let good = #"{"type":"error","seqNo":1,"correlationId":"c","message":"one"}"#
        temp.writeRaw("\(good)\n{\"type\":\"err")
        let store = TelemetryEventQueue(fileURL: temp.fileURL)
        store.load()
        XCTAssertEqual(store.count, 1)

        XCTAssertEqual(store.enqueue(event(type: "error", seq: 2)), .stored)
        XCTAssertEqual(store.count, 2)

        let reread = TelemetryEventQueue(fileURL: temp.fileURL)
        reread.load()
        XCTAssertEqual(reread.count, 2)
        XCTAssertEqual(reread.eventsLostToCorruption, 0,
                       "the load normalised the file, so the new append is clean")
    }

    // MARK: - 12. Concurrent events

    func testConcurrentEventsKeepOrderAndUniqueness() {
        StubURLProtocol.fallback = .init(error: noNetworkError())
        let logger = makeLogger(maxEvents: 500)

        let group = DispatchGroup()
        for worker in 0..<8 {
            DispatchQueue.global().async(group: group) {
                for index in 0..<25 {
                    logger.log(type: "action", message: "w\(worker)-\(index)")
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        logger.drainForTesting()
        XCTAssertTrue(waitUntil { logger.pendingEventsForTesting().count == 200 },
                      "all 200 events must be queued")

        let events = logger.pendingEventsForTesting()
        let seqs = events.compactMap { $0["seqNo"] as? Int }
        XCTAssertEqual(seqs.count, 200, "no event lost in the race")
        XCTAssertEqual(Set(seqs).count, 200, "no duplicated sequence number")
        XCTAssertEqual(seqs, seqs.sorted(), "queue order must match enqueue order")

        let correlations = Set(events.compactMap { $0["correlationId"] as? String })
        XCTAssertEqual(correlations.count, 1, "one correlationId per app launch")
    }

    // MARK: - 13. Resend after server restart

    /// The client-side half of the server-restart guarantee: a resend carries
    /// the original `correlationId:seqNo`, so the server's persisted dedup
    /// window recognises it. (The server half is covered by test_server.py.)
    func testResendAfterServerRestartUsesThePersistedDedupKey() {
        StubURLProtocol.replies = [
            .init(status: 500, body: Data()),
            .init(status: 200, body: ackBody(received: 1, stored: 0)),
        ]
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 1, stored: 0))
        let logger = makeLogger(retryDelays: [0.02])

        logger.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil(timeout: 8) { logger.pendingEventsForTesting().isEmpty })

        let keys = StubURLProtocol.receivedKeys
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1], "the dedup key is stable across retries")
    }

    // MARK: - 14. Incompatible server response

    func testUnparseableSuccessBodyKeepsTheEvent() {
        StubURLProtocol.fallback = .init(status: 200, body: Data("not json".utf8))
        let logger = makeLogger()

        logger.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 })
        logger.drainForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(logger.pendingEventsForTesting().count, 1,
                       "a 2xx we cannot read is not a confirmation")
    }

    func testOkFalseKeepsTheEvent() {
        StubURLProtocol.fallback = .init(status: 200,
                                         body: Data(#"{"ok":false,"error":"nope"}"#.utf8))
        let logger = makeLogger()

        logger.log(type: "error", message: "boom")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 })
        logger.drainForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(logger.pendingEventsForTesting().count, 1)
    }

    func testConfirmedCountBelowBatchKeepsTheRemainder() {
        // 3 events; the server accounts for only 2. The follow-up attempt gets
        // `received: 0`, so the unconfirmed tail is forced to stay put.
        StubURLProtocol.replies = [
            .init(status: 200, body: ackBody(received: 2, stored: 2)),
        ]
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 0, stored: 0))
        let logger = makeLogger()

        logger.log(type: "error", message: "a")
        logger.log(type: "error", message: "b")
        logger.log(type: "error", message: "c")
        XCTAssertTrue(waitUntil { StubURLProtocol.receivedBodies.count == 1 })
        XCTAssertTrue(waitUntil { logger.isIdleForTesting() })
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let remaining = logger.pendingEventsForTesting()
        XCTAssertEqual(remaining.count, 1,
                       "only the confirmed head of the batch is removed")
        XCTAssertEqual(remaining.first?["message"] as? String, "c",
                       "the unconfirmed tail stays")
    }

    func testOversizedBatchShrinksAndSucceeds() {
        StubURLProtocol.replies = [
            .init(status: 413, body: Data(#"{"ok":false,"error":"payload too large"}"#.utf8)),
        ]
        StubURLProtocol.fallback = .init(status: 200, body: ackBody(received: 20, stored: 20))
        let logger = makeLogger(retryDelays: [0.01])

        for index in 0..<20 {
            logger.log(type: "error", message: "e\(index)")
        }
        XCTAssertTrue(waitUntil(timeout: 8) { logger.pendingEventsForTesting().isEmpty },
                      "after shrinking the batch the events still go out")
        XCTAssertGreaterThanOrEqual(StubURLProtocol.receivedBodies.count, 2)
    }

    // MARK: - 15. Disk write failure

    func testEventIsNotLostWhenTheDiskWriteFails() {
        // A path under /dev/null can never be a directory, so every write fails.
        let unwritable = URL(fileURLWithPath: "/dev/null/hermex-queue/pending-events.jsonl")
        let store = TelemetryEventQueue(fileURL: unwritable)
        let logger = HermexLogger(store: store,
                                  session: session,
                                  serverURLProvider: { URL(string: "http://stub.local")! },
                                  flushDebounce: 0,
                                  retryDelays: [60])

        logger.log(type: "error", message: "boom")
        logger.drainForTesting()

        XCTAssertEqual(logger.undeliveredInMemoryCountForTesting(), 1,
                       "the event is held in memory, not discarded")
        XCTAssertEqual(store.count, 0, "nothing was claimed as stored")
    }

    // MARK: - Classification table

    func testClassifyCoversTheServerContract() {
        let request = URLRequest(url: URL(string: "http://stub.local/webhook/hermex-logs")!)
        _ = request

        func response(_ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "http://stub.local")!,
                            statusCode: status, httpVersion: nil, headerFields: nil)!
        }

        // Confirmed
        XCTAssertEqual(
            HermexLogger.classify(data: ackBody(received: 2, stored: 2),
                                  response: response(200), error: nil, batchCount: 2),
            .confirmed(2))
        // Duplicates: stored 0 but received 2 → still a confirmation
        XCTAssertEqual(
            HermexLogger.classify(data: ackBody(received: 2, stored: 0),
                                  response: response(200), error: nil, batchCount: 2),
            .confirmed(2))
        // Partial
        XCTAssertEqual(
            HermexLogger.classify(data: ackBody(received: 1, stored: 1),
                                  response: response(200), error: nil, batchCount: 2),
            .confirmed(1))
        // Transport error → retry
        XCTAssertEqual(
            HermexLogger.classify(data: nil, response: nil,
                                  error: NSError(domain: NSURLErrorDomain, code: -1009),
                                  batchCount: 1),
            .retryable(retryAfter: nil))
        // Too large → shrink
        XCTAssertEqual(
            HermexLogger.classify(data: Data(), response: response(413),
                                  error: nil, batchCount: 20),
            .batchTooLarge)
        // Server errors → retry
        XCTAssertEqual(
            HermexLogger.classify(data: Data(), response: response(500),
                                  error: nil, batchCount: 1),
            .retryable(retryAfter: nil))
        // Permanent
        XCTAssertEqual(
            HermexLogger.classify(data: Data(), response: response(400),
                                  error: nil, batchCount: 1),
            .permanent(reason: "http 400"))
        XCTAssertEqual(
            HermexLogger.classify(data: Data(), response: response(401),
                                  error: nil, batchCount: 1),
            .permanent(reason: "http 401"))
    }

    // MARK: - Helpers

    private func event(type: String, seq: Int) -> [String: Any] {
        ["type": type, "seqNo": seq, "correlationId": "test-corr",
         "message": "\(type)-\(seq)", "ts": Date().timeIntervalSince1970]
    }
}
